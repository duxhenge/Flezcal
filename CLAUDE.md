# Flezcal — Claude Instructions

## Paid API Services — NEVER call without explicit permission

**Rule: Never make live calls (curl, URLSession tests, etc.) against paid APIs during debugging or testing without asking first.**
Always inspect code or check documentation instead. If a live test is truly necessary, state the cost impact and wait for explicit approval.

### Brave Search API
- Key stored in `Secrets.xcconfig` (gitignored) → injected via `Info.plist` → read in `APIKeys.braveSearch`
- Used **only** in `WebsiteCheckService.braveWebResults()`
- Called **only** on explicit user tap — never in batch/background loops
- Max ~5 calls per user tap (1 URL discovery + 1 Pass 2 per category + 1 Pass 3 per category)
- Monthly cap: set in Brave dashboard — do NOT run curl tests against this key without permission

### Apple Maps (MKLocalSearch)
- Rate limit: ~50 requests per 60 seconds
- Called from `SuggestionService.fetchSuggestions()` on camera move (50m threshold guard)
- Tier 1 (POI category passes) fails with `MKErrorGEOError=-8` in some US regions — Tier 2 text queries are the reliable fallback

## Core Design Rule: One Search, Two Views

**The Map tab and Spots tab are two presentations of ONE search workflow. They MUST produce identical results when searching from the same center point.**

- Both tabs use `taggedMultiSearch` with the active picks' `mapSearchTerms` for category browsing.
- The Spots tab search bar has TWO modes: empty = category browse (same as Map tab), text typed = venue-name search (add-spot workflow). The venue-name search is intentionally a separate MKLocalSearch because the user is looking for a specific place to add.
- Pills (category filters) are user-controlled only — never reset programmatically on pan, zoom, or search.
- When switching between tabs, results transfer so the user sees the same data.
- Any code change that introduces a separate search pipeline for either tab violates this rule.
- Pre-screen (website scanning) runs identically on both tabs' result sets.

**Before modifying any search logic, verify the change preserves parity between both tabs.**

## Architecture Notes

### Ghost Pin Search (`SuggestionService`)
- Two-tier: Tier 1 = `MKPointOfInterestCategory` passes, Tier 2 = natural language text queries
- `fetchGeneration` counter aborts stale fetches when a newer one starts
- `anyThrottled` flag prevents a partial throttled result from overwriting a good prior set
- 50m movement threshold in `MapTabView.shouldFetch()` suppresses camera-settle micro-fires

### Website Check (`WebsiteCheckService`)
- Three-pass: Pass 1 = homepage HTML scan (free), Pass 2 = `keyword site:domain` Brave, Pass 3 = `keyword venueName` Brave
- `checkWithBraveSearch()` is the **only** public method — called only on user tap
- Cloudflare captcha wall detection: skips caching so Brave passes can still run
- Session-scoped HTML cache and Brave URL discovery cache prevent duplicate fetches

### Explore Search (`ListTabView` / `ExplorePanel`)
- See `memory/MEMORY.md` for critical SwiftUI pitfalls that broke this repeatedly
- `searchText` must be `@Binding`, SpotService must be plain `let` (not `@EnvironmentObject`)

## Before App Store Submission
- Replace placeholder URLs in `Constants.swift`: `privacyPolicyURL` and `supportURL`
- Both must be publicly accessible or Apple will reject the app
