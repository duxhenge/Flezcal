#!/usr/bin/env python3
"""
seed_mezcal_spots.py — Flezcal mezcal location importer
========================================================

Pipeline
--------
1. Load candidate locations from a CSV file (see INPUT FORMAT below).
2. Validate / enrich each entry via OpenStreetMap Nominatim (free, no key).
3. Optionally verify via Brave Search (metered — only called when OSM returns
   no result and --brave flag is passed).
4. Deduplicate against spots already in Firestore.
5. Dry-run by default; write to Firestore with --commit flag.

The script uses the Firebase Admin SDK, which bypasses client-side Firestore
security rules, so it can write documents with any addedByUserID value.

INPUT FORMAT (CSV)
------------------
name,address,city,state,country,latitude,longitude,categories,mezcalOfferings,websiteURL
Barra,1 Greenough Ave,Jamaica Plain,MA,US,,,.mezcal,,
El Destilado,San Jeronimo 503,Oaxaca,,MX,17.0603,-96.7203,mezcal,,https://eldestilado.com

Columns:
  name            Required. Business name.
  address         Street address (optional if lat/lon provided).
  city            City (optional if lat/lon provided).
  state           State or province abbreviation (optional).
  country         ISO-2 country code: US, CA, MX. Defaults to US.
  latitude        Decimal degrees (optional — geocoded from address if blank).
  longitude       Decimal degrees (optional — geocoded from address if blank).
  categories      Comma-separated: mezcal, flan (defaults to mezcal).
  mezcalOfferings Comma-separated list of mezcal brands (optional).
  websiteURL      URL string (optional).

USAGE
-----
  # Install deps once:
  pip install firebase-admin requests

  # Dry run (prints what would be written, touches nothing):
  python3 seed_mezcal_spots.py \
      --csv mezcal_locations.csv \
      --service-account serviceAccountKey.json

  # Commit for real:
  python3 seed_mezcal_spots.py \
      --csv mezcal_locations.csv \
      --service-account serviceAccountKey.json \
      --commit

  # Also use Brave Search for entries that OSM can't geocode:
  python3 seed_mezcal_spots.py \
      --csv mezcal_locations.csv \
      --service-account serviceAccountKey.json \
      --brave-key YOUR_BRAVE_API_KEY \
      --commit

SERVICE ACCOUNT
---------------
Download from Firebase Console → Project Settings → Service Accounts →
Generate new private key.  Do NOT commit this file to git.

DEDUPLICATION
-------------
A candidate is considered a duplicate of an existing Firestore spot if:
  • The names match (case-insensitive, first 6 chars)  AND
  • The coordinates are within ~500 m (0.005° in lat or lon)
Duplicates are skipped and logged.
"""

import argparse
import csv
import json
import math
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Optional heavy imports — checked at runtime
# ---------------------------------------------------------------------------

try:
    import firebase_admin
    from firebase_admin import credentials, firestore as admin_firestore
except ImportError:
    firebase_admin = None  # type: ignore

try:
    import requests
except ImportError:
    requests = None  # type: ignore

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

FIRESTORE_COLLECTION = "spots"
IMPORT_SYSTEM_USER_ID = "IMPORT_SCRIPT"
PROXIMITY_THRESHOLD_DEG = 0.005   # ~550 m — catches Apple Maps vs OSM geocoding variance
NOMINATIM_DELAY_SEC = 1.1         # Nominatim rate-limit: 1 request/second
BRAVE_BASE_URL = "https://api.search.brave.com/res/v1/web/search"
BRAVE_DELAY_SEC = 0.5

VALID_CATEGORIES = {"mezcal", "flan"}
SUPPORTED_COUNTRIES = {"US", "CA", "MX"}


# ---------------------------------------------------------------------------
# Geocoding helpers
# ---------------------------------------------------------------------------

