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
- Called from `SearchResultStore.fetchSuggestions()` (Map boot + "Search This Area") and `ExplorePanel` (Spots tab category browse)
- Both delegate to `LocationSearchService.taggedMultiSearch()` — search config exists in one place

## Core Design Rule: One Search, Two Views

**The Map tab and Spots tab are two presentations of ONE search workflow. They MUST produce identical results when searching from the same center point.**

- Both tabs share a single `SearchResultStore` (`@EnvironmentObject`) — one canonical `[SuggestedSpot]` array
- Both tabs use `taggedMultiSearch` with the active picks' `mapSearchTerms` for category browsing
- The Spots tab search bar has TWO modes: empty = category browse (reads from store), text typed = venue-name search (local `venueSearchResults` state, independent from store)
- Pills (category filters) are user-controlled only — never reset programmatically on pan, zoom, or search
- Pre-screen (website scanning) writes results to the store via `applyPreScreenResults()` — both tabs see updates instantly
- Any code change that introduces a separate search pipeline for either tab violates this rule

**Before modifying any search logic, verify the change preserves parity between both tabs.**

## Architecture Notes

### SearchResultStore (single source of truth)
- Owns: `suggestions` (≤25 displayed), `fullPool` (all ~100+ from search), `isLoading`, `preScreenComplete`
- `fetchSuggestions()` delegates to `LocationSearchService.taggedMultiSearch()`
- `fetchGeneration` counter aborts stale fetches when a newer one starts
- `applyPreScreenResults()` promotes green matches from full pool into displayed set
- Unified filtering: `filteredSuggestions()`, `visiblePins()`, `splitByPreScreen()` — replaces 4 duplicate filter implementations
- `dismissedIDs` is session-scoped (in-memory `Set<String>`) — does NOT persist to Firestore
- 50m movement threshold in `MapTabView.shouldFetch()` suppresses camera-settle micro-fires

### Website Check (`WebsiteCheckService`)
- Three-pass: Pass 1 = homepage HTML scan (free), Pass 2 = `keyword site:domain` Brave, Pass 3 = `keyword venueName` Brave
- `checkWithBraveSearch()` is the **only** public method — called only on user tap
- Cloudflare captcha wall detection: skips caching so Brave passes can still run
- Session-scoped HTML cache and Brave URL discovery cache prevent duplicate fetches

### Explore Search (`ListTabView` / `ExplorePanel`)
- See `memory/MEMORY.md` for critical SwiftUI pitfalls that broke this repeatedly
- `searchText` must be `@Binding`, SpotService must be plain `let` (not `@EnvironmentObject`)
- Category browse reads from `SearchResultStore` (shared); venue-name search uses local state (independent)

## Before App Store Submission
- Replace placeholder URLs in `Constants.swift`: `privacyPolicyURL` and `supportURL`
- Both must be publicly accessible or Apple will reject the app
