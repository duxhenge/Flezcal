import SwiftUI
import UIKit
import CoreLocation

struct ContentView: View {
    /// Stores the version string of the last welcome screen the user dismissed.
    /// When Firestore's "version" field changes, the welcome screen re-appears.
    @AppStorage("lastSeenWelcomeVersion") private var lastSeenWelcomeVersion: String = ""
    @EnvironmentObject var networkMonitor: NetworkMonitor
    /// Used ONLY for the display-name prompt — `needsDisplayNamePrompt` changes at
    /// most once per session, so this does NOT cause continuous re-renders like
    /// locationManager would. See the comment on `let locationManager` below.
    @EnvironmentObject var authService: AuthService
    @StateObject private var welcomeService = WelcomeService()
    @StateObject private var picksService = UserPicksService()
    @StateObject private var rankingService = RankingService()
    @StateObject private var tutorialService = TutorialService()
    @State private var showWelcome = false
    @State private var showTutorialCurriculum = false
    @State private var selectedTab: Int = AppTab.explore
    /// Set by the .showOnMap notification — MapTabView picks this up,
    /// centers the camera, and shows the ghost pin sheet.
    @State private var pendingMapSuggestion: SuggestedSpot? = nil
    /// Set by the .showAreaOnMap notification — MapTabView picks this up,
    /// centers the camera on the area, and runs fetchAndPreScreen.
    @State private var pendingMapCenter: CLLocationCoordinate2D? = nil
    /// Set by the .showSpotsAtLocation notification — ListTabView picks this up
    /// and sets its customLocation so the Spots tab searches from that area.
    @State private var pendingSpotsLocation: CustomSearchLocation? = nil
    /// Shared Flezcal filter state — which pick pills are active.
    /// Synced between Map and Spots tabs so toggling a pill on one tab
    /// carries over when switching to the other.
    @State private var activePickIDs: Set<String> = []
    @State private var activePickIDsInitialized = false
    /// Community Map mode — shows all verified spots across all 50 categories,
    /// hides ghost pins. Shared between Map and Spots tabs.
    @State private var showCommunityMap = false
    @State private var showDisplayNamePrompt = false
    @State private var promptedName = ""

    // Plain (non-reactive) reference — intentionally NOT @EnvironmentObject.
    // ContentView never reads locationManager.userLocation in its body, so
    // there is no reason for it to subscribe. Subscribing would cause ContentView
    // to re-render on every location update, which in turn rebuilds ListTabView
    // and can cancel the in-flight Explore search task. See ListTabView stability
    // contract for a full explanation.
    let locationManager: LocationManager

    /// Single shared instance so htmlCache is reused across both tabs.
    /// Explore pre-screen results carry over to Map ghost pins instantly.
    private let websiteChecker = WebsiteCheckService()

    /// Feature flags (singleton) — drives beta feedback button visibility.
    @ObservedObject private var featureFlags = FeatureFlagService.shared

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                MapTabView(pendingMapSuggestion: $pendingMapSuggestion,
                          pendingMapCenter: $pendingMapCenter,
                          activePickIDs: $activePickIDs,
                          showCommunityMap: $showCommunityMap,
                          websiteChecker: websiteChecker)
                    .environmentObject(picksService)
                    .tabItem { Label("Explore", systemImage: "map") }
                    .tag(AppTab.explore)

                ListTabView(locationManager: locationManager, picksService: picksService, activePickIDs: $activePickIDs, showCommunityMap: $showCommunityMap, pendingSpotsLocation: $pendingSpotsLocation, websiteChecker: websiteChecker)
                    .tabItem { Label("Spots", systemImage: "list.bullet") }
                    .tag(AppTab.spots)

                MyPicksTabView()
                    .environmentObject(picksService)
                    .tabItem { Label("My Flezcals", systemImage: "heart.circle") }
                    .tag(AppTab.myPicks)

                LeaderboardView()
                    .tabItem { Label("Leaderboard", systemImage: "trophy") }
                    .tag(AppTab.leaderboard)

