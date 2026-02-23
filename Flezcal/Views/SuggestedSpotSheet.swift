import SwiftUI
import MapKit

/// Where the sheet was opened from — controls copy that is context-specific.
enum SuggestedSpotSource {
    /// Tapped a ghost pin on the map.
    case ghostPin
    /// Tapped a result in the List tab's Explore search.
    case exploreSearch
}

/// Sheet shown when a user taps a ghost suggestion pin or an Explore search result.
/// Lets them confirm (opens Add Spot flow) or dismiss.
struct SuggestedSpotSheet: View {
    let suggestion: SuggestedSpot
    /// Live multi-category result passed in from the map — snapshotted on
    /// appear so the sheet doesn't flicker as background checks continue.
    let multiResult: MultiCategoryCheckResult?
    let onConfirm: () -> Void
    let onDismiss: () -> Void
    /// Where this sheet was opened from — adjusts copy for ghost pin vs. Explore search.
    var source: SuggestedSpotSource = .ghostPin

    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var spotService: SpotService
    @EnvironmentObject var photoService: PhotoService
    @Environment(\.dismiss) private var dismiss
    @State private var showAddSpot = false
    /// Frozen copy captured when the sheet first appears.
    @State private var frozenResult: MultiCategoryCheckResult? = nil

    /// The FoodCategory the suggestion was found for.
    private var suggestedCategory: FoodCategory { suggestion.suggestedCategory }
    /// Use the frozen result so the sheet is stable after opening.
    private var displayResult: MultiCategoryCheckResult? { frozenResult }

    /// If this venue is already confirmed in Firestore, this holds the existing Spot.
    private var existingSpot: Spot? {
        guard let coord = suggestion.mapItem.placemark.location?.coordinate,
              let name = suggestion.mapItem.name else { return nil }
        return spotService.findExistingSpot(
            name: name, latitude: coord.latitude, longitude: coord.longitude
        )
    }

    /// FoodCategories already confirmed on this spot in Firestore.
    private var existingCategories: [FoodCategory] {
        guard let spot = existingSpot else { return [] }
        return spot.categories.compactMap { FoodCategory(spotCategory: $0) }
    }

    /// SpotCategories to pass to ConfirmSpotView.
    /// Uses confirmed picks when available, otherwise falls back to the primary pick.
    private var spotCategories: [SpotCategory] {
        guard let result = displayResult else {
            // Still loading — just use the primary pick
            return [SpotCategory(rawValue: suggestedCategory.id) ?? .mezcal]
        }
        if !result.confirmed.isEmpty {
            return result.confirmed.compactMap { SpotCategory(rawValue: $0.id) }
        }
        // Nothing confirmed — use the primary pick so the user can still add
        return [SpotCategory(rawValue: result.primaryPick.id) ?? .mezcal]
    }

    /// Banner message and icon based on the multi-category website check.
    /// When the spot already exists in Firestore, the banner focuses on
    /// newly-discovered categories rather than contradicting existing data.
    private var websiteCheckBanner: (icon: String, color: Color, message: String) {
        guard let result = displayResult else {
            return (
                icon: "magnifyingglass",
                color: .secondary,
                message: "Checking their website…"
            )
        }

        let existingIDs = Set(existingCategories.map(\.id))

        // Categories confirmed by website check that are NOT already in Firestore
        let newlyConfirmed = result.confirmed.filter { !existingIDs.contains($0.id) }
        // Categories confirmed by website check that ARE already in Firestore
        let reconfirmed = result.confirmed.filter { existingIDs.contains($0.id) }

        if result.websiteUnavailable {
            if existingSpot != nil {
                return (
                    icon: "wifi.slash",
                    color: .secondary,
                    message: "No website on file — but this spot is already confirmed by the community."
                )
            }
            return (
                icon: "wifi.slash",
                color: .secondary,
                message: "No website on file for this location."
            )
        }

        // When the spot already exists, tailor the message
        if existingSpot != nil {
            if !newlyConfirmed.isEmpty {
                let names = newlyConfirmed.map { $0.displayName.lowercased() }.joined(separator: ", ")
                return (
                    icon: "plus.circle.fill",
                    color: newlyConfirmed.first?.color ?? .orange,
                    message: "We also found \(names) on their website — a new category to add!"
                )
            }
            if !reconfirmed.isEmpty {
                let names = reconfirmed.map { $0.displayName.lowercased() }.joined(separator: ", ")
                return (
                    icon: "checkmark.seal.fill",
                    color: reconfirmed.first?.color ?? .orange,
                    message: "Their website confirms \(names) — matches the community data."
                )
            }
            // Website didn't find any picks, but spot is already confirmed
            return (
                icon: "checkmark.circle",
                color: .orange,
                message: "Website scan didn't find your picks, but this spot is confirmed by the community."
            )
        }

        // Not an existing spot — original behavior
        if !result.confirmed.isEmpty {
            let names = result.confirmed.map { $0.displayName.lowercased() }
                .joined(separator: ", ")
            return (
                icon: "checkmark.seal.fill",
                color: result.confirmed.first?.color ?? suggestedCategory.color,
                message: "We found mentions of \(names) on their website."
            )
        }
        // primaryResult was notFound (or unavailable with a URL present)
        let primaryName = result.primaryPick.displayName.lowercased()
        return (
            icon: "questionmark.circle",
            color: .secondary,
            message: "We checked their website but couldn't find a mention of \(primaryName)."
        )
    }

