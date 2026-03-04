import SwiftUI
import FirebaseCore
import FirebaseCrashlytics
@main
struct FlezcalApp: App {
    @AppStorage("hasPassedAgeVerification") private var hasPassedAgeVerification = false
    @StateObject private var authService = AuthService()
    @StateObject private var spotService = SpotService()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var photoService = PhotoService()
    private let networkMonitor = NetworkMonitor.shared

    init() {
        FirebaseApp.configure()
        Crashlytics.crashlytics()
        // Firestore offline persistence is enabled by default in Firebase iOS SDK 11.x.
        // Writes are queued locally when offline and synced when connectivity resumes.
    }

    var body: some Scene {
        WindowGroup {
            if hasPassedAgeVerification {
                // locationManager is passed as a plain (non-reactive) let — NOT via
                // .environmentObject — so that ContentView and ListTabView never
                // subscribe to location updates. See ListTabView stability contract.
                // All other services remain as @EnvironmentObject.
                ContentView(locationManager: locationManager)
                    .environmentObject(authService)
                    .environmentObject(spotService)
                    .environmentObject(photoService)
                    .environmentObject(networkMonitor)
            } else {
                AgeVerificationView()
            }
        }
    }
}