                ProfileView(
                    onShowWhatsNew: { showWelcome = true },
                    onShowTutorials: { showTutorialCurriculum = true }
                )
                    .tabItem { Label("Profile", systemImage: "person.circle") }
                    .tag(AppTab.profile)
            }
            .tint(.orange)

            // Offline banner
            if !networkMonitor.isConnected {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.caption2)
                    Text("You're offline. Changes will sync when you reconnect.")
                        .font(.caption2)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.secondary)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: networkMonitor.isConnected)
                .accessibilityLabel("You are offline. Changes will sync when you reconnect.")
            }

            // Beta feedback floating button — controlled by FeatureFlagService.
            // Not shown on admin dashboard (it's a fullScreenCover above this).
            BetaFeedbackButton(
                featureFlags: featureFlags,
                userPickNames: picksService.picks.map(\.displayName)
            )

            // Tutorial spotlight overlay — renders above everything when active
            TutorialOverlay(tutorialService: tutorialService)
        }
        .environmentObject(rankingService)
        .onAppear {
            featureFlags.startListening()
            tutorialService.switchTab = { tab in selectedTab = tab }
            // Initialize shared filter state with all picks active
            if !activePickIDsInitialized {
                activePickIDs = Set(picksService.picks.map(\.id))
                activePickIDsInitialized = true
            }
        }
        .onDisappear { featureFlags.stopListening() }
        .onChange(of: picksService.picks) { _, newPicks in
            // When picks change (added/removed/swapped), reset all to active
            activePickIDs = Set(newPicks.map(\.id))
        }
        .overlayPreferenceValue(TutorialTargetKey.self) { anchors in
            GeometryReader { geo in
                Color.clear
                    .onChange(of: anchors.count) { _, _ in
                        updateTargetFrames(anchors: anchors, geo: geo)
                    }
                    .onChange(of: selectedTab) { _, _ in
                        // Re-resolve anchors when tab changes — different targets become visible
                        updateTargetFrames(anchors: anchors, geo: geo)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            updateTargetFrames(anchors: anchors, geo: geo)
                        }
                    }
                    .onChange(of: tutorialService.currentStepIndex) { _, _ in
                        // Re-resolve when the tutorial advances — target may have just appeared
                        updateTargetFrames(anchors: anchors, geo: geo)
                    }
                    .onAppear {
                        updateTargetFrames(anchors: anchors, geo: geo)
                    }
            }
            .allowsHitTesting(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToSpots)) { _ in
            selectedTab = AppTab.spots
        }
        .onReceive(NotificationCenter.default.publisher(for: .showOnMap)) { notification in
            if let suggestion = notification.userInfo?["suggestion"] as? SuggestedSpot {
                pendingMapSuggestion = suggestion
            }
            selectedTab = AppTab.explore
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAreaOnMap)) { notification in
            if let info = notification.userInfo,
               let lat = info["latitude"] as? Double,
               let lon = info["longitude"] as? Double {
                pendingMapCenter = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            selectedTab = AppTab.explore
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSpotsAtLocation)) { notification in
            if let info = notification.userInfo,
               let lat = info["latitude"] as? Double,
               let lon = info["longitude"] as? Double {
                let name = info["name"] as? String ?? "Map Area"
                pendingSpotsLocation = CustomSearchLocation(
                    name: name,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                )
            }
            selectedTab = AppTab.spots
        }
        .wormEasterEgg()
        .sheet(isPresented: $showWelcome) {
            WelcomeView { version in
                lastSeenWelcomeVersion = version
                showWelcome = false
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showTutorialCurriculum) {
            TutorialCurriculumView(tutorialService: tutorialService)
                .presentationDetents([.large])
        }
        .onChange(of: tutorialService.shouldShowCurriculum) { _, show in
            if show {
                tutorialService.shouldShowCurriculum = false
                showTutorialCurriculum = true
            }
        }
        .onChange(of: showWelcome) { _, isShowing in
            // After the welcome sheet is dismissed for the first time, show the tutorial curriculum
            if !isShowing && !tutorialService.hasShownCurriculum {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showTutorialCurriculum = true
                    tutorialService.markCurriculumShown()
                }
            }
        }
        .task {
            // Fetch welcome content version — WelcomeService is a @StateObject so it
            // persists for the lifetime of ContentView and won't be re-created on re-renders.
            await welcomeService.fetchWelcomeContent()
            if let version = welcomeService.content?.version, version != lastSeenWelcomeVersion {
                showWelcome = true
            } else if !tutorialService.hasShownCurriculum {
                // Welcome didn't trigger (already seen or network error) but curriculum
                // hasn't been shown yet — show it directly on first launch.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showTutorialCurriculum = true
                    tutorialService.markCurriculumShown()
                }
            }
            // Fetch category rankings (Top 50 / Trending tiers).
            // Falls back to hardcoded defaults if offline or doc missing.
            await rankingService.fetchRankings()
        }
        .onChange(of: authService.isSignedIn) { _, _ in
            // Pick tracking now fires only on deliberate user actions
            // (toggle/add), not on sign-in. No sync needed here.
        }
        .onChange(of: authService.needsDisplayNamePrompt) { _, needsPrompt in
            if needsPrompt {
                promptedName = ""
                showDisplayNamePrompt = true
            }
        }
        .alert("What should we call you?", isPresented: $showDisplayNamePrompt) {
            TextField("Your name", text: $promptedName)
                .autocorrectionDisabled()
            Button("Save") {
                Task { await authService.saveDisplayNameToFirestore(promptedName) }
            }
            .disabled(promptedName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Skip", role: .cancel) {
                authService.needsDisplayNamePrompt = false
            }
        } message: {
            Text("This name appears on the leaderboard. You can change it later in Profile.")
        }
    }

    /// Resolves anchor preferences from tutorial target views into CGRect frames.
    /// Merges into existing frames so that a re-render of one tab doesn't wipe
    /// out frames reported by another tab.
    private func updateTargetFrames(anchors: [String: Anchor<CGRect>], geo: GeometryProxy) {
        var frames = tutorialService.targetFrames
        for (id, anchor) in anchors {
            let rect = geo[anchor]
            if rect.width > 0 && rect.height > 0 {
                frames[id] = rect
            }
        }
        tutorialService.targetFrames = frames
    }
}

