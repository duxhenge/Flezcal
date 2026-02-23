# Flezcal Import Scripts

## seed_mezcal_spots.py

Imports curated mezcal/mezcalería locations from a CSV into Firestore.

### One-time setup

```bash
# Python 3.9+ required
pip install firebase-admin requests

# Download service account key from:
#   Firebase Console → Project Settings → Service Accounts → Generate new private key
# Save as scripts/serviceAccountKey.json  (already in .gitignore — do NOT commit)
```

### Prepare your CSV

Use `mezcal_locations_sample.csv` as a template.

| Column | Required | Notes |
|---|---|---|
| `name` | ✅ | Business name |
| `address` | — | Street address |
| `city` | — | City |
| `state` | — | State / province abbreviation |
| `country` | — | ISO-2: US, CA, MX (defaults to US) |
| `latitude` | — | Decimal degrees; geocoded from address if blank |
| `longitude` | — | Decimal degrees; geocoded from address if blank |
| `categories` | — | Comma-separated: `mezcal`, `flan` (defaults to `mezcal`) |
| `mezcalOfferings` | — | Comma-separated brand names |
| `websiteURL` | — | Full URL |

If `latitude`/`longitude` are empty the script geocodes via **OpenStreetMap Nominatim** (free, no key). If Nominatim can't find it and you pass `--brave-key`, a Brave Search call is made as a fallback.

### Dry run (safe — reads Firestore, writes nothing)

```bash
python3 seed_mezcal_spots.py \
  --csv mezcal_locations_sample.csv \
  --service-account serviceAccountKey.json
```

Output shows what *would* be written and any duplicates found.

### Commit (writes to Firestore)

```bash
python3 seed_mezcal_spots.py \
  --csv mezcal_locations.csv \
  --service-account serviceAccountKey.json \
  --commit
```

### With Brave Search fallback

```bash
python3 seed_mezcal_spots.py \
  --csv mezcal_locations.csv \
  --service-account serviceAccountKey.json \
  --brave-key YOUR_BRAVE_API_KEY \
  --commit
```

> **Cost note:** Brave Search is metered. The script only calls it when Nominatim fails and as a website-discovery fallback — not for every row.

### Deduplication logic

A candidate is skipped if Firestore already has a spot where:
- First 6 characters of the name match (case-insensitive), **AND**
- Coordinates are within ~100 m (0.001° lat or lon)

### Source field values written

| `source` value | Meaning |
|---|---|
| `"import"` | Written by this script |
| `nil` / absent | Added by a real Flezcal user |

The iOS app shows an amber "Curated listing — awaiting community check-in" banner for any spot with `source != nil && communityVerified == false`. Once a real user taps "I've been here", `communityVerified` flips to `true` and the banner changes to a subtle green capsule.

### Security

- `serviceAccountKey.json` is in `.gitignore` — never commit it.
- The Admin SDK bypasses Firestore client-side rules; it can write any `addedByUserID`.
- The import sets `addedByUserID = "IMPORT_SCRIPT"` — a sentinel that the app can detect.

### Mezcalistas workflow

1. Export / copy Mezcalistas listings into a CSV using the column format above.
2. Provide lat/lon where known (avoids Nominatim quota).
3. Dry-run first, verify the output, then `--commit`.
4. Validate in the live iOS app before launch.