def geocode_nominatim(name: str, address: str, city: str, state: str, country: str) -> Optional[dict]:
    """
    Try to resolve lat/lon from OSM Nominatim (free, no API key required).
    Returns {"latitude": float, "longitude": float, "mapItemName": str} or None.
    """
    if requests is None:
        print("  [WARN] 'requests' not installed — skipping geocoding.")
        return None

    query_parts = [p for p in [name, address, city, state, country] if p]
    query = ", ".join(query_parts)

    params = {
        "q": query,
        "format": "json",
        "limit": 1,
        "countrycodes": country.lower() if country else "",
        "addressdetails": 1,
    }
    headers = {"User-Agent": "Flezcal-Importer/1.0 (import script; contact: admin@flezcal.app)"}

    try:
        resp = requests.get(
            "https://nominatim.openstreetmap.org/search",
            params=params,
            headers=headers,
            timeout=10,
        )
        resp.raise_for_status()
        results = resp.json()
        if results:
            r = results[0]
            return {
                "latitude": float(r["lat"]),
                "longitude": float(r["lon"]),
                "mapItemName": r.get("display_name", name)[:120],
            }
    except Exception as e:
        print(f"  [WARN] Nominatim error for '{name}': {e}")

    time.sleep(NOMINATIM_DELAY_SEC)
    return None


def verify_brave(name: str, city: str, state: str, country: str, brave_key: str) -> Optional[str]:
    """
    Use Brave Search to confirm the business exists and return a website URL
    if found.  Only called when OSM geocoding fails.
    Returns website URL string or None.
    """
    if requests is None:
        return None

    query = f"{name} mezcal {city} {state} {country}".strip()
    headers = {
        "Accept": "application/json",
        "Accept-Encoding": "gzip",
        "X-Subscription-Token": brave_key,
    }
    params = {"q": query, "count": 3, "country": country or "US"}

    try:
        resp = requests.get(BRAVE_BASE_URL, headers=headers, params=params, timeout=10)
        resp.raise_for_status()
        data = resp.json()
        results = data.get("web", {}).get("results", [])
        if results:
            return results[0].get("url")
    except Exception as e:
        print(f"  [WARN] Brave Search error for '{name}': {e}")

    time.sleep(BRAVE_DELAY_SEC)
    return None


# ---------------------------------------------------------------------------
# Deduplication
# ---------------------------------------------------------------------------

def is_duplicate(candidate: dict, existing_spots: list[dict]) -> Optional[str]:
    """
    Returns the Firestore document ID of the matching existing spot, or None.
    Match criteria: name prefix (6 chars) AND coordinates within threshold.
    """
    c_name = candidate["name"].lower()[:6]
    c_lat = candidate["latitude"]
    c_lon = candidate["longitude"]

    for spot in existing_spots:
        e_name = spot.get("name", "").lower()[:6]
        e_lat = spot.get("latitude", 0.0)
        e_lon = spot.get("longitude", 0.0)

        if (
            c_name == e_name
            and abs(c_lat - e_lat) < PROXIMITY_THRESHOLD_DEG
            and abs(c_lon - e_lon) < PROXIMITY_THRESHOLD_DEG
        ):
            return spot.get("id", "?")

    return None


# ---------------------------------------------------------------------------
# CSV parsing
# ---------------------------------------------------------------------------

def parse_csv(path: Path) -> list[dict]:
    """Parse the input CSV and return a list of raw candidate dicts."""
    candidates = []
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row_num, row in enumerate(reader, start=2):  # start=2: header is row 1
            name = row.get("name", "").strip()
            if not name:
                print(f"  [SKIP] Row {row_num}: missing name — skipping.")
                continue

            country = row.get("country", "US").strip().upper() or "US"
            if country not in SUPPORTED_COUNTRIES:
                print(f"  [SKIP] Row {row_num} '{name}': unsupported country '{country}'.")
                continue

            raw_cats = [c.strip().lower() for c in row.get("categories", "mezcal").split(",") if c.strip()]
            categories = [c for c in raw_cats if c in VALID_CATEGORIES] or ["mezcal"]

            raw_offerings = row.get("mezcalOfferings", "").strip()
            offerings = (
                [o.strip() for o in raw_offerings.split(",") if o.strip()]
                if raw_offerings else []
            )

            lat_str = row.get("latitude", "").strip()
            lon_str = row.get("longitude", "").strip()

            try:
                lat = float(lat_str) if lat_str else None
                lon = float(lon_str) if lon_str else None
            except ValueError:
                lat, lon = None, None

            candidates.append({
                "_row": row_num,
                "name": name,
                "address": row.get("address", "").strip(),
                "city": row.get("city", "").strip(),
                "state": row.get("state", "").strip(),
                "country": country,
                "latitude": lat,
                "longitude": lon,
                "categories": categories,
                "mezcalOfferings": offerings,
                "websiteURL": row.get("websiteURL", "").strip() or None,
            })

    return candidates


