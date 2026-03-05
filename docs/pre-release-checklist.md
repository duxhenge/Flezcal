# Flezcal Pre-Release Audit Checklist

**Use before every TestFlight push. Claude Code can help with items marked [CC].**

---

## 1. Build Verification

- [ ] CI pipeline passes (all three jobs green on latest push)
- [ ] Archive builds successfully in Xcode (Product > Archive)
- [ ] No new compiler warnings in Release configuration

## 2. Test Coverage Assessment [CC]

- [ ] All existing unit tests pass locally (`Cmd+U` or `xcodebuild test`)
- [ ] Review coverage report from CI: target >= 30% overall
- [ ] Critical services have test coverage:
  - [ ] Spot model logic (SpotModelTests)
  - [ ] SpotCategory raw value stability (SpotCategoryTests)
  - [ ] CustomCategory validation and keyword generation (CustomCategoryTests)
  - [ ] RatingLevel computations (RatingLevelTests)
  - [ ] ClosureReport codable (ClosureReportTests)
- [ ] Any new model or service logic has corresponding tests

## 3. Performance Profiling (Instruments)

**Run each check on a physical device (not Simulator). Attach via Product > Profile (Cmd+I).**

### Memory (Allocations + Leaks)

- [ ] Launch app, navigate all tabs, open 3 spot details, return to map: **no leaks reported**
- [ ] Memory stays below **150 MB** during normal use
- [ ] After returning to Map tab from deep navigation, memory returns within 20 MB of baseline
- [ ] No retain cycles: open SpotDetailView, dismiss, check Allocations for zombie Spot objects

### Time Profiler

- [ ] App launch to interactive (first tab visible): **< 3 seconds** on iPhone 13 or later
- [ ] Tab switch latency: **< 200ms** for all tabs
- [ ] Map ghost pin appearance after camera settle: **< 2 seconds** (network dependent)
- [ ] Explore search results appear: **< 1 second** after typing stops

### Network

- [ ] Ghost pin search (SuggestionService): verify <= 50 MKLocalSearch calls per minute
- [ ] Spot detail open: verify no redundant Firestore reads (offline cache should serve)
- [ ] Brave API calls per ghost pin tap: verify <= 8 calls (JS-heavy path)

### Energy (Energy Log instrument)

- [ ] Background: verify zero network activity when app is backgrounded
- [ ] Location updates: verify no continuous GPS polling (only when-in-use, map visible)

## 4. Security Review — OWASP MASVS L1 Spot-Check [CC]

### MASVS-AUTH: Authentication

- [ ] Sign in with Apple: nonce is unique per request (AuthService.swift)
- [ ] Email auth: passwords not logged anywhere (grep for "password" near print/NSLog)
- [ ] Session expiry: Firebase handles token refresh — verify no custom token storage

### MASVS-STORAGE: Data Storage

- [ ] `Secrets.xcconfig` in `.gitignore` (CI secret scan verifies this)
- [ ] `GoogleService-Info.plist` in `.gitignore`
- [ ] `serviceAccountKey.json` in `.gitignore`
- [ ] No API keys hardcoded in Swift files (SwiftLint custom rule verifies)
- [ ] `UserDefaults` only stores non-sensitive data (user picks, UI preferences)
- [ ] No sensitive data in `print()` statements (grep for uid, email, token near print)

### MASVS-NETWORK: Network Security

- [ ] `NSAllowsArbitraryLoads = true` is documented and justified (broken SSL on restaurant sites)
- [ ] TLS 1.0 minimum is documented and justified (same reason)
- [ ] All Firestore/Firebase calls use Firebase SDK (automatic TLS 1.2+)
- [ ] Brave API calls use HTTPS only (verify in WebsiteCheckService)

### MASVS-PLATFORM: Platform Interaction

- [ ] Info.plist usage descriptions are accurate and non-generic:
  - [ ] NSLocationWhenInUseUsageDescription — references flan and mezcal
  - [ ] NSPhotoLibraryUsageDescription — references spot photos
- [ ] No unused permission requests in Info.plist
- [ ] URL schemes: none registered (no deep linking attack surface)

### MASVS-CODE: Code Quality

- [ ] No `as!` or `try!` in production code (SwiftLint enforces)
- [ ] Error messages shown to users do not expose internal details
- [ ] `CrashReporter` context strings do not contain user PII

## 5. Firestore Rules Review [CC]

- [ ] Admin UID in `firestore.rules` matches `AdminAccess.adminUID` in code
- [ ] Count admin UID occurrences in firestore.rules: should be exactly 8
- [ ] Verify: unauthenticated users CANNOT create spots, reviews, or verifications
- [ ] Verify: users CANNOT modify other users' reviews or verifications
- [ ] Verify: spot updates only allow the documented field sets

## 6. UI/UX Consistency (HIG Spot-Check)

- [ ] Dark mode: all screens render correctly (Settings > Display > Dark Mode)
- [ ] Dynamic Type: test with Accessibility > Larger Text at maximum size
- [ ] VoiceOver: all interactive elements have accessibility labels
- [ ] Tab bar icons use SF Symbols per HIG
- [ ] Alert dialogs use standard iOS patterns
- [ ] Age verification gate appears on first launch

## 7. Dependency Check [CC]

- [ ] Check Firebase iOS SDK for updates: compare current version vs latest release
- [ ] If update available, review changelog for breaking changes and security fixes
- [ ] No new SPM dependencies added without review

## 8. Pre-Submission Items

- [ ] `privacyPolicyURL` and `supportURL` point to live, accessible pages
- [ ] Privacy policy page is current and matches app behavior
- [ ] App version and/or build number bumped
- [ ] Crashlytics dashboard: check for unresolved crashes from previous build
- [ ] TestFlight release notes written
