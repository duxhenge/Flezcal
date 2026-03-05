# Flezcal Quarterly Deep Audit

**Audit Date**: ___________
**Build Version**: ___________
**Auditor**: ___________
**Previous Audit Date**: ___________

---

## 1. Full OWASP MASVS L1 Review

### MASVS-STORAGE (Data Storage and Privacy)

| # | Check | Status | Notes |
|---|-------|--------|-------|
| S-1 | App does not store sensitive data in system logs | | Grep all print/NSLog/os_log for PII |
| S-2 | No sensitive data in backups | | Check excluded paths from iCloud backup |
| S-3 | No sensitive data exposed via IPC | | No custom URL schemes, no App Groups |
| S-4 | No sensitive data in keyboard cache | | Check `.textContentType` on password fields |
| S-5 | Clipboard does not contain sensitive data | | No custom copy operations on sensitive fields |
| S-6 | No PII in Crashlytics beyond user UID | | Review CrashReporter custom values |
| S-7 | All secrets in Secrets.xcconfig (gitignored) | | Verify no new keys added to code |

### MASVS-CRYPTO (Cryptography)

| # | Check | Status | Notes |
|---|-------|--------|-------|
| C-1 | SHA256 nonce for Sign in with Apple uses CryptoKit | | AuthService.sha256() |
| C-2 | SecRandomCopyBytes for nonce generation | | AuthService.randomNonceString() |
| C-3 | No custom crypto implementations | | All crypto via Firebase SDK or CryptoKit |
| C-4 | No hardcoded encryption keys | | N/A — no local encryption |

### MASVS-AUTH (Authentication and Session Management)

| # | Check | Status | Notes |
|---|-------|--------|-------|
| A-1 | Firebase Auth token refresh is automatic | | Verify SDK version handles this |
| A-2 | Sign-out clears all user state | | Review AuthService.signOut() |
| A-3 | Account deletion cascades correctly | | Review AuthService.deleteAccount() |
| A-4 | Re-authentication required for destructive actions | | deleteAccount() can throw requiresRecentLogin |
| A-5 | Admin UID not exploitable from client | | Client-side admin gate is convenience only; Firestore rules enforce |

### MASVS-NETWORK (Network Communication)

| # | Check | Status | Notes |
|---|-------|--------|-------|
| N-1 | All Firebase SDK calls use TLS 1.2+ | | SDK-managed |
| N-2 | Brave API calls use HTTPS | | Verify URL construction in WebsiteCheckService |
| N-3 | Certificate pinning: N/A (acceptable for L1) | | |
| N-4 | NSAllowsArbitraryLoads documented justification still valid | | Review if restaurant site landscape changed |
| N-5 | TLS 1.0 fallback only for restaurant website fetches | | Verify webSession config |

### MASVS-PLATFORM (Platform Interaction)

| # | Check | Status | Notes |
|---|-------|--------|-------|
| P-1 | All WebView content (if any) is sandboxed | | No WKWebView in project |
| P-2 | No JavaScript bridges | | N/A |
| P-3 | Custom URL scheme handling: N/A | | No URL schemes registered |
| P-4 | Input validation on all user inputs | | CustomCategory.validate(), review text fields |
| P-5 | Content filtering on user-generated content | | CustomCategory.isBlocked(), review text moderation |

### MASVS-CODE (Code Quality and Build Settings)

| # | Check | Status | Notes |
|---|-------|--------|-------|
| Q-1 | App is signed with valid certificate | | Check Xcode signing settings |
| Q-2 | Debug code stripped from release | | Verify #if DEBUG guards |
| Q-3 | No debug logging in release | | SwiftLint no_bare_print rule |
| Q-4 | Stack traces not shown to users | | Error messages use friendly wrappers |
| Q-5 | Binary protections enabled | | Check Xcode build settings for stack canaries |

### MASVS-RESILIENCE (not required for L1 — track only)

| # | Check | Status | Notes |
|---|-------|--------|-------|
| R-1 | Jailbreak detection: not implemented | | Acceptable for L1 |
| R-2 | Anti-tampering: not implemented | | Acceptable for L1 |

---

## 2. Dependency Vulnerability Scan

### Firebase iOS SDK

- Current version: _________
- Latest version: _________
- Security advisories since last audit: _________
- Action needed: _________

### Transitive Dependencies

Check via SPM resolution log or `Package.resolved`:

| Dependency | Version | CVEs Found | Action |
|-----------|---------|------------|--------|
| swift-protobuf | | | |
| grpc-swift | | | |
| abseil-cpp | | | |
| GoogleUtilities | | | |
| nanopb | | | |
| leveldb | | | |

### How to Check

```bash
# Check Firebase releases
# (requires gh CLI)
gh api repos/firebase/firebase-ios-sdk/releases --jq '.[0:5] | .[] | .tag_name + " " + .published_at'

# Check for known vulnerabilities
gh api graphql -f query='{ securityVulnerabilities(first: 5, ecosystem: SWIFT, package: "firebase-ios-sdk") { nodes { advisory { summary severity } vulnerableVersionRange firstPatchedVersion { identifier } } } }'
```