# ---------------------------------------------------------------------------
# Firestore document builder
# ---------------------------------------------------------------------------

def build_firestore_doc(candidate: dict, geo: dict) -> dict:
    """
    Assembles a Firestore document dict that matches the Swift Spot Codable model.
    All optional Swift fields that have no value are omitted (Firestore ignores missing keys).
    """
    now = datetime.now(timezone.utc)

    address_parts = [p for p in [
        candidate["address"],
        candidate["city"],
        candidate["state"],
        candidate["country"],
    ] if p]
    address = ", ".join(address_parts) or geo.get("mapItemName", candidate["name"])

    doc: dict = {
        "id": str(uuid.uuid4()),
        "name": candidate["name"],
        "address": address,
        "latitude": geo["latitude"],
        "longitude": geo["longitude"],
        "mapItemName": geo.get("mapItemName", candidate["name"]),
        "categories": candidate["categories"],
        "addedByUserID": IMPORT_SYSTEM_USER_ID,
        "addedDate": now,
        "averageRating": 0.0,
        "reviewCount": 0,
        # Moderation defaults
        "isReported": False,
        "reportCount": 0,
        "reportedByUserIDs": [],
        "isHidden": False,
        # Import provenance (new fields from Step 1)
        "source": "import",
        "importDate": now,
        "communityVerified": False,
    }

    if candidate.get("mezcalOfferings"):
        doc["mezcalOfferings"] = candidate["mezcalOfferings"]
    if candidate.get("websiteURL"):
        doc["websiteURL"] = candidate["websiteURL"]

    return doc


# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------

