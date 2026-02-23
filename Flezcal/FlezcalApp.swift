import SwiftUI
import FirebaseCore

@main
struct FlezcalApp: App {
    @StateObject private var authService = AuthService()
    @StateObject private var spotService = SpotService()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var photoService = PhotoService()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            // locationManager is passed as a plain (non-reactive) let — NOT via
            // .environmentObject — so that ContentView and ListTabView never
            // subscribe to location updates. See ListTabView stability contract.
            // All other services remain as @EnvironmentObject.
            ContentView(locationManager: locationManager)
                .environmentObject(authService)
                .environmentObject(spotService)
                .environmentObject(photoService)
        }
    }
}