    var body: some View {
        NavigationStack {
            // ScrollView ensures the buttons are never clipped on smaller screens
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Source label — replaces the removed mini-map preview
                        Label(
                            source == .exploreSearch
                                ? "Found via Apple Maps search"
                                : "Suggested by Apple Maps",
                            systemImage: "sparkles"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        // Category chips — existing Firestore categories + website check results
                        HStack(spacing: 6) {
                            // 1. Show existing Firestore categories (already confirmed by community)
                            ForEach(existingCategories) { cat in
                                HStack(spacing: 4) {
                                    FoodCategoryIcon(category: cat, size: 18)
                                    Text(cat.displayName)
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                }
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(cat.color.opacity(0.15))
                                .foregroundStyle(cat.color)
                                .clipShape(Capsule())
                            }

                            // 2. Show website-check confirmed categories (excluding those already in Firestore)
                            if let result = displayResult, !result.confirmed.isEmpty {
                                let existingIDs = Set(existingCategories.map(\.id))
                                let newConfirmed = result.confirmed.filter { !existingIDs.contains($0.id) }
                                ForEach(newConfirmed) { cat in
                                    HStack(spacing: 4) {
                                        FoodCategoryIcon(category: cat, size: 18)
                                        Text(cat.displayName)
                                        Image(systemName: "checkmark")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                    }
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(cat.color.opacity(0.15))
                                    .foregroundStyle(cat.color)
                                    .clipShape(Capsule())
                                }
                            } else if existingCategories.isEmpty {
                                // Loading and no existing spot — show primary pick placeholder
                                HStack(spacing: 4) {
                                    FoodCategoryIcon(category: suggestedCategory, size: 20)
                                    Text(suggestedCategory.displayName)
                                }
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(suggestedCategory.color.opacity(0.15))
                                .foregroundStyle(suggestedCategory.color)
                                .clipShape(Capsule())
                            }
                        }

                        // Name & address
                        Text(suggestion.name)
                            .font(.title3)
                            .fontWeight(.bold)

                        if !suggestion.address.isEmpty {
                            Label(suggestion.address, systemImage: "mappin")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // ── Already on Flezcal banner ─────────────────────────
                        if let spot = existingSpot {
                            let catNames = spot.categories.map(\.displayName).joined(separator: ", ")
                            Label(
                                "Already on Flezcal for \(catNames).",
                                systemImage: "star.fill"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.top, 4)
                        }

                        // ── Website check result banner ───────────────────────
                        let banner = websiteCheckBanner
                        Label(banner.message, systemImage: banner.icon)
                            .font(.subheadline)
                            .foregroundStyle(banner.color)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(banner.color.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.top, 4)

                        // User prompt
                        Group {
                            if existingSpot != nil {
                                // Venue already exists — prompt to add new categories if any detected
                                if let result = displayResult {
                                    let existingIDs = Set(existingCategories.map(\.id))
                                    let newCats = result.confirmed.filter { !existingIDs.contains($0.id) }
                                    if !newCats.isEmpty {
                                        let newNames = newCats.map { $0.displayName.lowercased() }.joined(separator: ", ")
                                        Text("This spot is already on Flezcal. We also found \(newNames) on their website — tap below to add \(newCats.count == 1 ? "it" : "them").")
                                    } else {
                                        Text("This spot is already on Flezcal. You can still update it with new categories or mezcal offerings.")
                                    }
                                } else {
                                    Text("This spot is already on Flezcal. Checking their website for more categories…")
                                }
                            } else if let result = displayResult {
                                if !result.confirmed.isEmpty {
                                    Text("Know this place? If you've been here, add it so the community can find it.")
                                } else if result.websiteUnavailable {
                                    let primaryName = result.primaryPick.displayName.lowercased()
                                    Text("Know this place? If they have \(primaryName), add it so the community can find it. If it doesn't belong, \(source == .exploreSearch ? "dismiss this." : "remove the pin.")")
                                } else {
                                    let primaryName = result.primaryPick.displayName.lowercased()
                                    Text("The website didn't mention \(primaryName) — but menus aren't always online. Know this place? Add it if they have \(primaryName).")
                                }
                            } else {
                                let primaryName = suggestedCategory.displayName.lowercased()
                                Text("Know this place? If they have \(primaryName), add it so the community can find it. If it doesn't belong, \(source == .exploreSearch ? "dismiss this." : "remove the pin.")")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Action buttons — inside the scroll view so they're always reachable
                    VStack(spacing: 12) {
                        Button {
                            showAddSpot = true
                        } label: {
                            Label(
                                existingSpot != nil
                                    ? "Update this spot"
                                    : "Yes, add it to Flezcal!",
                                systemImage: existingSpot != nil
                                    ? "pencil.circle.fill"
                                    : "checkmark.circle.fill"
                            )
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(existingSpot != nil ? .orange : suggestedCategory.color)

                        // Open the venue in Apple Maps so the user can check
                        // the listing, menu link, photos, or reviews directly.
                        Button {
                            suggestion.mapItem.openInMaps()
                        } label: {
                            Label("View in Apple Maps", systemImage: "map")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)

                        // Show on Map — only from Explore search (already on map from ghost pin)
                        if source == .exploreSearch {
                            Button {
                                NotificationCenter.default.post(
                                    name: .showOnMap,
                                    object: nil,
                                    userInfo: ["suggestion": suggestion]
                                )
                                dismiss()
                            } label: {
                                Label("Show on Map", systemImage: "map.fill")
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            }
                            .buttonStyle(.bordered)
                            .tint(.green)
                        }

                        Button(role: .destructive) {
                            onDismiss()
                            dismiss()
                        } label: {
                            Label(
                                source == .exploreSearch
                                    ? "Not what I'm looking for"
                                    : "Not accurate, remove pin",
                                systemImage: "xmark.circle"
                            )
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                    }
                    .padding()
                }
            }
            .onAppear {
                // Snapshot immediately if result already arrived
                if let result = multiResult {
                    frozenResult = result
                }
            }
            .onChange(of: multiResult) { _, newValue in
                // Accept the first result that arrives, then freeze
                if frozenResult == nil, let newValue {
                    frozenResult = newValue
                }
            }
            .navigationTitle("Suggested Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddSpot) {
                ConfirmSpotView(
                    mapItem: suggestion.mapItem,
                    categories: spotCategories,
                    preVerified: true
                ) {
                    onConfirm()
                    dismiss()
                }
                .environmentObject(authService)
                .environmentObject(spotService)
                .environmentObject(photoService)
            }
        }
    }
}

// MARK: - Ghost Pin View

/// Semi-transparent dashed pin shown on the map for unconfirmed suggestions.
/// All ghost pins look identical — website check only happens on tap.
struct GhostPinView: View {
    let category: FoodCategory

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.85))
                .frame(width: 36, height: 36)

            Circle()
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
                .foregroundStyle(category.color.opacity(0.85))
                .frame(width: 36, height: 36)

            Text("?")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(category.color.opacity(0.85))
        }
    }
}