def run(args: argparse.Namespace) -> None:
    # ── Dependency check ────────────────────────────────────────────────────
    if firebase_admin is None:
        sys.exit("ERROR: firebase-admin not installed.\n  Run: pip install firebase-admin requests")
    if requests is None:
        sys.exit("ERROR: requests not installed.\n  Run: pip install firebase-admin requests")

    csv_path = Path(args.csv)
    if not csv_path.exists():
        sys.exit(f"ERROR: CSV file not found: {csv_path}")

    sa_path = Path(args.service_account)
    if not sa_path.exists():
        sys.exit(f"ERROR: Service account file not found: {sa_path}")

    commit = args.commit
    brave_key: Optional[str] = getattr(args, "brave_key", None) or None

    print(f"\n{'='*60}")
    print(f"  Flezcal Mezcal Spot Importer")
    print(f"  Mode: {'COMMIT (writing to Firestore)' if commit else 'DRY RUN (read-only)'}")
    print(f"  CSV:  {csv_path}")
    print(f"  Brave Search: {'enabled' if brave_key else 'disabled'}")
    print(f"{'='*60}\n")

    # ── Init Firebase ────────────────────────────────────────────────────────
    cred = credentials.Certificate(str(sa_path))
    firebase_admin.initialize_app(cred)
    db = admin_firestore.client()

    # ── Load existing spots for deduplication ────────────────────────────────
    print("Loading existing Firestore spots for deduplication…")
    existing_docs = db.collection(FIRESTORE_COLLECTION).stream()
    existing_spots: list[dict] = []
    for doc in existing_docs:
        d = doc.to_dict()
        d["id"] = doc.id
        existing_spots.append(d)
    print(f"  Found {len(existing_spots)} existing spot(s).\n")

    # ── Parse CSV ────────────────────────────────────────────────────────────
    candidates = parse_csv(csv_path)
    print(f"Parsed {len(candidates)} candidate(s) from CSV.\n")

    # ── Process each candidate ───────────────────────────────────────────────
    written = 0
    skipped_dup = 0
    skipped_no_geo = 0

    for candidate in candidates:
        row = candidate["_row"]
        name = candidate["name"]
        print(f"[Row {row}] {name}")

        # Step A: resolve coordinates
        lat = candidate["latitude"]
        lon = candidate["longitude"]

        if lat is None or lon is None:
            print(f"  No lat/lon in CSV — geocoding via Nominatim…")
            time.sleep(NOMINATIM_DELAY_SEC)
            geo_result = geocode_nominatim(
                name,
                candidate["address"],
                candidate["city"],
                candidate["state"],
                candidate["country"],
            )
            if geo_result:
                lat = geo_result["latitude"]
                lon = geo_result["longitude"]
                map_item_name = geo_result["mapItemName"]
                print(f"  Nominatim → ({lat:.5f}, {lon:.5f})")
            elif brave_key:
                print(f"  Nominatim failed — trying Brave Search for website…")
                website = verify_brave(name, candidate["city"], candidate["state"], candidate["country"], brave_key)
                if website and not candidate.get("websiteURL"):
                    candidate["websiteURL"] = website
                    print(f"  Brave found website: {website}")
                # Still no coordinates
                print(f"  [SKIP] Could not resolve coordinates for '{name}' — skipping.")
                skipped_no_geo += 1
                continue
            else:
                print(f"  [SKIP] Could not resolve coordinates for '{name}' — skipping (no Brave key).")
                skipped_no_geo += 1
                continue
        else:
            map_item_name = f"{name}, {candidate['city']}, {candidate['state']}".strip(", ")
            geo_result = {"latitude": lat, "longitude": lon, "mapItemName": map_item_name}

        candidate["latitude"] = lat
        candidate["longitude"] = lon

        # Step B: deduplication
        dup_id = is_duplicate(candidate, existing_spots)
        if dup_id:
            print(f"  [SKIP] Duplicate of existing spot {dup_id}")
            skipped_dup += 1
            continue

        # Step C: build document
        doc = build_firestore_doc(candidate, geo_result)
        doc_id = doc["id"]

        print(f"  → Will write: id={doc_id}, categories={doc['categories']}, "
              f"lat={doc['latitude']:.5f}, lon={doc['longitude']:.5f}")

        # Step D: write (or dry-run)
        if commit:
            db.collection(FIRESTORE_COLLECTION).document(doc_id).set(doc)
            print(f"  ✓ Written to Firestore")
            # Add to local list so next iterations can deduplicate against it
            existing_spots.append(doc)
        else:
            print(f"  (dry-run — not written)")

        written += 1

    # ── Summary ──────────────────────────────────────────────────────────────
    print(f"\n{'='*60}")
    print(f"  Done.")
    print(f"  Candidates processed : {len(candidates)}")
    print(f"  {'Written' if commit else 'Would write':<22}: {written}")
    print(f"  Skipped (duplicates) : {skipped_dup}")
    print(f"  Skipped (no geo)     : {skipped_no_geo}")
    print(f"{'='*60}\n")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Import curated mezcal spots into Flezcal Firestore.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--csv", required=True, help="Path to input CSV file")
    parser.add_argument(
        "--service-account",
        required=True,
        metavar="KEY_JSON",
        help="Path to Firebase service account JSON key file",
    )
    parser.add_argument(
        "--commit",
        action="store_true",
        default=False,
        help="Actually write to Firestore (default is dry-run)",
    )
    parser.add_argument(
        "--brave-key",
        default=None,
        metavar="API_KEY",
        help="Brave Search API key (metered — optional, used as fallback when OSM geocoding fails)",
    )

    args = parser.parse_args()
    run(args)


if __name__ == "__main__":
    main()
