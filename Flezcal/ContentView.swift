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
    @State private var showWelcome = false
    @State private var selectedTab: Int = AppTab.explore
    /// Set by the .showOnMap notification — MapTabView picks this up,
    /// centers the camera, and shows the ghost pin sheet.
    @State private var pendingMapSuggestion: SuggestedSpot? = nil
    /// Set by the .showAreaOnMap notification — MapTabView picks this up,
    /// centers the camera on the area, and runs fetchAndPreScreen.
    @State private var pendingMapCenter: CLLocationCoordinate2D? = nil
    @State private var showDisplayNamePrompt = false
    @State private var promptedName = ""

    // Plain (non-reactive) reference — intentionally NOT @EnvironmentObject.
    // ContentView never reads locationManager.userLocation in its body, so
    // there is no reason for it to subscribe. Subscribing would cause ContentView
    // to re-render on every location update, which in turn rebuilds ListTabView
    // and can cancel the in-flight Explore search task. See ListTabView stability
    // contract for a full explanation.
    let locationManager: LocationManager

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                MapTabView(pendingMapSuggestion: $pendingMapSuggestion,
                          pendingMapCenter: $pendingMapCenter)
                    .environmentObject(picksService)
                    .tabItem { Label("Explore", systemImage: "map") }
                    .tag(AppTab.explore)

                ListTabView(locationManager: locationManager, picksService: picksService)
                    .tabItem { Label("Spots", systemImage: "list.bullet") }
                    .tag(AppTab.spots)

                MyPicksTabView()
                    .environmentObject(picksService)
                    .tabItem { Label("My Flezcals", systemImage: "heart.circle") }
                    .tag(AppTab.myPicks)

                LeaderboardView()
                    .tabItem { Label("Leaderboard", systemImage: "trophy") }
                    .tag(AppTab.leaderboard)

                ProfileView(onShowWhatsNew: { showWelcome = true })
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
        .wormEasterEgg()
        .sheet(isPresented: $showWelcome) {
            WelcomeView { version in
                lastSeenWelcomeVersion = version
                showWelcome = false
            }
            .presentationDetents([.large])
        }
        .task {
            // Fetch welcome content version — WelcomeService is a @StateObject so it
            // persists for the lifetime of ContentView and won't be re-created on re-renders.
            await welcomeService.fetchWelcomeContent()
            if let version = welcomeService.content?.version, version != lastSeenWelcomeVersion {
                showWelcome = true
            }
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
