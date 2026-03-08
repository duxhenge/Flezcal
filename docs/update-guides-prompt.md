# Prompt: Update User Guide & In-App Tutorials for Recent UI Changes

## Context

The Flezcal iOS app has undergone significant UI changes to the Spots tab (ListTabView) and Map tab (MapTabView). The user guide (`USER_MANUAL.md`), in-app tutorials (`TutorialContent.swift`), and welcome content (`WelcomeContent.swift`) need to be updated to reflect the current state of the app. **No screenshots need to be created** — just text content updates.

This is a Swift/SwiftUI iOS project located at:
`/Users/peterwojciechowski/Library/Mobile Documents/com~apple~CloudDocs/Claude coding/Flezcal/`

---

## Summary of UI Changes to Document

### 1. Spots Tab Redesign (formerly "Community" + "Explore" segmented control)

**Before:** The Spots tab had two modes toggled by a segmented control — "Community" (showing verified spots) and "Explore" (showing Apple Maps search results with pre-screen highlighting).

**After:** The Spots tab is now a **single unified page** with three filter pill toggles at the top:

- **Verified** (green, solid dot) — Community-confirmed spots from the database
- **Likely** (green, ring/outline dot) — Search results where the app found a Flezcal keyword match on the venue's website (pre-screen confirmed). These were previously called "Possible" and before that were only visible in Explore mode.
- **Nearby** (yellow dot) — Search results that are the right category but haven't been website-checked yet. These were previously called "Unchecked" and before that were only visible in Explore mode.

The Verified and Likely results are **interleaved by distance** in a single unified list section. Nearby (yellow/unchecked) results appear below in a separate "Other Nearby" section.

These three filter toggles use the same `PinToggleButton` pill style as the Map tab — small capsules with a colored dot and count number that can be toggled on/off.

### 2. Map Tab Pin Toggle Label Changes

The Map tab's existing pin type toggles have been relabeled to match:
- "Possible" → **"Likely"**
- "Unchecked" → **"Nearby"**

The Verified / Likely / Nearby toggle pills now appear identically on both the Map tab and the Spots tab.

### 3. Flezcal Category Filters Moved to Top

On the Spots tab, the Flezcal category filter pills (e.g., "All", "Mezcal", "Flan", "Tortillas") now appear at the **very top** of the page, above the search bar. Previously they were lower on the page.

### 4. Automatic Search on Spots Tab

The Spots tab now automatically begins searching when opened (no need to switch to "Explore" mode). The search runs against the user's active Flezcal picks and location settings. Results appear as Likely and Nearby items alongside Verified spots.

### 5. "Search Wider Area?" on Spots Tab

A "Search Wider Area?" floating button now appears on the Spots tab (same as the Map tab). Tapping it scans additional venues beyond the initial 25 closest, potentially promoting new Likely matches into the list.

### 6. Search Activity Indicator

A spinning progress indicator now appears next to the filter pills while a search or pre-screen is in progress, making it clear that work is happening.

### 7. Manual Refresh

The toolbar refresh button (↻) on the Spots tab now triggers both a Firestore data refresh AND a new explore search. The button is disabled while a search is active.

### 8. Search Radius Moved

The Search Radius picker has been **moved from the My Flezcals page** to the **Customize Spot Search** sheet (accessible from the Spots tab via "Customize spot search" button). It appears at the top of both the overview and edit views within that sheet.

### 9. Tutorial Target for Search Radius Removed

The `searchRadius` tutorial target was removed from MyPicksTabView when the SearchRadiusPicker was moved, but it was **NOT re-added** to EditSpotSearchView. The tutorial step that spotlights "searchRadius" (Tutorial 1, Step 4) will currently show a loading/fallback state because its target doesn't exist on-screen. This needs to be addressed — either by re-adding the `.tutorialTarget("searchRadius")` in the new location OR by converting that tutorial step to a screenshot step OR by removing/rewording it.

---

## Files to Update

### 1. `USER_MANUAL.md` (root of project)

The user manual needs these sections rewritten or updated:

**Section: "The Map (Explore Tab)"** (lines 117-167)
- Update pin toggle descriptions to use "Likely" and "Nearby" labels instead of describing them only by color
- Mention the filter toggles by name (Verified / Likely / Nearby) and explain they control pin visibility with counts
- The "Search Wider Area" description is already present and accurate

**Section: "The Spots Tab (List View)"** (lines 264-288)
- This section describes the OLD two-mode "Community / Explore" segmented control design
- Rewrite entirely to describe the new unified page:
  - Three filter pill toggles (Verified / Likely / Nearby) with colored dots and counts
  - Flezcal category filters at the top
  - Automatic search on page open
  - Unified list with Verified + Likely interleaved by distance
  - "Other Nearby" section below for unchecked results
  - "Search Wider Area?" floating button
  - Spinning indicator during search
  - Refresh button triggers new search
  - "Customize spot search" button for adjusting search terms and radius
- Remove references to "Community mode" and "Explore mode" as separate concepts

