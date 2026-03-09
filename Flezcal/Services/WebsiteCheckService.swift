import Foundation
@preconcurrency import MapKit
import CoreLocation

/// The result of checking a venue's website for category-relevant keywords.
enum WebsiteCheckResult: Equatable {
    /// Keywords were found — high confidence the venue carries this item.
    /// Associated value is the FoodCategory whose keywords matched.
    case confirmed(FoodCategory)
    /// A broad/related keyword matched but the specific keywords didn't.
    /// The user should verify. `keyword` is the matched term (e.g. "tortillas").
    case relatedFound(FoodCategory, keyword: String)
    /// The website was reachable but no keywords matched.
    case notFound
    /// No website URL available, the fetch failed, or the response was unreadable.
    case unavailable
}

/// A broad keyword match that needs user verification.
struct RelatedMatch: Equatable {
    let category: FoodCategory
    let keyword: String
}

/// Result of checking a venue's website against ALL of the user's active picks.
/// Used by the ghost pin sheet to show which picks were found on the website.
struct MultiCategoryCheckResult: Equatable {
    /// Categories (from the user's active picks) confirmed on the website.
    let confirmed: [FoodCategory]
    /// Categories where only broad/related keywords matched — needs user verification.
    let relatedFound: [RelatedMatch]
    /// Categories checked but not found.
    let notFound: [FoodCategory]
    /// The primary category (the one that produced the ghost pin).
    let primaryPick: FoodCategory
    /// Full 3-pass result for the primary pick specifically.
    let primaryResult: WebsiteCheckResult
    /// True when no website URL was available at all.
    let websiteUnavailable: Bool
}

/// Per-URL HTML scan result: confirmed category IDs and related-match info.
struct HTMLScanResult {
    var confirmed: Set<String>       // category IDs with websiteKeyword matches
    var related: [String: String]    // category ID → first matched relatedKeyword

    /// All category IDs with any kind of match (confirmed or related).
    var allMatchedIDs: Set<String> { confirmed.union(Set(related.keys)) }

