import SwiftUI
import UIKit

struct ContentView: View {
    /// Stores the version string of the last welcome screen the user dismissed.
    /// When Firestore's "version" field changes, the welcome screen re-appears.
    @AppStorage("lastSeenWelcomeVersion") private var lastSeenWelcomeVersion: String = ""
    @StateObject private var welcomeService = WelcomeService()
    @StateObject private var picksService = UserPicksService()
    @State private var showWelcome = false
    @State private var selectedTab: Int = AppTab.explore

    // Plain (non-reactive) reference — intentionally NOT @EnvironmentObject.
    // ContentView never reads locationManager.userLocation in its body, so
    // there is no reason for it to subscribe. Subscribing would cause ContentView
    // to re-render on every location update, which in turn rebuilds ListTabView
    // and can cancel the in-flight Explore search task. See ListTabView stability
    // contract for a full explanation.
    let locationManager: LocationManager

    var body: some View {
        TabView(selection: $selectedTab) {
            MapTabView()
                .environmentObject(picksService)
                .tabItem { Label("Explore", systemImage: "map") }
                .tag(AppTab.explore)

            MyPicksTabView()
                .environmentObject(picksService)
                .tabItem { Label("My Picks", systemImage: "heart.circle") }
                .tag(AppTab.myPicks)

            ListTabView(locationManager: locationManager, picksService: picksService)
                .tabItem { Label("List", systemImage: "list.bullet") }
                .tag(AppTab.list)

            AddSpotView()
                .environmentObject(picksService)
                .tabItem { Label("Add Spot", systemImage: "plus.circle") }
                .tag(AppTab.addSpot)

            LeaderboardView()
                .tabItem { Label("Leaderboard", systemImage: "trophy") }
                .tag(AppTab.leaderboard)

            ProfileView(onShowWhatsNew: { showWelcome = true })
                .tabItem { Label("Profile", systemImage: "person.circle") }
                .tag(AppTab.profile)
        }
        .tint(.orange)
        .onReceive(NotificationCenter.default.publisher(for: .switchToAddSpot)) { _ in
            selectedTab = AppTab.addSpot
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
}
