# Flezcal — Claude Instructions

## Paid API Services — NEVER call without explicit permission

**Rule: Never make live calls (curl, URLSession tests, etc.) against paid APIs during debugging or testing without asking first.**

### Brave Search API
- Key: `Secrets.xcconfig` → `Config.xcconfig` (`#include`) → build settings → `Info.plist` → `APIKeys.braveSearch`
- **`Config.xcconfig` MUST contain `#include "Secrets.xcconfig"`.** Without it, Brave API fails with HTTP 422.
- Used only in `WebsiteCheckService.braveWebResults()` — called only on explicit user tap
- Do NOT run curl tests against this key without permission

### Apple Maps (MKLocalSearch)
- Rate limit: ~50 requests/60s. 250ms delay + 1s retry on throttle in `LocationSearchService`
- Called from `SearchResultStore.fetchSuggestions()` via `LocationSearchService.taggedMultiSearch()`

---

## SEARCH STABILITY CONTRACT — PROTECTED

**No search may run without explicit user action. Period.**

### Allowed search triggers (exhaustive list):
1. **Boot** — ONE auto-fetch at user location (`bootFetchesRemaining = 1`, zeroed immediately)
2. **"Search This Area" button** — user taps explicitly on Map tab
3. **"Scan More Spots?" button** — user taps explicitly (Wave 2)
4. **Custom location first set** — user typed a location or used Concierge (ExplorePanel, first time only)

### Forbidden triggers:
- **Tab switches** — `.onEnd` fires on every tab switch; after boot it ONLY shows button
- **Camera settles** — pan/zoom only shows "Search This Area" button
- **Pill toggles** — client-side filter only, never re-fetch
- **SwiftUI `.task(id:)` re-fires** — ExplorePanel guards with `lastFetchedTaskID` + `!suggestions.isEmpty`
- **`.onChange` handlers** — picks changes show button, never auto-fetch

### Three layers of protection:
1. **Call-site guards** — `bootFetchesRemaining == 0`, `lastFetchedTaskID`, `!suggestions.isEmpty`
2. **Store redundant-fetch guard** — `lastFetchPickIDs` + `lastFetchCenter` (< 500m) + `hasResultsOrInFlight`
3. **`cancelInFlight()` preserves guard state** — does NOT clear `lastFetchPickIDs` or `lastFetchCenter`

### Before adding ANY new `fetchAndPreScreen` call site:
- Prove it only fires from direct user input
- Verify it cannot re-fire on tab switch or view re-appearance
- Warn the user before making the change

---

## One Search, Two Views

**Map tab and Spots tab are two presentations of ONE search. Same center = same results. Always.**

- Both tabs share one `SearchResultStore` via `@EnvironmentObject`
- **Only the Map tab triggers searches** (boot fetch, "Search This Area" button). The Spots tab is a pure renderer of store data.
- Spots tab search bar: empty = category browse (reads store), text typed = venue-name search (local state)
- Pills are user-controlled only — never reset on pan/zoom/search
- Pre-screen writes to store via `applyPreScreenResults()` — both tabs see updates instantly
- **Violating this rule is expensive.** Always verify tab parity before modifying search logic.

---

## Two-Stage Search

**Wave 1 = exactly 25 total pins (green + yellow). Wave 2 adds ONLY new green pins.**

- `fetchSuggestions` builds pool of ~100+ from `taggedMultiSearch`, takes closest 25, sets `originalSuggestionIDs`
- Cached pre-screen + Wave 1: `applyPreScreenResults(promotePoolGreens: false)` — updates original 25 only
- Wave 2 (user taps "Scan More Spots?"): `applyPreScreenResults(promotePoolGreens: true)` — adds greens from pool
- `originalSuggestionIDs` set ONCE in `fetchSuggestions`, never mutated by `applyPreScreenResults`
- Does NOT expand geographic radius — all venues come from the original 0.5° MKLocalSearch region

---

## Map Behavior Model ("Store Owns Tasks")

- **Boot:** `bootFetchesRemaining = 1` → first valid `.onEnd` fires fetch → set to 0 immediately
- **Pan/zoom:** Shows "Search This Area" button. NEVER cancels store tasks.
- **"Search This Area" button:** Calls `cancelInFlight()` then `fetchAndPreScreen()`. Only explicit user action.
- **Picks changed:** Shows "Search This Area" button — no auto-fetch.
- **Pill toggles:** Client-side filter only — no re-fetch. `visibleGhostPins` handles filtering.
- **Zoom via `pendingZoomToFit`** — store sets, MapTabView consumes via `.onChange(of: preScreenComplete)` + `.onChange(of: pendingZoomToFit)`

---

## SearchResultStore — Key Rules

Single source of truth for search results AND search task lifecycle.