    static let empty = HTMLScanResult(confirmed: [], related: [:])
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
    // Accepts TLS 1.0+ because many small-town restaurant sites run outdated
    // SSL configurations that fail with the default TLS 1.2 minimum.
    private let webSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 6
        config.timeoutIntervalForResource = 8
        // Limit concurrent connections to avoid overwhelming the device's
        // network stack when pre-screening many venues at once. Without this,
        // 10+ simultaneous connections to slow/unresponsive restaurant sites
        // cause connection timeouts to pile up, stalling the entire session.
        config.httpMaximumConnectionsPerHost = 2
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        ]
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        // Disable URL caching — we maintain our own in-memory htmlCache and
        // don't want stale disk-cached responses consuming storage.
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    // Plain session for Brave API calls — no custom User-Agent so the
    // API key header isn't interfered with.
    private let apiSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 6
        config.timeoutIntervalForResource = 8
        return URLSession(configuration: config)
    }()

    /// HTML cache: URL string → scan result with confirmed and related matches
    /// (empty result = page fetched with no matches). nil entry = page not yet fetched.
    private var htmlCache: [String: HTMLScanResult] = [:]

    /// Tracks which URLs were detected as JS-heavy (homepage was a JS shell).
    /// Used so cache hits in `checkWithBraveSearch` can still expand Pass 2.
    private var jsHeavyCache: Set<String> = []

    /// Brave Search cache: venue name+city+state query → discovered website URL.
    private var braveCache: [String: URL] = [:]

    /// Clears the HTML scan cache. Call when user picks change so pages are
    /// re-scanned for the new category keywords on next fetch.
    func clearHTMLCache() {
        htmlCache.removeAll()
        jsHeavyCache.removeAll()
    }

    /// Maximum number of subpages to crawl per venue (homepage doesn't count).
    /// 5 is enough for lunch/dinner/drinks/dessert/location-specific menus
    /// while staying under ~6 seconds total even on slow hosts.
    private let maxSubpageCrawls = 5

    /// Social media / aggregator domains whose pages never contain venue-specific
    /// menu keywords. When Apple Maps lists one of these as a venue's "website",
    /// we skip it and fall through to Brave Search discovery.
    private static let blockedDomains: Set<String> = [
        "facebook.com", "www.facebook.com", "m.facebook.com",
        "instagram.com", "www.instagram.com",
        "twitter.com", "x.com",
        "yelp.com", "www.yelp.com",
        "tripadvisor.com", "www.tripadvisor.com",
        "tiktok.com", "www.tiktok.com",
        "linkedin.com", "www.linkedin.com",
    ]

    // MARK: - Public API

    /// Returns a cached result instantly if the URL has been scanned before.
    /// Returns nil if the URL has never been fetched (caller should run a full check).
    /// Call this before checkWithBraveSearch to avoid unnecessary network calls.
    func cachedResult(for urlString: String, pick: FoodCategory) -> WebsiteCheckResult? {
        guard let cached = htmlCache[urlString] else { return nil }
        // Cache hit — check confirmed first, then related
        if cached.confirmed.contains(pick.id) {
            return .confirmed(pick)
        }
        if let keyword = cached.related[pick.id] {
            return .relatedFound(pick, keyword: keyword)
        }
        return .notFound
    }

    /// Instant cache-only pre-screen — returns results for suggestions whose
    /// URLs are already in htmlCache. No network calls. Use this to apply
    /// cached results immediately (e.g. from Explore tab) before running the
    /// full batchPreScreen for uncached venues.
    func cachedPreScreen(
        suggestions: [SuggestedSpot],
        picks: [FoodCategory]
    ) -> [String: Set<String>] {
        let pickIDs = Set(picks.map(\.id))
        var results: [String: Set<String>] = [:]
        for suggestion in suggestions {
            guard let rawURL = suggestion.mapItem.url,
                  !isSocialMediaURL(rawURL) else { continue }
            let key = upgradeToHTTPS(rawURL).absoluteString
            if let cached = htmlCache[key] {
                results[suggestion.id] = cached.confirmed.intersection(pickIDs)
            }
        }
        return results
    }

    /// Homepage-only scan for batch pre-screening ghost pins.
    /// Fetches homepages concurrently, scans for the user's active picks only,
    /// and returns matched category IDs per suggestion ID.
    /// NO Brave API calls. NO subpage crawling. Homepage only for speed.
    ///
    /// Only the user's active picks are scanned (~3 categories instead of 50+),
    /// reducing regex operations by ~94%. Cache is invalidated when picks change.
    func batchPreScreen(
        suggestions: [SuggestedSpot],
        picks: [FoodCategory]
    ) async -> [String: Set<String>] {
        let pickIDs = Set(picks.map(\.id))
        // Results map: id → matched pick IDs.
        // Venues WITH a URL that were scanned but had no matches get an empty Set().
        // Venues WITHOUT a URL are omitted entirely (not in the dict).
        // This lets applyPreScreenResults distinguish "scanned, nothing found"
        // from "no URL to scan" — the latter keeps preScreenMatches = nil (yellow pin).
        var results: [String: Set<String>] = [:]

        // Separate into cached (instant) and needs-fetch
        var toFetch: [(id: String, url: URL)] = []

        for suggestion in suggestions {
            guard let rawURL = suggestion.mapItem.url,
                  !isSocialMediaURL(rawURL) else {
                // No URL or social media URL — skip entirely (not added to results)
                continue
            }
            // Normalize to https:// so cache keys match the full check
            // (resolveURL applies upgradeToHTTPS before looking up the cache).
            let url = upgradeToHTTPS(rawURL)
            let key = url.absoluteString
            if let cached = htmlCache[key] {
                // Already scanned — filter to user's picks.
                // Only confirmed (websiteKeyword) matches count for pre-screen ranking.
                // Related (relatedKeyword) matches are too weak — e.g. "agave" on a
                // breakfast menu would falsely promote a non-mezcal venue.
                let relevant = cached.confirmed.intersection(pickIDs)
                // Always include in results (even if empty) to mark as scanned
                results[suggestion.id] = relevant
            } else {
                toFetch.append((id: suggestion.id, url: url))
            }
        }

        // Fetch uncached homepages concurrently (max 6 at a time).
        // Reduced from 10 — too many simultaneous connections to slow
        // restaurant servers cause network timeouts to pile up, stalling
        // the URLSession and making the app feel frozen.
        if !toFetch.isEmpty {
            let fetched = await fetchAndScanHomepages(toFetch, categories: picks)

            // Cache results and filter to picks.
            // Only confirmed matches drive pre-screen ranking (not related).
            // Include all fetched venues in results (even empty) to mark as scanned.
            for (id, url, scanResult) in fetched {
                htmlCache[url.absoluteString] = scanResult
                let relevant = scanResult.confirmed.intersection(pickIDs)
                results[id] = relevant
                #if DEBUG
                if !scanResult.confirmed.isEmpty || !scanResult.related.isEmpty {
                    print("[PreScreen] \(id): confirmed=\(scanResult.confirmed) related=\(scanResult.related) pickIDs=\(pickIDs) → relevant=\(relevant)")
                }
                #endif
            }

            // Also mark venues whose fetch failed (not in `fetched`) as scanned
            // if they had a URL — they were attempted but the server was unreachable.
            let fetchedIDs = Set(fetched.map(\.0))
            for item in toFetch where !fetchedIDs.contains(item.id) {
                if results[item.id] == nil {
                    results[item.id] = Set()
                }
            }
        }

        #if DEBUG
        let matchCount = results.values.filter { !$0.isEmpty }.count
        let noURLCount = suggestions.count - results.count
        print("[PreScreen] \(suggestions.count) venues: \(matchCount) matches, \(results.count - matchCount) scanned-no-match, \(noURLCount) no-URL. Fetched \(toFetch.count) homepages.")
        for (id, matches) in results where !matches.isEmpty {
            let name = suggestions.first { $0.id == id }?.name ?? id
            print("  ✅ \(name): \(matches)")
        }
        #endif
        return results
    }

    /// Pre-screen MKMapItems for Explore result re-ranking.
    /// Returns a set of MKMapItem indices (position in the input array) that
    /// had at least one keyword match (confirmed or related) for the user's picks.
    /// Homepage-only, no Brave API calls, no subpage crawling.
    /// Pre-screen venues for Explore result re-ranking.
    /// Accepts pre-extracted (index, url) pairs so that non-Sendable MKMapItem
    /// doesn't cross the actor boundary.
    func batchPreScreenMapItems(
        _ items: [(index: Int, url: URL)],
        picks: [FoodCategory]
    ) async -> Set<Int> {
        let pickIDs = Set(picks.map(\.id))
        var matchedIndices = Set<Int>()

        // Separate cached vs needs-fetch
        var toFetch: [(id: Int, url: URL)] = []

        for item in items {
            guard !isSocialMediaURL(item.url) else { continue }
            // Normalize to https:// so cache keys match the full check
            // (resolveURL applies upgradeToHTTPS before looking up the cache).
            let normalized = upgradeToHTTPS(item.url)
            let key = normalized.absoluteString
            if let cached = htmlCache[key] {
                if !cached.confirmed.intersection(pickIDs).isEmpty {
                    matchedIndices.insert(item.index)
                }
            } else {
                toFetch.append((id: item.index, url: normalized))
            }
        }

        // Fetch uncached homepages concurrently (max 6 at a time).
        // Keeps connection count manageable to avoid timeout pile-ups.
        if !toFetch.isEmpty {
            let fetched = await fetchAndScanHomepages(toFetch, categories: picks)

            for (index, url, scanResult) in fetched {
                htmlCache[url.absoluteString] = scanResult
                if !scanResult.confirmed.intersection(pickIDs).isEmpty {
                    matchedIndices.insert(index)
                }
                #if DEBUG
                if !scanResult.confirmed.isEmpty || !scanResult.related.isEmpty {
                    print("[PreScreen-Explore] index \(index): confirmed=\(scanResult.confirmed) related=\(scanResult.related) pickIDs=\(pickIDs)")
                }
                #endif
            }
        }

        #if DEBUG
        print("[PreScreen] Explore: scanned \(toFetch.count) homepages, \(matchedIndices.count) matches")
        #endif
        return matchedIndices
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
        allPicks: [FoodCategory] = [],
        knownURL: String? = nil
    ) async -> (WebsiteCheckResult, URL?) {
        let venueName = mapItem.name ?? ""
        #if DEBUG
        print("[WebCheck] \(venueName): checking \(pick.displayName)")
        #endif

        let url = await resolveURL(mapItem: mapItem, knownURL: knownURL)
        #if DEBUG
        print("[WebCheck]   url=\(url?.absoluteString ?? "nil")")
        #endif

        // Pass 1: homepage HTML scan — scans user's active picks, caches results.
        // Then checks if the requested pick was matched.
        var jsHeavy = false
        var pass1FoundOtherCategories = false
        var relatedKeyword: String?  // Track if a broad related keyword was found in Pass 1
        if let url {
            // Check cache first before fetching
            let key = url.absoluteString
            if let cached = htmlCache[key] {
                if cached.confirmed.contains(pick.id) { return (.confirmed(pick), url) }
                // Check for related match
                if let keyword = cached.related[pick.id] {
                    relatedKeyword = keyword
                }
                // Cache says page was fetched but pick not confirmed — fall through to Brave passes.
                // Restore JS-heavy flag from cache so Pass 2 behaves consistently.
                jsHeavy = jsHeavyCache.contains(key)
                // "Other categories" means OTHER confirmed categories (not related-only for this pick)
                let otherConfirmed = cached.confirmed.subtracting([pick.id])
                pass1FoundOtherCategories = !otherConfirmed.isEmpty
            } else {
                // Not cached — fetch and scan user's picks
                let categories = allPicks.isEmpty ? [pick] : allPicks
                let (scanned, isJSHeavy, hasPDFMenus) = await fetchAndScanAllCategories(url, categories: categories)
                jsHeavy = isJSHeavy
                // Treat PDF-menu sites as "HTML worked" — the site has menu content,
                // it's just in PDFs we can't scan. This prevents Pass 2 from running
                // expanded keyword searches that produce false positives.
                pass1FoundOtherCategories = hasPDFMenus
                if let fresh = htmlCache[key] {
                    if fresh.confirmed.contains(pick.id) {
                        return (.confirmed(pick), url)
                    }
                    if let keyword = fresh.related[pick.id] {
                        relatedKeyword = keyword
                    }
                    // Check if OTHER categories were confirmed (not just related for current pick)
                    let otherConfirmed = fresh.confirmed.subtracting([pick.id])
                    if !otherConfirmed.isEmpty { pass1FoundOtherCategories = true }
                }
                #if DEBUG
                print("[WebCheck]   Pass 1: \(scanned.confirmed.isEmpty && scanned.related.isEmpty ? "no matches" : "confirmed: \(scanned.confirmed), related: \(scanned.related)")\(jsHeavy ? " (JS-heavy → expanded Pass 2)" : "")")
                #endif
            }

            // Pass 2: site-scoped Brave Search for the specific pick.
            // Uses ONLY websiteKeywords (never relatedKeywords) — Brave Search
            // with broad terms like "tortillas" would match every Mexican restaurant.
            //
            // Normal sites: try first 2 keywords (e.g. "mezcal" then "agave").
            // JS-heavy sites: try ALL keywords since HTML scanning is unreliable
            // on React/Vue/Toast pages where the real menu content is rendered
            // client-side. Brave's index includes JS-rendered content.
            //
            // Skip Pass 2 entirely when:
            //   a) Chain/multi-location domains with 4+ path segments — `site:domain`
            //      searches thousands of unrelated pages (Dunkin' false positive).
            //   b) Pass 1 confirmed OTHER categories but NOT this pick — the HTML is
            //      clearly readable, so if the keyword isn't there, it's not on
            //      the menu. Brave may still index SEO metadata, review snippets,
            //      or cross-referenced content that mentions the keyword without
            //      the venue actually serving it (Tuxpan/Cielito false positive).
            //      Note: a related-only match for the CURRENT pick does NOT count
            //      as "HTML worked" — we still want Pass 2 to try specific keywords.
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
                        #if DEBUG
                        print("[WebCheck]   Pass 2 HIT: \(query)")
                        #endif
                        return (.confirmed(pick), url)
                    }
                }
            } else if isChainLocationPage {
                #if DEBUG
                print("[WebCheck]   Pass 2: SKIPPED (chain location page)")
                #endif
            } else if htmlWorkedButPickMissing {
                #if DEBUG
                print("[WebCheck]   Pass 2: SKIPPED (HTML readable, found other categories but not \(pick.displayName))")
                #endif
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
                    #if DEBUG
                    print("[WebCheck]   Pass 3 HIT: \(query)")
                    #endif
                    return (.confirmed(pick), url)
                }
            }
        }

        // If Pass 1 found a related keyword but Passes 2/3 didn't confirm,
        // return .relatedFound so the UI can show a verification prompt.
        if let keyword = relatedKeyword {
            #if DEBUG
            print("[WebCheck]   \(venueName): \(pick.displayName) → relatedFound(\(keyword))")
            #endif
            return (.relatedFound(pick, keyword: keyword), url)
        }

        let result: WebsiteCheckResult = url == nil ? .unavailable : .notFound
        #if DEBUG
        print("[WebCheck]   \(venueName): \(pick.displayName) → \(result)")
        #endif
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
        // This populates htmlCache with the user's active picks from Pass 1.
        // Also returns the resolved URL so we can look up the cache for
        // secondary picks without re-resolving (which could diverge).
        let (primaryResult, url) = await checkWithBraveSearchReturningURL(
            mapItem, for: primaryPick, allPicks: picks, knownURL: knownURL
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
        // Three buckets: confirmed, relatedFound, notFound.
        var confirmed: [FoodCategory] = []
        var relatedFound: [RelatedMatch] = []
        var notFound: [FoodCategory] = []

        for pick in allPicks {
            let result: WebsiteCheckResult
            if pick == primaryPick {
                result = primaryResult
            } else if let url, let cached = cachedResult(for: url.absoluteString, pick: pick) {
                // Secondary picks only get confirmed from cache — never relatedFound.
                // relatedFound is inherently noisy for secondary picks because:
                //   1. They didn't go through the full 3-pass (no Brave confirmation).
                //   2. Broad related keywords (e.g. "agave" for mezcal) match
                //      incidental HTML content (agave syrup on a breakfast menu).
                //   3. The user is investigating the PRIMARY pick — showing uncertain
                //      matches for secondary picks creates false confidence.
                // Only the primary pick's relatedFound result is meaningful because
                // it was the user's intent to investigate that specific category.
                switch cached {
                case .confirmed:
                    result = cached
                case .relatedFound:
                    result = .notFound  // demote to notFound for secondary picks
                default:
                    result = cached
                }
            } else {
                result = .notFound
            }

            switch result {
            case .confirmed:
                confirmed.append(pick)
            case .relatedFound(_, let keyword):
                relatedFound.append(RelatedMatch(category: pick, keyword: keyword))
            default:
                notFound.append(pick)
            }
        }

        #if DEBUG
        print("[WebCheck] allPicks: confirmed=\(confirmed.map(\.id)), related=\(relatedFound.map(\.category.id)), notFound=\(notFound.map(\.id))")
        #endif

        return MultiCategoryCheckResult(
            confirmed: confirmed,
            relatedFound: relatedFound,
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

    /// Fetches homepage HTML, scans for the user's active pick keywords, then follows
    /// menu-related subpage links — including **depth-2 links** found on
    /// subpages themselves (critical for multi-location sites like Lolita where
    /// homepage → /fort-point/ → /fort-point-menu/).
    ///
    /// All results are merged into a single cache entry keyed by the original URL.
    /// Returns (matched category IDs, looksJSHeavy). The JS flag tells the caller
    /// to try more Brave Search keywords in Pass 2, since HTML scanning is unreliable
    /// on JS-rendered sites (React, Vue, Toast, etc.).
    /// Returns (matchedCategories, isJSHeavy, hasPDFMenus).
    /// `hasPDFMenus` is true when the homepage links to PDF menu files
    /// (e.g. menu-lunch.pdf, menu-dessert.pdf). These can't be HTML-scanned,
    /// so the caller should treat the site as "readable but pick not found"
    /// rather than "empty / JS-heavy", preventing false-positive Brave searches.
    private func fetchAndScanAllCategories(_ url: URL, categories: [FoodCategory]) async -> (HTMLScanResult, Bool, Bool) {
        let key = url.absoluteString

        // Step 1: fetch and scan the homepage
        guard let (homeHTML, isValid) = await fetchPage(url), isValid else {
            htmlCache[key] = .empty
            return (.empty, false, false)
        }
        var matched = scanForCategories(in: homeHTML, categories: categories)

        // Detect PDF menu links — sites like Mustards Grill host menus as
        // downloadable PDFs (.pdf) that our HTML scanner can't read. When we
        // find these, we know the site HAS menu content even though we can't
        // scan it. This prevents the JS-heavy heuristic from triggering and
        // stops Pass 2 from running expanded keyword searches.
        let lower = homeHTML.lowercased()
        let menuPDFTerms = ["menu", "food", "dessert", "drink", "dinner", "lunch", "brunch"]
        let hasPDFMenus: Bool = {
            // Look for href="...something-menu...pdf" patterns
            guard let pdfRegex = try? NSRegularExpression(
                pattern: #"href\s*=\s*["'][^"']*\.pdf["']"#,
                options: [.caseInsensitive]
            ) else { return false }
            let nsRange = NSRange(lower.startIndex..., in: lower)
            let pdfMatches = pdfRegex.matches(in: lower, range: nsRange)
            for match in pdfMatches {
                guard let range = Range(match.range, in: lower) else { continue }
                let href = String(lower[range])
                if menuPDFTerms.contains(where: { href.contains($0) }) {
                    return true
                }
            }
            return false
        }()

        // Detect JS-heavy pages: high script-to-content ratio suggests the real
        // menu content is rendered client-side and invisible to our HTML scan.
        // Only flagged when the homepage itself has few matches — if we already
        // found categories, the HTML is clearly working fine.
        // Also suppressed when PDF menus are present — the site is readable,
        // its menu content is just locked in PDFs.
        let looksJSHeavy: Bool
        if matched.confirmed.isEmpty && matched.related.isEmpty && !hasPDFMenus {
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

        // Step 2: find menu-related links on the homepage (PDF links are now filtered out)
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
                mergeHTMLResult(cached, into: &matched)
                crawlCount += 1
                continue
            }

            guard let (subHTML, subValid) = await fetchPage(menuURL), subValid else {
                crawlCount += 1
                continue
            }
            let subMatched = scanForCategories(in: subHTML, categories: categories)
            htmlCache[menuKey] = subMatched
            mergeHTMLResult(subMatched, into: &matched)
            crawlCount += 1
            #if DEBUG
            let subTotal = subMatched.confirmed.count + subMatched.related.count
            print("[WebCheck]   subpage \(menuURL.path): \(subTotal == 0 ? "0" : "\(subMatched.confirmed.count) confirmed, \(subMatched.related.count) related") matches")
            #endif

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
        #if DEBUG
        let jsNote = looksJSHeavy ? " (JS-heavy)" : ""
        let pdfNote = hasPDFMenus ? " (PDF menus)" : ""
        print("[WebCheck]   scan done: \(crawlCount) subpages, confirmed: \(matched.confirmed), related: \(matched.related)\(jsNote)\(pdfNote)")
        #endif
        return (matched, looksJSHeavy, hasPDFMenus)
    }

    /// Fetches a single page. Returns (html, isValid) or nil on failure.
    /// isValid is false when the page is a captcha / bot wall.
    private func fetchPage(_ url: URL) async -> (String, Bool)? {
        // Try HTTPS first, fall back to HTTP if it fails.
        // Many small-town restaurant sites have broken SSL, outdated TLS,
        // or only serve HTTP. We try HTTPS first (upgrading http:// URLs),
        // then fall back to plain HTTP on failure.
        // Requires NSAllowsArbitraryLoads in Info.plist for HTTP fallback.
        var httpsURL = url
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           components.scheme == "http" {
            components.scheme = "https"
            if let upgraded = components.url {
                httpsURL = upgraded
            }
        }

        // Attempt 1: HTTPS
        if let result = await fetchPageDirect(httpsURL) {
            return result
        }

        // Attempt 2: plain HTTP fallback (for broken SSL or HTTP-only sites)
        if httpsURL.scheme == "https",
           var components = URLComponents(url: httpsURL, resolvingAgainstBaseURL: false) {
            components.scheme = "http"
            if let httpURL = components.url {
                #if DEBUG
                print("[fetchPage] HTTPS failed for \(httpsURL.host ?? "?"), trying HTTP fallback")
                #endif
                return await fetchPageDirect(httpURL)
            }
        }
        return nil
    }

    /// Raw fetch + HTML parse for a single URL (no retry logic).
    private func fetchPageDirect(_ url: URL) async -> (String, Bool)? {
        do {
            let (data, response) = try await webSession.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                #if DEBUG
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[fetchPage] \(url.scheme ?? "?")://\(url.host ?? "?")\(url.path) → HTTP \(code)")
                #endif
                return nil
            }
            let html = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""
            guard !html.isEmpty else { return nil }
            #if DEBUG
            print("[fetchPage] \(url.scheme ?? "?")://\(url.host ?? "?")\(url.path) → OK (\(html.count) chars)")
            #endif
            let lower = html.lowercased()

            let isCaptchaWall = lower.contains("captcha-delivery.com") ||
                                lower.contains("enable js and disable any ad blocker") ||
                                lower.contains("cf-browser-verification") ||
                                (html.count < 2000 && lower.contains("cloudflare"))
            return (html, !isCaptchaWall)
        } catch {
            #if DEBUG
            let code = (error as NSError).code
            print("[fetchPage] \(url.scheme ?? "?")://\(url.host ?? "?")\(url.path) → error \(code)")
            #endif
            return nil
        }
    }

    /// Merges a subpage's scan result into an accumulated result.
    /// Confirmed matches take precedence: if a category is confirmed on any page,
    /// it's removed from the related dict to avoid showing it as "uncertain".
    private func mergeHTMLResult(_ new: HTMLScanResult, into accumulated: inout HTMLScanResult) {
        accumulated.confirmed.formUnion(new.confirmed)
        for confirmedID in new.confirmed {
            accumulated.related.removeValue(forKey: confirmedID)
        }
        for (catID, keyword) in new.related where !accumulated.confirmed.contains(catID) {
            if accumulated.related[catID] == nil {
                accumulated.related[catID] = keyword
            }
        }
    }

    /// Fetches homepages concurrently (max 6 at a time) and scans each for the
    /// user's active picks only. Returns the ID, URL, and scan result for each successful fetch.
    /// Shared by batchPreScreen and batchPreScreenMapItems to avoid duplicating
    /// the throttled task-group loop.
    private func fetchAndScanHomepages<ID: Sendable>(
        _ items: [(id: ID, url: URL)],
        categories: [FoodCategory]
    ) async -> [(ID, URL, HTMLScanResult)] {
        return await withTaskGroup(
            of: (ID, URL, HTMLScanResult)?.self,
            returning: [(ID, URL, HTMLScanResult)].self
        ) { group in
            var pending = 0
            var index = 0
            var collected: [(ID, URL, HTMLScanResult)] = []

            while index < items.count {
                while pending < 6 && index < items.count {
                    let item = items[index]
                    index += 1
                    pending += 1
                    group.addTask { [self] in
                        guard let (html, isValid) = await self.fetchPage(item.url),
                              isValid else { return nil }
                        let scanResult = await self.scanForCategories(in: html, categories: categories)
                        return (item.id, item.url, scanResult)
                    }
                }
                if let result = await group.next() {
                    pending -= 1
                    if let r = result { collected.append(r) }
                }
            }
            for await result in group {
                if let r = result { collected.append(r) }
            }
            return collected
        }
    }

    /// Scans raw HTML for the provided categories' keywords and returns an `HTMLScanResult`
    /// with both confirmed (websiteKeywords) and related (relatedKeywords) matches.
    ///
    /// Uses word-boundary matching (`\b`) so that short keywords like "flan" don't
    /// false-positive on "flank steak", "flannel", CSS class names, etc.
    /// Only scans the user's active picks (not all 50+ built-in categories)
    /// for a ~94% reduction in regex operations per page.
    ///
    /// For each category:
    ///   1. First scan `websiteKeywords` — if any match → confirmed (skip relatedKeywords).
    ///   2. Only if no websiteKeyword matched AND relatedKeywords is non-empty →
    ///      scan relatedKeywords → add to related dict with the matched keyword.
    private func scanForCategories(in html: String, categories: [FoodCategory]) -> HTMLScanResult {
        let lower = html.lowercased()
        var result = HTMLScanResult.empty

        for category in categories {
            // Step 1: check specific websiteKeywords first
            var foundSpecific = false
            for keyword in category.websiteKeywords {
                if matchKeyword(keyword, in: lower) {
                    result.confirmed.insert(category.id)
                    foundSpecific = true
                    break
                }
            }

            // Step 2: only check relatedKeywords if no specific keyword matched
            if !foundSpecific && !category.relatedKeywords.isEmpty {
                for keyword in category.relatedKeywords {
                    if matchKeyword(keyword, in: lower) {
                        result.related[category.id] = keyword
                        break
                    }
                }
            }
        }
        return result
    }

    /// Word-boundary regex match for a single keyword in lowercased HTML.
    private func matchKeyword(_ keyword: String, in lowerHTML: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword.lowercased()))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            // Fall back to contains() if regex fails (shouldn't happen)
            return lowerHTML.contains(keyword.lowercased())
        }
        let range = NSRange(lowerHTML.startIndex..., in: lowerHTML)
        return regex.firstMatch(in: lowerHTML, range: range) != nil
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

            // Skip non-HTML files — PDFs, images, and documents can't be scanned
            let skipExtensions = [".pdf", ".jpg", ".jpeg", ".png", ".gif", ".svg", ".doc", ".docx", ".xls", ".xlsx"]
            if skipExtensions.contains(where: { path.hasSuffix($0) }) { return }

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

    private func isSocialMediaURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return Self.blockedDomains.contains(host)
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
        guard await RateLimiter.shared.canMakeBraveCall() else {
            #if DEBUG
            print("[WebsiteCheck] Session Brave API limit reached")
            #endif
            return []
        }
        await RateLimiter.shared.recordBraveCall()

        // swiftlint:disable:next brave_api_guard
        let braveBase = "https://api.search.brave.com/res/v1/web/search"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let requestURL = URL(string: "\(braveBase)?q=\(encodedQuery)&count=\(count)")
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