---

## 3. Performance Baseline Comparison

Record these metrics and compare to previous quarter.

| Metric | Previous | Current | Delta | Threshold |
|--------|----------|---------|-------|-----------|
| Cold launch to interactive (s) | | | | < 3.0 |
| Warm launch to interactive (s) | | | | < 1.0 |
| Memory at idle — Map tab (MB) | | | | < 80 |
| Memory peak during search (MB) | | | | < 150 |
| Firestore reads per session (typical) | | | | < 200 |
| Brave API calls per session (typical) | | | | < 50 |
| App binary size (MB) | | | | < 50 |
| SPM dependency count | | | | Track growth |

---

## 4. Firestore Rules Audit

### Rules vs. Actual Usage Matrix

| Collection | Create | Read | Update | Delete | Rule Status |
|-----------|--------|------|--------|--------|-------------|
| spots | auth + ownerID | public | field-restricted | admin only | |
| reviews | auth + userID | public | report fields only | admin only | |
| verifications | auth + userID | public | owner only | owner only | |
| closure_reports | auth + reporterID | public | admin only | denied | |
| users | auth + self | public | auth + self | auth + self | |
| customCategories | auth + validation | public | pickCount only | denied | |
| admin_* | admin UID | admin UID | admin UID | N/A | |
| analytics_monthly | owner/admin | N/A | auth | denied | |
| viewer_log | self/owner/admin | N/A | self only | denied | |

### Specific Checks

- [ ] Count admin UID occurrences: should be exactly 8 in firestore.rules
- [ ] All `update` rules use `.diff().affectedKeys().hasOnly()` — no open-ended updates
- [ ] No collection allows `write: true` (unrestricted write)
- [ ] `delete: if false` on collections that should never have client deletes
- [ ] Timestamps: assess if `request.time` validation should be added
- [ ] Rate limiting: assess if Cloud Functions are needed for server-side rate limiting

---

## 5. Code Architecture Review [CC]

### File Size Health

Run and compare to previous quarter:

```bash
find Flezcal -name "*.swift" -exec wc -l {} \; | sort -rn | head -10
```

Files over 800 lines — evaluate for extraction:

| File | Lines (Previous) | Lines (Current) | Action |
|------|-----------------|-----------------|--------|
| SpotDetailView.swift | | | |
| ListTabView.swift | | | |
| WebsiteCheckService.swift | | | |
| MapTabView.swift | | | |

### Dependency Graph Health

- [ ] No circular dependencies between Services
- [ ] Services do not import View layer
- [ ] Models do not import Firebase (models should be plain structs)
- [ ] No new singletons beyond existing (NetworkMonitor.shared, AnalyticsService.shared, RateLimiter.shared)

### Concurrency Audit

- [ ] All `@MainActor` services are correctly annotated
- [ ] `actor WebsiteCheckService` properly isolates mutable state
- [ ] `actor RateLimiter` properly isolates mutable state
- [ ] No data races flagged by Thread Sanitizer (run tests with TSan enabled)

---

## 6. Privacy Compliance Review (Apple 5.1.2)

### Data Collection Declaration

Compare App Store privacy labels to actual data collection:

| Data Type | Collected? | Used For | Linked to Identity? | Where in Code |
|-----------|-----------|----------|---------------------|---------------|
| Email | Yes | Account | Yes | AuthService |
| Display Name | Yes | App Functionality | Yes | AuthService, Firestore users/ |
| Location (when-in-use) | Yes | App Functionality | No | LocationManager |
| Photos (library) | Yes | App Functionality | No | PhotoService |
| User ID | Yes | Account | Yes | Firebase Auth UID |
| Crash Data | Yes | Analytics | Yes (via UID) | Crashlytics |
| Usage Data | Yes | Analytics | Yes | AnalyticsService |

### Specific Checks

- [ ] App Privacy details on App Store Connect match the table above
- [ ] Data deletion: `deleteAccount()` removes all user data across all collections
- [ ] Location: only used when app is active and map is visible
- [ ] Photos: only accessed when user explicitly chooses to upload
- [ ] No third-party analytics SDKs beyond Firebase Crashlytics
- [ ] Crashlytics user ID is cleared on sign-out
- [ ] If using any third-party AI services: disclosed per Apple guideline 5.1.2
- [ ] Privacy policy URL is live and accurate

---

## 7. Audit Summary

### Issues Found

| # | Severity | Category | Description | Remediation |
|---|----------|----------|-------------|-------------|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |

### Metrics Trend

| Area | Trend | Notes |
|------|-------|-------|
| Security posture | | |
| Code quality | | |
| Performance | | |
| Test coverage | | |
| Dependency health | | |

### Action Items for Next Quarter

1.
2.
3.