- **Owns:** `suggestions` (≤25 displayed), `fullPool` (all ~100+), `isLoading`, `preScreenComplete`
- **Owns tasks:** `fetchTask`, `preScreenTask` are private — views CANNOT cancel them
- **`cancelInFlight()`** — cancels tasks but does NOT clear `lastFetchPickIDs` or `lastFetchCenter`
- **Redundant-fetch guard:** `lastFetchPickIDs` + `lastFetchCenter` (< 500m) + `hasResultsOrInFlight`. Only reset when new fetch starts.
- **Cached pre-screen uses `markComplete: false`** — preview pass must NOT set `preScreenComplete = true`
- **Minimum 0.5° search span** — zoomed-in maps get different results without it
- **`originalSuggestionIDs`** — tracks original closest-25. Never mutated by `applyPreScreenResults`
- **Rebuild array** in `applyPreScreenResults` — `.filter {}` from pool, NOT in-place mutation
- **`dismissedIDs`** — session-scoped `Set<String>`, not persisted

---

## WebsiteCheckService — 5 Critical Components (never remove)

1. **Browser User-Agent on URLSession** — Without it, Joomla/Wix/Squarespace/BentoBox return 403
2. **Social media URL filtering** (`isSocialMediaURL`) — Skip Facebook/Instagram/Yelp URLs from Apple Maps
3. **Menu subpage crawling** — Up to 5 subpages, depth-2, visible-text only, priority-sorted
4. **Word-boundary matching** (`\b` regex) — Never use `contains()`. "flan" would match "flank steak"
5. **Pass 3 restricted to URL-less venues** — Review sites produce false positives when URLs exist

### checkAllPicks Rules
1. Primary pick must always be in iteration set (`allPicks = picks + primaryPick`)
2. `ConfirmSpotView` accepts `categories: [SpotCategory]` (not single)
3. Pass 2: up to 2 keywords per category; JS-heavy tries all
4. Pass 2 skip rules: chain domains (4+ path segments), HTML readable but pick missing, JS-heavy cache

### fetchPage TLS/HTTP Fallback
HTTPS first, HTTP fallback. Required: `.TLSv12`, `NSAllowsArbitraryLoads = true`, `fetchPageDirect`

### Pre-Screen URL Normalization
All pre-screen methods MUST `upgradeToHTTPS()` before cache key use

---

## Category Architecture (Unified)

**FoodCategory is the single source of truth** for all category metadata.
- Struct with 50 active + 9 legacy static instances
- All computed properties: displayName, emoji, color, icon, mapSearchTerms, websiteKeywords, etc.
- Firestore overrides (`SearchTermOverrideService`) take precedence for display/search fields

**SpotCategory is a thin enum** — identity + Codable only.
- 59 built-in cases + `.custom(String)` for trending/user-created
- ALL display properties delegate to `FoodCategory.by(id: rawValue)` — zero duplication

---

## Explore Search Stability

**Never do these — they broke search repeatedly:**
- Pass `searchText` as `let` (must be `@Binding` — otherwise `@StateObject` destroyed on every keystroke)
- Add `@EnvironmentObject SpotService` to `ExplorePanel` (re-renders cancel `.task`)
- Move `.task(id:)` to parent view
- Declare unused `@EnvironmentObject` on sheets presented by `ExplorePanel`

---

## LocationSearchService — Required Settings (never change)

1. `resultTypes = .pointOfInterest` only (never `.address`)
2. `pointOfInterestFilter` for food/drink (retail queries bypass via `unfiltered` set)
3. `0.5° region span` (never 5.0). Retail queries use tighter 0.15°.
4. Hard distance cutoff filters venues beyond `radius * 111_000m`
5. 250ms delay between sequential queries + single retry with 1s backoff on throttle

---

## SuggestedSpot Equatable

`==` compares both `id` AND `preScreenMatches`. Otherwise SwiftUI won't re-render pins.

## Shared WebsiteCheckService

ONE instance in `ContentView`, passed as `let` to both tabs. Shares `htmlCache`.

## filteredSuggestions — Name-Only Matching

Never add coordinate proximity filtering. It suppresses unrelated nearby restaurants.

## UserPicksService — Term Refresh

`loadPicks()` refreshes from `allKnownCategories` unless user customized. `customizedTermsIDs` tracks.
**Alcohol/retail rule:** All spirit/wine/beer categories need "liquor store" AND "wine spirits" in `mapSearchTerms`.

## Swift 6 Strict Concurrency

`SWIFT_STRICT_CONCURRENCY = complete`, `SWIFT_VERSION` 5.0 (warnings not errors).

## Firestore Schema Safety

**Before every TestFlight build that changes Firestore structure, run a schema audit.**
- Additions: low risk. Renames/removals: high risk. Type changes: medium.

## Before App Store Submission
- Replace placeholder URLs in `Constants.swift`: `privacyPolicyURL` and `supportURL`
