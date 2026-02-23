import Foundation
import MapKit
import CoreLocation

/// The result of checking a venue's website for category-relevant keywords.
enum WebsiteCheckResult: Equatable {
    /// Keywords were found — high confidence the venue carries this item.
    /// Associated value is the FoodCategory whose keywords matched.
    case confirmed(FoodCategory)
    /// The website was reachable but no keywords matched.
    case notFound
    /// No website URL available, the fetch failed, or the response was unreadable.
    case unavailable
}

/// Result of checking a venue's website against ALL of the user's active picks.
/// Used by the ghost pin sheet to show which picks were found on the website.
struct MultiCategoryCheckResult: Equatable {
    /// Categories (from the user's active picks) confirmed on the website.
    let confirmed: [FoodCategory]
    /// Categories checked but not found.
    let notFound: [FoodCategory]
    /// The primary category (the one that produced the ghost pin).
    let primaryPick: FoodCategory
    /// Full 3-pass result for the primary pick specifically.
    let primaryResult: WebsiteCheckResult
    /// True when no website URL was available at all.
    let websiteUnavailable: Bool
}

/// Fetches a venue's website in the background and searches the raw HTML for
/// category keywords. Used to add confidence context to ghost pin suggestions
/// without requiring any user action.
///
/// URL source: mapItem.url — populated by Apple Maps for map-feature taps.
/// MKLocalSearch results often have no URL, so those return .unavailable.
///
/// Caching strategy:
///   Every fetch scans ALL FoodCategory keywords at once and stores the full set
///   of matched category IDs per URL. Any subsequent per-category query is answered
///   instantly from cache without re-fetching — regardless of which filter
///   was active when the page was first loaded.
///
/// Limitations (known and accepted):
///   • JS-rendered pages (React, Vue, etc.) won't include dynamic menu content
///   • Follows up to 5 menu-related subpage links (depth-2: includes links found on subpages)
///   Expected result: ~30–40% .confirmed on genuinely relevant venues,
///   majority .unavailable or .notFound — treated as "ask the user" fallback.
actor WebsiteCheckService {

    // Session for fetching restaurant websites — includes a browser User-Agent
    // because many sites (Joomla, Wix, etc.) return 403 without one.
    private let webSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 8
        config.timeoutIntervalForResource = 10
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        ]
        return URLSession(configuration: config)
    }()

    // Plain session for Brave API calls — no custom User-Agent so the
    // API key header isn't interfered with.
    private let apiSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 8
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    /// HTML cache: URL string → set of matched FoodCategory IDs (empty set = page
    /// fetched with no matches). nil entry = page not yet fetched.
    private var htmlCache: [String: Set<String>] = [:]

    /// Tracks which URLs were detected as JS-heavy (homepage was a JS shell).
    /// Used so cache hits in `checkWithBraveSearch` can still expand Pass 2.
    private var jsHeavyCache: Set<String> = []

    /// Brave Search cache: venue name+city+state query → discovered website URL.
    private var braveCache: [String: URL] = [:]

    /// Maximum number of subpages to crawl per venue (homepage doesn't count).
    /// 5 is enough for lunch/dinner/drinks/dessert/location-specific menus
    /// while staying under ~6 seconds total even on slow hosts.
    private let maxSubpageCrawls = 5

    // MARK: - Public API

    /// Returns a cached result instantly if the URL has been scanned before.
    /// Returns nil if the URL has never been fetched (caller should run a full check).
    /// Call this before checkWithBraveSearch to avoid unnecessary network calls.
    func cachedResult(for urlString: String, pick: FoodCategory) -> WebsiteCheckResult? {
        guard let matched = htmlCache[urlString] else { return nil }
        // Cache hit — check whether the requested category was matched
        if matched.contains(pick.id) {
            return .confirmed(pick)
        }
        return .notFound
    }

    /// Homepage-only scan for batch pre-screening ghost pins.
    /// Fetches homepages concurrently, scans for all category keywords, and
    /// returns matched category IDs per suggestion ID.
    /// NO Brave API calls. NO subpage crawling. Homepage only for speed.
    ///
    /// Results are filtered to the user's active picks so that only relevant
    /// categories appear as "likely" on the map. The underlying htmlCache still
    /// stores all 20 categories so a later full check gets a free cache hit.
    func batchPreScreen(
        suggestions: [SuggestedSpot],
        picks: [FoodCategory]
    ) async -> [String: Set<String>] {
        let pickIDs = Set(picks.map(\.id))
        var results: [String: Set<String>] = [:]

        // Separate into cached (instant) and needs-fetch
        var toFetch: [(id: String, url: URL)] = []

        for suggestion in suggestions {
            guard let url = suggestion.mapItem.url,
                  !isSocialMediaURL(url) else {
                continue
            }
            let key = url.absoluteString
            if let cached = htmlCache[key] {
                // Already scanned — filter to user's picks
                let relevant = cached.intersection(pickIDs)
                if !relevant.isEmpty {
                    results[suggestion.id] = relevant
                }
            } else {
                toFetch.append((id: suggestion.id, url: url))
            }
        }

        // Fetch uncached homepages concurrently (max 10 at a time)
        if !toFetch.isEmpty {
            let fetched = await withTaskGroup(
                of: (String, URL, Set<String>)?.self,
                returning: [(String, URL, Set<String>)].self
            ) { group in
                // Limit concurrency to 10 by batching
                var pending = 0
                var index = 0
                var collected: [(String, URL, Set<String>)] = []

                while index < toFetch.count {
                    while pending < 10 && index < toFetch.count {
                        let item = toFetch[index]
                        index += 1
                        pending += 1
                        group.addTask { [self] in
                            guard let (html, isValid) = await self.fetchPage(item.url),
                                  isValid else {
                                return nil
                            }
                            let matched = await self.scanForCategories(in: html)
                            return (item.id, item.url, matched)
                        }
                    }
                    // Wait for one to finish before adding more
                    if let result = await group.next() {
                        pending -= 1
                        if let r = result { collected.append(r) }
                    }
                }
                // Drain remaining
                for await result in group {
                    if let r = result { collected.append(r) }
                }
                return collected
            }

            // Cache results and filter to picks
            for (id, url, matched) in fetched {
                htmlCache[url.absoluteString] = matched
                let relevant = matched.intersection(pickIDs)
                if !relevant.isEmpty {
                    results[id] = relevant
                }
            }
        }

        print("[PreScreen] scanned \(toFetch.count) homepages, \(results.count) likely matches")
        return results
    }

    /// Check a single tapped venue — uses Brave Search as fallback when
    /// Apple Maps has no URL. Only call this for single user-initiated taps,
    /// never in a batch loop.
    ///
    /// Three-pass strategy:
    ///   Pass 1 — scan homepage + menu subpage HTML for category keywords
    ///            (fast, no API cost). Uses word-boundary regex to avoid
    ///            substring false positives (e.g. "flank" matching "flan").
    ///   Pass 2 — site-scoped Brave Search: `flan site:domain.com`
    ///            Normally tries first 2 keywords (up to 2 API calls).
    ///            On JS-heavy sites (detected by Pass 1), tries ALL keywords
    ///            since HTML scanning is unreliable on client-rendered pages.
    ///   Pass 3 — broad web search: `flan "Venue Name"` (no site: restriction).
    ///            Only runs when NO website URL exists. Skipped when a URL is
    ///            available because review sites and aggregators produce false
    ///            positives by mentioning food terms near unrelated venue names.
    ///
    /// - Parameters:
    ///   - pick: The FoodCategory to check keywords for.
    ///   - knownURL: Optional stored websiteURL from the Spot model, used when
    ///               MKMapItem.url is nil (e.g. when called from SpotDetailView).
    func checkWithBraveSearch(_ mapItem: MKMapItem, for pick: FoodCategory,
                               knownURL: String? = nil) async -> WebsiteCheckResult {
        let (result, _) = await checkWithBraveSearchReturningURL(mapItem, for: pick, knownURL: knownURL)
        return result
    }

    /// Internal implementation of the 3-pass check that also returns the resolved URL.
    /// `checkAllPicks` uses the returned URL to look up the HTML cache for secondary
    /// picks, avoiding a duplicate URL resolution that could diverge from the primary.
    private func checkWithBraveSearchReturningURL(
        _ mapItem: MKMapItem, for pick: FoodCategory,
        knownURL: String? = nil
    ) async -> (WebsiteCheckResult, URL?) {
        let venueName = mapItem.name ?? ""
        print("[WebCheck] \(venueName): checking \(pick.displayName)")

        let url = await resolveURL(mapItem: mapItem, knownURL: knownURL)
        print("[WebCheck]   url=\(url?.absoluteString ?? "nil")")

        // Pass 1: homepage HTML scan — scans ALL categories at once, caches results.
        // Then checks if the requested pick was matched.
        var jsHeavy = false
        var pass1FoundOtherCategories = false
        if let url {
            // Check cache first before fetching
            let key = url.absoluteString
            if let cached = htmlCache[key] {
                if cached.contains(pick.id) { return (.confirmed(pick), url) }
                // Cache says page was fetched but pick not found — fall through to Brave passes.
                // Restore JS-heavy flag from cache so Pass 2 behaves consistently.
                jsHeavy = jsHeavyCache.contains(key)
                pass1FoundOtherCategories = !cached.isEmpty
            } else {
                // Not cached — fetch and scan all categories
                let (scanned, isJSHeavy) = await fetchAndScanAllCategories(url)
                jsHeavy = isJSHeavy
                pass1FoundOtherCategories = !scanned.isEmpty
                print("[WebCheck]   Pass 1: \(scanned.isEmpty ? "no matches" : "matched: \(scanned)")\(jsHeavy ? " (JS-heavy → expanded Pass 2)" : "")")
                if let fresh = htmlCache[key], fresh.contains(pick.id) {
                    return (.confirmed(pick), url)
                }
            }

            // Pass 2: site-scoped Brave Search for the specific pick.
            // Normal sites: try first 2 keywords (e.g. "mezcal" then "agave").
            // JS-heavy sites: try ALL keywords since HTML scanning is unreliable
            // on React/Vue/Toast pages where the real menu content is rendered
            // client-side. Brave's index includes JS-rendered content.
            //
            // Skip Pass 2 entirely when:
            //   a) Chain/multi-location domains with 4+ path segments — `site:domain`
            //      searches thousands of unrelated pages (Dunkin' false positive).
            //   b) Pass 1 found OTHER categories but NOT this pick — the HTML is
            //      clearly readable, so if the keyword isn't there, it's not on
            //      the menu. Brave may still index SEO metadata, review snippets,
            //      or cross-referenced content that mentions the keyword without
            //      the venue actually serving it (Tuxpan/Cielito false positive).
            let domain = url.host ?? ""
            let pathSegments = url.pathComponents.filter { $0 != "/" }
            let isChainLocationPage = pathSegments.count >= 4
            let htmlWorkedButPickMissing = pass1FoundOtherCategories && !jsHeavy
            if !domain.isEmpty, !isChainLocationPage, !htmlWorkedButPickMissing {
                let keywordsToTry = jsHeavy
                    ? pick.websiteKeywords           // all keywords — JS site, HTML unreliable
                    : Array(pick.websiteKeywords.prefix(2))  // normal — first 2 is enough
                for keyword in keywordsToTry {
                    let query = "\(keyword) site:\(domain)"
                    let found = await braveSearchHasResults(query: query)
                    if found {
                        print("[WebCheck]   Pass 2 HIT: \(query)")
                        return (.confirmed(pick), url)
                    }
                }
            } else if isChainLocationPage {
                print("[WebCheck]   Pass 2: SKIPPED (chain location page)")
            } else if htmlWorkedButPickMissing {
                print("[WebCheck]   Pass 2: SKIPPED (HTML readable, found other categories but not \(pick.displayName))")
            }
        }

        // Pass 3: venue-name + keyword web search (no site: restriction).
        // Only run when we have NO website URL at all. When a URL exists but
        // Passes 1–2 didn't find the keyword, a broad web search produces too
        // many false positives from review sites and aggregators that mention
        // both the venue name and common food terms on the same page.
        if url == nil, !venueName.isEmpty {
            if let keyword = pick.websiteKeywords.first {
                let query = "\(keyword) \"\(venueName)\""
                let found = await braveSearchHasResults(query: query)
                if found {
                    print("[WebCheck]   Pass 3 HIT: \(query)")
                    return (.confirmed(pick), url)
                }
            }
        }

        let result: WebsiteCheckResult = url == nil ? .unavailable : .notFound
        print("[WebCheck]   \(venueName): \(pick.displayName) → \(result)")
        return (result, url)
    }

    /// Check a venue against ALL of the user's active picks at once.
    ///
    /// Cost strategy (critical for API budget):
    ///   - Pass 1 (HTML scan) is free and checks all 20 categories in one fetch.
    ///   - Pass 2/3 (Brave Search) run ONLY for `primaryPick`.
    ///     Normal sites: up to 2 keyword searches. JS-heavy sites: up to ~7.
    ///   - All other picks are checked against the HTML cache only (zero cost).
    func checkAllPicks(_ mapItem: MKMapItem,
                       picks: [FoodCategory],
                       primaryPick: FoodCategory,
                       knownURL: String? = nil) async -> MultiCategoryCheckResult {
        // Run the full 3-pass check for the primary pick.
        // This populates htmlCache with ALL category matches from Pass 1.
        // Also returns the resolved URL so we can look up the cache for
        // secondary picks without re-resolving (which could diverge).
        let (primaryResult, url) = await checkWithBraveSearchReturningURL(
            mapItem, for: primaryPick, knownURL: knownURL
        )

        // Build the combined set of picks to check: user's active picks + primaryPick.
        // The primary pick may not be in the user's active picks (e.g. ghost pin was
        // produced by mezcal search, but the user's picks are flan + birria). We must
        // always include the primary pick in the result so the UI can show it.
        var allPicks = picks
        if !allPicks.contains(primaryPick) {
            allPicks.insert(primaryPick, at: 0)
        }

        // Check all picks against the HTML cache (zero API cost).
        var confirmed: [FoodCategory] = []
        var notFound: [FoodCategory] = []

        for pick in allPicks {
            if pick == primaryPick {
                if case .confirmed = primaryResult {
                    confirmed.append(pick)
                } else {
                    notFound.append(pick)
                }
                continue
            }
            // Non-primary picks: cache-only check
            if let url, let cached = cachedResult(for: url.absoluteString, pick: pick) {
                if case .confirmed = cached {
                    confirmed.append(pick)
                } else {
                    notFound.append(pick)
                }
            } else {
                notFound.append(pick)
            }
        }

        print("[WebCheck] allPicks: confirmed=\(confirmed.map(\.id)), notFound=\(notFound.map(\.id))")

        return MultiCategoryCheckResult(
            confirmed: confirmed,
            notFound: notFound,
            primaryPick: primaryPick,
            primaryResult: primaryResult,
            websiteUnavailable: url == nil
        )
    }

    // MARK: - Private helpers

    /// Single source of truth for URL resolution. Both `checkWithBraveSearch` and
    /// `checkAllPicks` use this — never duplicate this logic.
    ///
    /// Priority: mapItem.url → stored knownURL → Brave Search discovery.
    /// Social media / aggregator URLs are skipped at each stage.
    private func resolveURL(mapItem: MKMapItem, knownURL: String?) async -> URL? {
        if let rawURL = mapItem.url, !isSocialMediaURL(rawURL) {
            return upgradeToHTTPS(rawURL)
        }
        if let stored = knownURL, let storedURL = URL(string: stored), !isSocialMediaURL(storedURL) {
            return upgradeToHTTPS(storedURL)
        }
        return await websiteURL(for: mapItem)
    }

    /// Fetches homepage HTML, scans for ALL FoodCategory keywords, then follows
    /// menu-related subpage links — including **depth-2 links** found on
    /// subpages themselves (critical for multi-location sites like Lolita where
    /// homepage → /fort-point/ → /fort-point-menu/).
    ///
    /// All results are merged into a single cache entry keyed by the original URL.
    /// Returns (matched category IDs, looksJSHeavy). The JS flag tells the caller
    /// to try more Brave Search keywords in Pass 2, since HTML scanning is unreliable
    /// on JS-rendered sites (React, Vue, Toast, etc.).
    private func fetchAndScanAllCategories(_ url: URL) async -> (Set<String>, Bool) {
        let key = url.absoluteString

        // Step 1: fetch and scan the homepage
        guard let (homeHTML, isValid) = await fetchPage(url), isValid else {
            htmlCache[key] = []
            return ([], false)
        }
        var matched = scanForCategories(in: homeHTML)

        // Detect JS-heavy pages: high script-to-content ratio suggests the real
        // menu content is rendered client-side and invisible to our HTML scan.
        // Only flagged when the homepage itself has few matches — if we already
        // found categories, the HTML is clearly working fine.
        let looksJSHeavy: Bool
        if matched.isEmpty {
            let lower = homeHTML.lowercased()
            let scriptCount = lower.components(separatedBy: "<script").count - 1
            let bodyText = lower.replacingOccurrences(
                of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression
            ).replacingOccurrences(
                of: "<[^>]+>", with: "", options: .regularExpression
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            // JS-heavy heuristic: many script tags and very little visible text
            // after stripping scripts/tags. Typical for React/Vue/Toast shells.
            looksJSHeavy = scriptCount >= 5 && bodyText.count < 2000
        } else {
            looksJSHeavy = false
        }

        // Step 2: find menu-related links on the homepage
        var menuURLs = extractMenuLinks(from: homeHTML, baseURL: url)

        // Track all URLs we've already fetched or queued to avoid duplicates
        var fetched = Set<String>([key])
        var crawlCount = 0

        // Process the queue — new depth-2 links are appended to menuURLs as we go
        var index = 0
        while index < menuURLs.count && crawlCount < maxSubpageCrawls {
            let menuURL = menuURLs[index]
            index += 1

            let menuKey = menuURL.absoluteString
            guard !fetched.contains(menuKey) else { continue }
            fetched.insert(menuKey)

            // Check if already cached from a previous check
            if let cached = htmlCache[menuKey] {
                matched.formUnion(cached)
                crawlCount += 1
                continue
            }

            guard let (subHTML, subValid) = await fetchPage(menuURL), subValid else {
                crawlCount += 1
                continue
            }
            let subMatched = scanForCategories(in: subHTML)
            htmlCache[menuKey] = subMatched
            matched.formUnion(subMatched)
            crawlCount += 1
            print("[WebCheck]   subpage \(menuURL.path): \(subMatched.isEmpty ? "0" : "\(subMatched.count)") matches")

            // Depth-2: if this subpage has its own menu links we haven't seen,
            // append them to the queue. This handles multi-location sites where
            // homepage → /location/ → /location/menu/.
            if crawlCount < maxSubpageCrawls {
                let depth2Links = extractMenuLinks(from: subHTML, baseURL: menuURL)
                for link in depth2Links where !fetched.contains(link.absoluteString) {
                    menuURLs.append(link)
                }
            }
        }

        htmlCache[key] = matched
        if looksJSHeavy { jsHeavyCache.insert(key) }
        let jsNote = looksJSHeavy ? " (JS-heavy)" : ""
        print("[WebCheck]   scan done: \(crawlCount) subpages, \(matched.count) categories: \(matched)\(jsNote)")
        return (matched, looksJSHeavy)
    }

    /// Fetches a single page. Returns (html, isValid) or nil on failure.
    /// isValid is false when the page is a captcha / bot wall.
    private func fetchPage(_ url: URL) async -> (String, Bool)? {
        // Upgrade http → https to avoid ATS blocks.  Many Apple Maps URLs are
        // stored as http:// even though the site supports https://.
        var fetchURL = url
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           components.scheme == "http" {
            components.scheme = "https"
            if let upgraded = components.url {
                fetchURL = upgraded
            }
        }
        do {
            let (data, response) = try await webSession.data(from: fetchURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let html = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""
            guard !html.isEmpty else { return nil }
            let lower = html.lowercased()

            let isCaptchaWall = lower.contains("captcha-delivery.com") ||
                                lower.contains("enable js and disable any ad blocker") ||
                                lower.contains("cf-browser-verification") ||
                                (html.count < 2000 && lower.contains("cloudflare"))
            return (html, !isCaptchaWall)
        } catch {
            return nil
        }
    }

    /// Scans raw HTML for all FoodCategory keywords and returns matched category IDs.
    /// Uses word-boundary matching (`\b`) so that short keywords like "flan" don't
    /// false-positive on "flank steak", "flannel", CSS class names, etc.
    private func scanForCategories(in html: String) -> Set<String> {
        let lower = html.lowercased()
        var matched = Set<String>()
        for category in FoodCategory.allCategories {
            for keyword in category.websiteKeywords {
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword.lowercased()))\\b"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                    // Fall back to contains() if regex fails (shouldn't happen)
                    if lower.contains(keyword.lowercased()) {
                        matched.insert(category.id)
                        break
                    }
                    continue
                }
                let range = NSRange(lower.startIndex..., in: lower)
                if regex.firstMatch(in: lower, range: range) != nil {
                    matched.insert(category.id)
                    break
                }
            }
        }
        return matched
    }

    /// Parses HTML for same-domain href values whose **URL path** or **visible
    /// link text** contains a menu-related term.
    ///
    /// Key design decisions (hard-won through debugging):
    ///   • Only matches menu terms in **visible text** (between `>` and `<`), NOT
    ///     inside HTML attributes like `data-menu-type` or `class="menu-toggle"`.
    ///     Previous version matched attributes, causing `/about/` and other junk
    ///     pages to burn limited crawl slots.
    ///   • Results are **priority-sorted**: path-match links (e.g. `/menu/`) rank
    ///     above text-only matches (e.g. `<a href="/fort-point">Menu</a>`).
    ///     This ensures the most promising pages are crawled first.
    ///   • Skips obvious non-content paths (`/about`, `/contact`, `/careers`, etc.)
    ///     to avoid wasting crawl slots on pages that never have food keywords.
    private func extractMenuLinks(from html: String, baseURL: URL) -> [URL] {
        let menuTerms = [
            "menu", "food", "dessert", "drink", "dinner", "lunch",
            "brunch", "cocktail", "wine-list", "bar-menu", "dine"
        ]

        // Paths that almost never contain menu content — skip to save crawl slots.
        let skipPaths = [
            "/about", "/contact", "/careers", "/jobs", "/press",
            "/privacy", "/terms", "/faq", "/blog", "/news",
            "/events", "/gallery", "/photos", "/team", "/story",
        ]

        // Match <a…href="URL"…>VISIBLE TEXT</a>, capturing the href value and the
        // visible text between > and </a>. Uses non-greedy matching for attributes.
        // Also handles self-contained href with nearby visible text via fallback.
        guard let anchorRegex = try? NSRegularExpression(
            pattern: #"<a\s[^>]*?href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }

        // Fallback: bare href="…" for cases where the anchor regex doesn't match
        // (e.g. nested tags break the simple pattern). Only uses path matching.
        guard let hrefRegex = try? NSRegularExpression(
            pattern: #"href\s*=\s*["']([^"']+)["']"#,
            options: [.caseInsensitive]
        ) else { return [] }

        let lower = html.lowercased()
        let nsRange = NSRange(lower.startIndex..., in: lower)

        // Priority buckets: path matches first, then visible-text matches.
        var pathMatches: [URL] = []
        var textMatches: [URL] = []
        var seen = Set<String>()

        /// Try to resolve, deduplicate, and validate a candidate URL.
        func tryAdd(_ href: String, isPathMatch: Bool) {
            if href.hasPrefix("#") || href.hasPrefix("javascript:") || href.hasPrefix("mailto:") { return }
            guard let resolved = URL(string: href, relativeTo: baseURL)?.absoluteURL else { return }
            guard resolved.host == baseURL.host else { return }
            let path = resolved.path.lowercased()
            if path == "/" || path == baseURL.path.lowercased() { return }

            // Skip non-content paths
            if skipPaths.contains(where: { path.hasPrefix($0) }) { return }

            let urlString = resolved.absoluteString
            guard !seen.contains(urlString) else { return }
            seen.insert(urlString)

            if isPathMatch {
                pathMatches.append(resolved)
            } else {
                textMatches.append(resolved)
            }
        }

        // Pass A: full <a href="…">text</a> matching — captures visible text safely.
        let anchorMatches = anchorRegex.matches(in: lower, range: nsRange)
        for match in anchorMatches {
            guard let hrefRange = Range(match.range(at: 1), in: lower) else { continue }
            let href = String(lower[hrefRange])

            let pathHasMenu = menuTerms.contains { href.contains($0) }

            // Strip HTML tags from visible text to get clean anchor text
            let rawText: String
            if let textRange = Range(match.range(at: 2), in: lower) {
                rawText = String(lower[textRange])
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            } else {
                rawText = ""
            }
            let textHasMenu = menuTerms.contains { rawText.contains($0) }

            if pathHasMenu {
                tryAdd(href, isPathMatch: true)
            } else if textHasMenu {
                tryAdd(href, isPathMatch: false)
            }
        }

        // Pass B: fallback href-only scan — catches links that the anchor regex
        // missed (e.g. nested elements, malformed HTML). Only uses path matching
        // to avoid the old bug of matching "menu" in HTML attributes.
        let hrefMatches = hrefRegex.matches(in: lower, range: nsRange)
        for match in hrefMatches {
            guard let range = Range(match.range(at: 1), in: lower) else { continue }
            let href = String(lower[range])
            if menuTerms.contains(where: { href.contains($0) }) {
                tryAdd(href, isPathMatch: true)
            }
        }

        // Return path matches first (highest signal), then text matches.
        return pathMatches + textMatches
    }

    /// Returns the website URL for a map item via Brave Search cache.
    private func websiteURL(for mapItem: MKMapItem) async -> URL? {
        guard let name = mapItem.name, !name.isEmpty else { return nil }
        let city  = mapItem.placemark.locality ?? ""
        let state = mapItem.placemark.administrativeArea ?? ""
        let queryKey = [name, city, state].filter { !$0.isEmpty }.joined(separator: " ")

        if let cached = braveCache[queryKey] { return cached }

        if let url = await findWebsiteViaBraveSearch(query: queryKey) {
            braveCache[queryKey] = url
            return url
        }
        return nil
    }

    /// Returns true for social media / aggregator domains whose pages will never
    /// contain venue-specific menu keywords. When Apple Maps lists one of these as
    /// a venue's "website", we skip it and fall through to Brave Search discovery.
    private func isSocialMediaURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let blockedDomains = [
            "facebook.com", "www.facebook.com", "m.facebook.com",
            "instagram.com", "www.instagram.com",
            "twitter.com", "x.com",
            "yelp.com", "www.yelp.com",
            "tripadvisor.com", "www.tripadvisor.com",
            "tiktok.com", "www.tiktok.com",
            "linkedin.com", "www.linkedin.com",
        ]
        return blockedDomains.contains(host)
    }

    /// Upgrades http:// to https:// — iOS ATS blocks plain HTTP fetches.
    private func upgradeToHTTPS(_ url: URL) -> URL {
        guard url.scheme == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.scheme = "https"
        return components.url ?? url
    }

    /// Returns true if a Brave Search for `query` has at least one web result.
    private func braveSearchHasResults(query: String) async -> Bool {
        guard let results = await braveWebResults(query: query, count: 1) else { return false }
        return !results.isEmpty
    }

    /// Discovers a venue's real website URL via Brave Search, skipping social media.
    /// Requests 5 results so we can skip social media pages that may rank above
    /// the venue's own website (still a single API call).
    private func findWebsiteViaBraveSearch(query: String) async -> URL? {
        guard let results = await braveWebResults(query: query, count: 5) else { return nil }
        for result in results {
            guard let urlString = result["url"] as? String,
                  let url = URL(string: urlString) else { continue }
            let upgraded = upgradeToHTTPS(url)
            if !isSocialMediaURL(upgraded) { return upgraded }
        }
        return nil
    }

    /// Shared Brave Search HTTP call. Returns the raw result array or nil on failure.
    private func braveWebResults(query: String, count: Int) async -> [[String: Any]]? {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let requestURL = URL(string: "https://api.search.brave.com/res/v1/web/search?q=\(encodedQuery)&count=\(count)")
        else { return nil }

        var request = URLRequest(url: requestURL)
        request.setValue(APIKeys.braveSearch, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await apiSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let web = json["web"] as? [String: Any],
                  let results = web["results"] as? [[String: Any]]
            else { return nil }
            return results
        } catch {
            return nil
        }
    }
}
