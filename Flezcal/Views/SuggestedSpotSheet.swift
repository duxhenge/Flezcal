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
    /// All user picks being checked — used to show all category chips during loading.
    var userPicks: [FoodCategory] = []

    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var spotService: SpotService
    @EnvironmentObject var photoService: PhotoService
    @Environment(\.dismiss) private var dismiss
    @State private var showAddSpot = false
    @State private var showSignIn = false
    /// Tracks that the user tapped "add" while unsigned — auto-proceed after sign-in.
    @State private var pendingAddAfterSignIn = false
    /// Frozen copy captured when the sheet first appears.
    @State private var frozenResult: MultiCategoryCheckResult? = nil

    /// The FoodCategory the suggestion was found for.
    private var suggestedCategory: FoodCategory { suggestion.suggestedCategory }

    /// All picks being checked — user picks plus the primary pick if not already included.
    private var allCheckedPicks: [FoodCategory] {
        var picks = userPicks
        if !picks.contains(where: { $0.id == suggestedCategory.id }) {
            picks.insert(suggestedCategory, at: 0)
        }
        return picks.isEmpty ? [suggestedCategory] : picks
    }
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
    /// Only confirmed picks are pre-filled — relatedFound matches require user
    /// verification and should not be automatically included. If nothing was
    /// confirmed, falls back to the primary pick so the user can still add.
    private var spotCategories: [SpotCategory] {
        guard let result = displayResult else {
            // Still loading — just use the primary pick
            return [SpotCategory(rawValue: suggestedCategory.id) ?? .mezcal]
        }
        // Only confirmed categories are addable — relatedFound need verification first
        if !result.confirmed.isEmpty {
            return result.confirmed.compactMap { SpotCategory(rawValue: $0.id) }
        }
        // Nothing confirmed — use the primary pick so the user can still add
        return [SpotCategory(rawValue: result.primaryPick.id) ?? .mezcal]
    }

    /// All categories detected by the website scan (confirmed + related).
    /// Stored on the Spot so unverified categories show as "potential".
    private var detectedCategoryIDs: [String]? {
        guard let result = displayResult else { return nil }
        let confirmed = result.confirmed.map(\.id)
        let related = result.relatedFound.map(\.category.id)
        let all = confirmed + related
        return all.isEmpty ? nil : all
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
        if !result.confirmed.isEmpty && !result.relatedFound.isEmpty {
            // Confirmed + related on same venue
            let confirmedNames = result.confirmed.map { $0.displayName.lowercased() }.joined(separator: ", ")
            let relatedMatch = result.relatedFound.first!
            return (
                icon: "checkmark.seal.fill",
                color: result.confirmed.first?.color ?? suggestedCategory.color,
                message: "We found \(confirmedNames) on their website. Also found '\(relatedMatch.keyword)' — can you verify they have \(relatedMatch.category.displayName.lowercased())?"
            )
        }
        if !result.confirmed.isEmpty {
            let names = result.confirmed.map { $0.displayName.lowercased() }
                .joined(separator: ", ")
            return (
                icon: "checkmark.seal.fill",
                color: result.confirmed.first?.color ?? suggestedCategory.color,
                message: "We found mentions of \(names) on their website."
            )
        }
        if !result.relatedFound.isEmpty {
            // Related-only (no confirmed) — amber verification prompt
            let relatedMatch = result.relatedFound.first!
            return (
                icon: "eye.fill",
                color: Color(red: 0.7, green: 0.5, blue: 0.0),
                message: "We found '\(relatedMatch.keyword)' on their menu — help verify if they have \(relatedMatch.category.displayName.lowercased())!"
            )
        }
        // Nothing confirmed or related — list all picks that were checked
        let allNames = result.notFound.map { $0.displayName.lowercased() }
        let nameList = allNames.joined(separator: " or ")
        return (
            icon: "questionmark.circle",
            color: .secondary,
            message: "We checked their website but couldn't find a mention of \(nameList)."
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    sheetContent
                    actionButtons
                }
            }
            .onAppear {
                if let result = multiResult {
                    frozenResult = result
                }
            }
            .onChange(of: multiResult) { _, newValue in
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
            .sheet(isPresented: $showSignIn) {
                SignInSheet()
                    .environmentObject(authService)
                    .presentationDetents([.medium])
            }
            .onChange(of: authService.isSignedIn) { _, signedIn in
                if signedIn && pendingAddAfterSignIn {
                    pendingAddAfterSignIn = false
                    // Small delay so the sign-in sheet finishes dismissing
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showAddSpot = true
                    }
                }
            }
            .sheet(isPresented: $showAddSpot) {
                ConfirmSpotView(
                    mapItem: suggestion.mapItem,
                    categories: spotCategories,
                    preVerified: true,
                    websiteDetectedCategories: detectedCategoryIDs
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

    // MARK: - Extracted Subviews

    @ViewBuilder
    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Source label
            Label(
                source == .exploreSearch
                    ? "Found via Apple Maps search"
                    : "Suggested by Apple Maps",
                systemImage: "sparkles"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            categoryChips

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

            existingSpotBanner
            websiteCheckBannerView
            userPromptText
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var categoryChips: some View {
        HStack(spacing: 6) {
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

            if let result = displayResult {
                let existingIDs = Set(existingCategories.map(\.id))
                let newConfirmed = result.confirmed.filter { !existingIDs.contains($0.id) }
                let relatedNew = result.relatedFound.filter { !existingIDs.contains($0.category.id) }
                let notFoundNew = result.notFound.filter { !existingIDs.contains($0.id) }
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
                ForEach(relatedNew, id: \.category.id) { match in
                    HStack(spacing: 4) {
                        FoodCategoryIcon(category: match.category, size: 18)
                        Text(match.category.displayName)
                        Image(systemName: "questionmark")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.15))
                    .foregroundStyle(Color(red: 0.7, green: 0.5, blue: 0.0))
                    .clipShape(Capsule())
                }
                ForEach(notFoundNew) { cat in
                    HStack(spacing: 4) {
                        FoodCategoryIcon(category: cat, size: 18)
                        Text(cat.displayName)
                        Image(systemName: "minus.circle")
                            .font(.caption2)
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
                }
            } else if existingCategories.isEmpty {
                ForEach(allCheckedPicks) { cat in
                    HStack(spacing: 4) {
                        FoodCategoryIcon(category: cat, size: 18)
                        Text(cat.displayName)
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(cat.color.opacity(0.15))
                    .foregroundStyle(cat.color)
                    .clipShape(Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private var existingSpotBanner: some View {
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
    }

    @ViewBuilder
    private var websiteCheckBannerView: some View {
        let banner = websiteCheckBanner
        VStack(alignment: .leading, spacing: 4) {
            Label(banner.message, systemImage: banner.icon)
                .font(.subheadline)
                .foregroundStyle(banner.color)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(banner.color.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Label("Web searches aren't as reliable as your own knowledge — but we'll give it our best shot!", systemImage: "info.circle")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var userPromptText: some View {
        Group {
            if existingSpot != nil {
                if let result = displayResult {
                    let existingIDs = Set(existingCategories.map(\.id))
                    let newCats = result.confirmed.filter { !existingIDs.contains($0.id) }
                    let newRelated = result.relatedFound.filter { !existingIDs.contains($0.category.id) }
                    if !newCats.isEmpty {
                        let newNames = newCats.map { $0.displayName.lowercased() }.joined(separator: ", ")
                        Text("This spot is already on Flezcal. We also found \(newNames) on their website — tap below to add \(newCats.count == 1 ? "it" : "them").")
                    } else if !newRelated.isEmpty {
                        let match = newRelated.first!
                        Text("This spot is already on Flezcal. We found '\(match.keyword)' on their website — if they have \(match.category.displayName.lowercased()), tap below to add it.")
                    } else {
                        Text("This spot is already on Flezcal. You can still update it with new categories or mezcal offerings.")
                    }
                } else {
                    Text("This spot is already on Flezcal. Checking their website for more categories…")
                }
            } else if let result = displayResult {
                if !result.confirmed.isEmpty {
                    Text("Know this place? If you've been here, add it so the community can find it.")
                } else if !result.relatedFound.isEmpty {
                    let match = result.relatedFound.first!
                    Text("We spotted '\(match.keyword)' on their menu. If you know they have \(match.category.displayName.lowercased()), add it so the community can find it.")
                } else if result.websiteUnavailable {
                    let pickNames = result.notFound.map { $0.displayName.lowercased() }.joined(separator: " or ")
                    Text("Know this place? If they have \(pickNames), add it so the community can find it. If it doesn't belong, \(source == .exploreSearch ? "dismiss this." : "remove the pin.")")
                } else {
                    let pickNames = result.notFound.map { $0.displayName.lowercased() }.joined(separator: " or ")
                    Text("The website didn't mention \(pickNames) — but menus aren't always online. Know this place? Add it if they have what you're looking for.")
                }
            } else {
                let pickNames = allCheckedPicks.map { $0.displayName.lowercased() }.joined(separator: " or ")
                Text("Know this place? If they have \(pickNames), add it so the community can find it. If it doesn't belong, \(source == .exploreSearch ? "dismiss this." : "remove the pin.")")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                if authService.isSignedIn {
                    showAddSpot = true
                } else {
                    pendingAddAfterSignIn = true
                    showSignIn = true
                }
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

// MARK: - Ghost Pin View

/// Three-tier ghost pin shown on the map for unconfirmed suggestions.
///
/// **Yellow (default):** Dashed outline, "?" center — not yet scanned.
/// **Green (`isLikely`):** Solid outline, pulse animation, category badge — homepage
/// HTML matched keywords for the user's active picks.
/// **Gray (`isScanned` but not likely):** Solid outline, "−" center — scanned, no match found.
struct GhostPinView: View {
    let category: FoodCategory
    /// Set to true when the batch homepage pre-screen found keywords for this venue.
    var isLikely: Bool = false
    /// Set to true when the pre-screen has run (regardless of result).
    var isScanned: Bool = false
    /// Categories matched during pre-screen — used for the badge icon on green pins.
    var likelyCategories: [FoodCategory] = []

    @State private var isPulsing = false

    var body: some View {
        if isLikely {
            greenPin
        } else if isScanned {
            grayPin
        } else {
            yellowPin
        }
    }

    // MARK: - Yellow pin (not yet scanned)

    private var yellowPin: some View {
        ZStack {
            Circle()
                .fill(Color.yellow.opacity(0.2))
                .frame(width: 36, height: 36)

            Circle()
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
                .foregroundStyle(Color.yellow.opacity(0.85))
                .frame(width: 36, height: 36)

            Text("?")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.yellow.opacity(0.85))
        }
    }

    // MARK: - Scanned pin (checked, no match on homepage)
    // Keeps the yellow color to stay visually present on the map,
    // but swaps "?" for "−" so users can tell it was already scanned.
    // Still tappable — the full 3-pass check may find matches that
    // the quick homepage scan missed.

    private var grayPin: some View {
        ZStack {
            Circle()
                .fill(Color.yellow.opacity(0.12))
                .frame(width: 34, height: 34)

            Circle()
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
                .foregroundStyle(Color.yellow.opacity(0.5))
                .frame(width: 34, height: 34)

            Image(systemName: "minus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.yellow.opacity(0.5))
        }
    }

    // MARK: - Green pin (likely match)

    private var greenPin: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 38, height: 38)

                Circle()
                    .strokeBorder(lineWidth: 1.5)
                    .foregroundStyle(Color.green.opacity(0.9))
                    .frame(width: 38, height: 38)

                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.green)
            }
            .scaleEffect(isPulsing ? 1.08 : 1.0)
            .animation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }

            // Category badge — small circle with emoji at bottom-right
            if let first = likelyCategories.first {
                FoodCategoryIcon(category: first, size: 12)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.white))
                    .overlay(Circle().stroke(Color.green.opacity(0.5), lineWidth: 0.5))
                    .offset(x: 4, y: 4)
            }
        }
    }
}