// MARK: - Shake Detection

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
    }
}

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

struct OnShakeModifier: ViewModifier {
    let action: () -> Void
    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            action()
        }
    }
}

extension View {
    func onShake(_ action: @escaping () -> Void) -> some View {
        modifier(OnShakeModifier(action: action))
    }
}

// MARK: - Worm Overlay

struct WormOverlay: View {
    @Binding var isVisible: Bool

    @State private var xOffset: CGFloat = -120
    @State private var yOffset: CGFloat = 0
    @State private var wiggle: Double = 0

    var body: some View {
        GeometryReader { geo in
            if isVisible {
                VStack(spacing: 0) {
                    Text("🐛")
                        .font(.system(size: 52))
                        .rotationEffect(.degrees(-90))
                        .scaleEffect(x: -1)
                        .offset(x: xOffset, y: yOffset)
                        .rotationEffect(.degrees(wiggle), anchor: .center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .onAppear {
                    yOffset = CGFloat.random(in: -geo.size.height * 0.3 ... geo.size.height * 0.3)
                    xOffset = -120
                    withAnimation(.easeInOut(duration: 0.18).repeatForever(autoreverses: true)) {
                        wiggle = 12
                    }
                    withAnimation(.linear(duration: 3.2)) {
                        xOffset = geo.size.width + 120
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.3) {
                        isVisible = false
                        wiggle = 0
                    }
                }

                Text("Shake for worm 🫨")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 100)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - Worm Easter Egg Modifier

struct WormEasterEggModifier: ViewModifier {
    @State private var showWorm = false

    func body(content: Content) -> some View {
        ZStack {
            content
            WormOverlay(isVisible: $showWorm)
        }
        .onShake {
            guard !showWorm else { return }
            showWorm = true
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
        }
    }
}

extension View {
    func wormEasterEgg() -> some View {
        modifier(WormEasterEggModifier())
    }
}

#Preview {
    ContentView(locationManager: LocationManager())
        .environmentObject(NetworkMonitor.shared)
        .environmentObject(AuthService())
}