**Section: "Adding a Spot > From Explore Search"** (lines 178-183)
- Update to reflect the new unified Spots tab (no more switching to "Explore" mode)
- A user now simply taps any Likely or Nearby result in the Spots tab list

**Section: "Your Picks > Viewing and Managing Picks"** (lines 57-66)
- Remove mention of search distance control being on the My Flezcals page (it's been moved)

**Section: "Adjusting Web Search Terms"** (lines 93-113)
- Add note that the Search Radius picker is now in the Customize Spot Search sheet, accessed from the Spots tab

**Section: "Tips and Tricks"** (lines 353-361)
- Update "Green ghost pins are your best bet" to use the term "Likely" alongside the green description
- Consider adding a tip about the unified Spots tab showing search results automatically

### 2. `Flezcal/Tutorial/TutorialContent.swift`

**Tutorial 1 — "Setting Up Your Flezcals" (setupFlezcals)**
- **Step 4 ("Search Distance")**: This step spotlights `"searchRadius"` which no longer exists on MyPicksTabView. Options:
  - **(Recommended)** Convert to a screenshot step explaining that search radius is in the Customize Spot Search sheet, OR
  - Re-add `.tutorialTarget("searchRadius")` to `EditSpotSearchView.swift` and change `requiredTab` — but this is complex because it requires opening a sheet during the tutorial
  - Remove the step entirely (loses the search radius education)
- **Bump `version` to 3** so existing users see the updated tutorial

**Tutorial 2 — "The Map" (mapExplore)**
- **Step 2 ("Pin Colors")**: Body text says "Yellow pins haven't been checked yet." Update to: "Green pins are **Likely** matches — the app found keywords on their website. Yellow pins are **Nearby** — they haven't been checked yet but might have what you're looking for."
- **Step 4 ("Pin Type Toggles")**: Body text says "Control which pin types are visible." Update to mention the specific toggle names: "Three toggles — Verified, Likely, and Nearby — control which pins are visible. Each shows a count so you can see how many spots are nearby."
- **Bump `version` to 3** so existing users see the updated tutorial

**Tutorial 3 — "Adding a Spot" (addSpot)**
- No changes needed — the adding flow itself hasn't changed, only how you discover spots. The screenshots still show the same sheets.

### 3. `Flezcal/Models/WelcomeContent.swift`

**Fallback content updates:**
- `pages[1]` ("The Map Works for You"): Description mentions "Green pins are community-verified spots. Green ghost pins are menu-scanned matches. Yellow pins haven't been checked yet." Update to use Likely/Nearby terminology and mention filter toggles.
- `pages[2]` ("Browse All Spots"): Description says "The Spots tab is your community directory, every spot added by the community, searchable and sortable. Filter by category, check ratings, and find verified places at a glance." Update to describe the unified list with Verified + Likely + Nearby filter toggles.
- `changeNote`: Update to mention the unified Spots tab and Likely/Nearby labels
- `changeDate`: Update to current date if needed
- Consider bumping `version` to force re-display of the welcome screen

**Note:** The welcome content may also be managed in Firestore. These fallback changes ensure offline/first-launch users see accurate content. The Firestore version should also be updated separately by the user.

### 4. (Optional) `Flezcal/Views/EditSpotSearchView.swift`

If the tutorial step for Search Radius is kept as a spotlight step (not converted to screenshot), add `.tutorialTarget("searchRadius")` to the `SearchRadiusPicker` in this file. This is only needed if the tutorial approach requires it.

---

## Important Constraints

- **NEVER call paid APIs** (Brave Search) during this work. This is a text-only update task.
- **Do NOT modify any view logic or search behavior** — only update text content in the files listed above.
- **Preserve the tutorial version system**: Bumping `version` on a tutorial resets its "completed" state so users see updated content. Only bump if content actually changes.
- **The ExplorePanel search stability rules still apply** — don't touch ListTabView.swift view code. Only TutorialContent.swift, USER_MANUAL.md, and WelcomeContent.swift need edits.
- **Variable names like `showPossible`, `showUnchecked`, `uncheckedCount`, `possibleCount`** remain unchanged in the code — only the user-facing **labels** changed to "Likely" and "Nearby". Don't rename variables.
- **The `searchRadius` tutorial target is broken** — it was removed from MyPicksTabView but not re-added elsewhere. Address this in the tutorial update.

---

## Verification Checklist

After making changes, verify:
1. No references to "Community mode" or "Explore mode" as separate Spots tab modes remain in USER_MANUAL.md
2. No references to "Possible" (old label) remain in user-facing text — should all say "Likely"
3. No references to "Unchecked" (old label) remain in user-facing text — should all say "Nearby"
4. Tutorial version numbers bumped for any tutorials with changed content
5. The `searchRadius` tutorial step is handled (screenshot, removed, or target re-added)
6. The project builds successfully: `xcodebuild -project Flezcal.xcodeproj -scheme Flezcal -destination 'generic/platform=iOS' build`
7. USER_MANUAL.md accurately describes the current Spots tab layout: Flezcal filters → search bar → location bar → customize button → result type filters (Verified/Likely/Nearby pills) → unified list → "Other Nearby" section → "Search Wider Area?" button
