#!/bin/sh
#
# deploy_firestore_rules.sh
# Deploys firestore.rules to Firebase using the REST API.
# Runs as an Xcode build phase — skips on Debug builds.
# Non-blocking: warns but does NOT fail the build on errors.

set -e

# ─── Skip on Debug builds ───────────────────────────────────────────────
if [ "$CONFIGURATION" != "Release" ]; then
    echo "ℹ️  Skipping Firestore rules deploy (not Release build)"
    exit 0
fi

# ─── Configuration ──────────────────────────────────────────────────────
SRCROOT="${SRCROOT:-.}"
RULES_FILE="$SRCROOT/firestore.rules"
SA_KEY_FILE="$SRCROOT/scripts/serviceAccountKey.json"
PROJECT_ID="flezcal-e3045"

# ─── Validate inputs ────────────────────────────────────────────────────
if [ ! -f "$RULES_FILE" ]; then
    echo "⚠️  Firestore rules file not found at $RULES_FILE — skipping deploy"
    exit 0
fi

if [ ! -f "$SA_KEY_FILE" ]; then
    echo "⚠️  Service account key not found at $SA_KEY_FILE — skipping deploy"
    exit 0
fi

# ─── Temp files ──────────────────────────────────────────────────────────
PRIVATE_KEY_FILE=$(mktemp /tmp/firebase_pk.XXXXXX)
TOKEN_RESP_FILE=$(mktemp /tmp/firebase_token.XXXXXX)
RULESET_RESP_FILE=$(mktemp /tmp/firebase_ruleset.XXXXXX)
RELEASE_RESP_FILE=$(mktemp /tmp/firebase_release.XXXXXX)
REQUEST_BODY_FILE=$(mktemp /tmp/firebase_body.XXXXXX)

cleanup() {
    rm -f "$PRIVATE_KEY_FILE" "$TOKEN_RESP_FILE" "$RULESET_RESP_FILE" "$RELEASE_RESP_FILE" "$REQUEST_BODY_FILE"
}
trap cleanup EXIT

# ─── Extract service account fields ─────────────────────────────────────
CLIENT_EMAIL=$(/usr/bin/python3 -c "import json; print(json.load(open('$SA_KEY_FILE'))['client_email'])")

/usr/bin/python3 -c "
import json
key = json.load(open('$SA_KEY_FILE'))['private_key']
with open('$PRIVATE_KEY_FILE', 'w') as f:
    f.write(key)
"

# ─── Generate JWT for OAuth2 ────────────────────────────────────────────
NOW=$(/bin/date +%s)
EXP=$(($NOW + 3600))

JWT_HEADER=$(printf '{"alg":"RS256","typ":"JWT"}' | /usr/bin/base64 | tr '+/' '-_' | tr -d '=\n')

JWT_PAYLOAD=$(printf '{"iss":"%s","scope":"https://www.googleapis.com/auth/firebase","aud":"https://oauth2.googleapis.com/token","iat":%d,"exp":%d}' "$CLIENT_EMAIL" "$NOW" "$EXP" | /usr/bin/base64 | tr '+/' '-_' | tr -d '=\n')

SIGNING_INPUT="${JWT_HEADER}.${JWT_PAYLOAD}"
JWT_SIGNATURE=$(printf '%s' "$SIGNING_INPUT" | /usr/bin/openssl dgst -sha256 -sign "$PRIVATE_KEY_FILE" -binary | /usr/bin/base64 | tr '+/' '-_' | tr -d '=\n')

JWT="${SIGNING_INPUT}.${JWT_SIGNATURE}"

# ─── Exchange JWT for access token ──────────────────────────────────────
echo "🔑 Requesting OAuth2 access token..."
curl -s -X POST "https://oauth2.googleapis.com/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=$JWT" \
    -o "$TOKEN_RESP_FILE"

ACCESS_TOKEN=$(/usr/bin/python3 -c "
import json, sys
with open('$TOKEN_RESP_FILE') as f:
    resp = json.load(f)
if 'access_token' in resp:
    print(resp['access_token'])
else:
    print('ERROR: ' + resp.get('error_description', resp.get('error', 'unknown')), file=sys.stderr)
    sys.exit(1)
") || {
    echo "⚠️  Failed to obtain access token — skipping Firestore rules deploy"
    exit 0
}

# ─── Build request body with rules content ───────────────────────────────
/usr/bin/python3 -c "
import json
with open('$RULES_FILE', 'r') as f:
    rules = f.read()
body = {'source': {'files': [{'content': rules, 'name': 'firestore.rules'}]}}
with open('$REQUEST_BODY_FILE', 'w') as f:
    json.dump(body, f)
"

# ─── Step 1: Create ruleset ─────────────────────────────────────────────
echo "📤 Deploying Firestore rules..."
curl -s -X POST \
    "https://firebaserules.googleapis.com/v1/projects/$PROJECT_ID/rulesets" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d @"$REQUEST_BODY_FILE" \
    -o "$RULESET_RESP_FILE"

RULESET_NAME=$(/usr/bin/python3 -c "
import json, sys
with open('$RULESET_RESP_FILE') as f:
    resp = json.load(f)
if 'name' in resp:
    print(resp['name'])
else:
    print('ERROR: ' + json.dumps(resp), file=sys.stderr)
    sys.exit(1)
") || {
    echo "⚠️  Failed to create ruleset — skipping deploy"
    exit 0
}

echo "   Created ruleset: $RULESET_NAME"

# ─── Step 2: Update release to point to new ruleset ─────────────────────
RELEASE_NAME="projects/$PROJECT_ID/releases/cloud.firestore"
curl -s -X PATCH \
    "https://firebaserules.googleapis.com/v1/$RELEASE_NAME?updateMask=rulesetName" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d "{\"release\":{\"name\":\"$RELEASE_NAME\",\"rulesetName\":\"$RULESET_NAME\"}}" \
    -o "$RELEASE_RESP_FILE"

RELEASE_OK=$(/usr/bin/python3 -c "
import json, sys
with open('$RELEASE_RESP_FILE') as f:
    resp = json.load(f)
if 'name' in resp:
    print('ok')
else:
    print('ERROR: ' + json.dumps(resp), file=sys.stderr)
    sys.exit(1)
") || {
    echo "⚠️  Ruleset created but failed to update release — manual deploy may be needed"
    exit 0
}

echo "✅ Firestore rules deployed successfully!"
