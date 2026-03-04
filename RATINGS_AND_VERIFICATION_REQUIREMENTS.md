# Flezcal Ratings & Verification — Requirements Specification

## Core Principles

1. **Verified** means a user has been to the spot and confirms the Flezcal is offered there
2. **Rating** is a quality score (1-5) that is optional and separate from verification
3. **Website check results are only "potential"** — never verified until a user confirms
4. **No written reviews, no photo uploads** — Flezcal is concise, not Yelp
5. **The spot must exist in Apple Maps** — users are informed during search if a spot can't be found

---

## Verification System

### What Verification Means
- A thumbs up = "I have been to this spot and they serve this Flezcal"
- A thumbs down = "I have been to this spot and they do NOT serve this Flezcal"
- Verification is per-category (mezcal can be verified while flan is not)

### Verification Lifecycle
1. **Initial verification**: A single user can verify a category by giving thumbs up
2. **Ongoing voting**: Other users can also thumbs up or thumbs down
3. **Threshold**: Once 10+ votes exist in the rolling 3-month window, the 70% positive threshold determines status
   - 70%+ positive (e.g., 7 of 10) → stays **Verified**
   - Below 70% → becomes **Unverified**
4. **Vote expiration**: Votes expire after 3 months, EXCEPT the original verifier's vote which persists longer (until user base is large enough)
5. **A rating also counts as a verification vote (thumbs up)** — one vote either way, not double-counted

### Changing Verification
- Users can change their thumbs up to thumbs down anytime (and vice versa)
- Changing to thumbs down removes that user's rating for that category
- Users can change their vote anytime, no time limit

---

## Rating System

### Rating Scale (1-5)
| Score | Label       | Description                    |
|-------|-------------|--------------------------------|
| 1     | You Decide  | It's here, your call           |
| 2     | Pop In      | Glad it's on the menu          |
| 3     | Book It     | Satisfies the craving          |
| 4     | Road Trip   | Worth going out of your way    |
| 5     | Pilgrimage  | Worth booking a flight         |

### Rating Rules
- Rating is **optional** — users can verify (thumbs up) without rating
- Rating is **per-category** — each Flezcal at a spot gets its own rating
- Rating **implies thumbs up** — you can't rate something you say isn't served
- Ratings can be **added, changed, or removed** anytime
- Removing a rating does NOT affect the user's verification vote
- Only **aggregate ratings** are shown to other users (e.g., "4.2 from 7 ratings"), never individual ratings
- **Number of verifying users** is shown (e.g., "12 users confirmed"), not usernames

### Rating UI
- One set of 5 flan emojis for selecting the score
- A table/legend below defining the meaning of each level (1-5)
- The rating tool appears immediately after the user gives a thumbs up or adds a Flezcal to the spot
- Rating is prompted but not required

---

## Spot Lifecycle

### Discovery (Two Paths)
1. **Ghost pin (website check)** — app scans restaurant website, finds potential Flezcal keywords, shows ghost pin on map. This is "potential" only, NOT verified.
2. **Explore search** — user already knows a spot serves a Flezcal and searches for it manually. This is an important use case that should be reinforced in the UI.

### Saving/Confirming a Spot
- User taps to confirm the spot → spot is saved to the database
- The act of confirming IS their verification — they are saying "I've been here, they serve this"
- The user only verifies the categories they can personally confirm from their visit
- Categories they haven't tried remain unverified (or "website mentions" if found by web scan)
- The spot must exist in Apple Maps; inform the user during search if it can't be found

### Adding Categories
- A user who didn't discover the spot can verify additional categories later
- Example: User A discovers Dolores and verifies mezcal. User B visits later and verifies flan.

---

## Spot Detail View — Consolidated Layout

### Top Section: Flezcal Rows
Each verified or potential Flezcal gets a compact row:

```
[emoji] [Name]    [thumbs up] [thumbs down]    [flan rating] [score]
```

Example:
```
🫓 Tortillas   👍 👎   🍮🍮🍮🍮 4.2
🍹 Mezcal      👍 👎   🍮🍮🍮   3.1
🍮 Flan        👍 👎   (no ratings yet)
```

- All information about a Flezcal is on one row: identity, verification, rating
- Rows wrap to two lines if there are many categories
- Thumbs up/down buttons are always visible for logged-in users
- Tapping thumbs up prompts (but doesn't require) a rating
- Tapping thumbs down removes any existing rating for that category

### Removed from Detail View
- ~~"Verified: [business name]" green label~~ — removed; Apple Maps match is implicit
- ~~Separate community verification section~~ — merged into Flezcal rows
- ~~Written reviews / review cards~~ — removed entirely
- ~~Photo uploads~~ — not in Flezcal

---

## Spot List Row

### Verified Spot
```
Dolores
Providence, RI
🫓 Tortillas  🍹 Mezcal  🍮 Flan
```
- Shows emoji + spelled-out name for each verified category
- No aggregate rating in the list row (save for detail view)
- No checkmark needed — presence in the list implies verification

### Potential (Unverified) Spot
```
Dolores
Providence, RI
Website mentions: 🍹 Mezcal  🍮 Flan  🫓 Tortillas
```
- "Website mentions" signals that no user has confirmed yet
- Tapping in lets the user review and potentially verify

---

## Closure Reports
- Users can report a spot as permanently closed
- After sufficient reports, the spot is visually dimmed/grayed out with a "Permanently Closed" note
- Eventually hidden from search results after a threshold of closure reports
- Kept lightweight — just a flag, no complex voting

---

## Profile — User History
- Users can view their own verification and rating history from their profile
- History shows spots they've verified and ratings they've given
- Tapping a spot links back to the spot detail where they can make changes
- Users are NOT automatically sent to the rating view — only if they specifically request to edit

---

## Admin Capabilities
- Admin database changes are handled through Claude conversations, not in-app admin UI
- Admin can remove categories from spots, delete user votes/ratings, or make any database modifications as needed
- Existing admin review delete functionality in ReviewCardView will be updated/simplified to match the new system

---

## What Changes from Current Implementation

### Removed
- WriteReviewView (text comments) → replaced by inline thumbs + rating
- Individual review cards (ReviewCardView) → replaced by aggregate display
- Separate VerificationSectionView → merged into Flezcal rows
- "Verified: [business name]" label → removed
- "Unverified/Confirmed/Disputed/New" status badges → replaced by category display
- Photo upload capability → not in Flezcal

### Modified
- SpotDetailView top section → consolidated Flezcal rows with thumbs + ratings
- List row status badge → verified category emojis and names
- Rating UI → simplified to one row of 5 emojis + meaning table
- Verification model → rating counts as verification vote
- Vote expiration → 3-month rolling window (except original verifier)

### Kept
- Rating scale 1-5 with travel-distance theme labels
- Per-category rating system
- Apple Maps integration for spot discovery
- Website check for potential discovery (ghost pins)
- Explore search for manual spot addition
- Closure reporting (simplified)
- Admin UID-based access
