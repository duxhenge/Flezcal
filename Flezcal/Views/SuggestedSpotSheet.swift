import SwiftUI
import MapKit

/// Where the sheet was opened from — controls copy that is context-specific.
enum SuggestedSpotSource {
    /// Tapped a ghost pin on the map.
    case ghostPin
    /// Tapped a result in the List tab's Explore search.
    case exploreSearch
}

/// Sheet shown when a user taps a ghost pin or Explore search result for a
/// venue that does NOT yet exist in Firestore. Lets them confirm (opens
/// Add Spot flow) or dismiss.
///
/// Existing spots are now routed directly to SpotDetailView from the tap
/// handlers in MapTabView and ExplorePanel — they never reach this sheet.
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
    @State private var showFlezcalPicker = false
    @State private var selectedFlezcal: FoodCategory? = nil
    @State private var showConfirmSpot = false
    @State private var showSignIn = false
    /// Tracks that the user tapped "add" while unsigned — auto-proceed after sign-in.
    @State private var pendingAddAfterSignIn = false
    /// Frozen copy captured when the sheet first appears.
    @State private var frozenResult: MultiCategoryCheckResult? = nil
    /// Trending Flezcals from Firestore
    @StateObject private var customService = CustomCategoryService()
    @State private var showCreateTrending = false

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

    /// The SpotCategory for the user's selected Flezcal.
    /// Always returns a value — built-in IDs map to their case, custom IDs
    /// map to `.custom(id)`.
    private var selectedSpotCategory: SpotCategory? {
        guard let flezcal = selectedFlezcal else { return nil }
        return SpotCategory(rawValue: flezcal.id)
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
    private var websiteCheckBanner: (icon: String, color: Color, message: String) {
        guard let result = displayResult else {
            return (
                icon: "magnifyingglass",
                color: .secondary,
                message: "Checking their website…"
            )
        }

        if result.websiteUnavailable {
            return (
                icon: "wifi.slash",
                color: .secondary,
                message: "No website on file for this location."
            )
        }

        if !result.confirmed.isEmpty && !result.relatedFound.isEmpty {
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
            let relatedMatch = result.relatedFound.first!
            return (
                icon: "eye.fill",
                color: Color(red: 0.7, green: 0.5, blue: 0.0),
                message: "We found '\(relatedMatch.keyword)' on their menu — help verify if they have \(relatedMatch.category.displayName.lowercased())!"
            )
        }
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
                    Button("Skip") {
                        dismiss()
                    }
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        startAddFlow()
                    }
                }
            }
            .sheet(isPresented: $showFlezcalPicker) {
                FlezcalPickerView(
                    userPicks: userPicks,
                    allCategories: FoodCategory.allCategories,
                    disabledCategoryIDs: Set(),
                    onSelect: { category in
                        selectedFlezcal = category
                        #if DEBUG
                        print("[CustomFlezcal] Selected Flezcal: \(category.displayName) (id: \(category.id), isCustom: \(category.id.hasPrefix("custom_")))")
                        #endif
                        showFlezcalPicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showConfirmSpot = true
                        }
                    },
                    onCancel: {
                        showFlezcalPicker = false
                    },
                    trendingCategories: customService.customCategories.map { $0.toFoodCategory() },
                    onCreateTrending: {
                        showFlezcalPicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showCreateTrending = true
                        }
                    }
                )
                .task { await customService.fetchAll() }
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showConfirmSpot) {
                if let spotCat = selectedSpotCategory {
                    let _ = {
                        #if DEBUG
                        print("[CustomFlezcal] Opening ConfirmSpotView with SpotCategory: \(spotCat.rawValue) (isCustom: \(spotCat.isCustom))")
                        #endif
                    }()
                    ConfirmSpotView(
                        mapItem: suggestion.mapItem,
                        category: spotCat,
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
            .sheet(isPresented: $showCreateTrending) {
                CreateCustomCategoryView()
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

            websiteCheckBannerView
            userPromptText
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var categoryChips: some View {
        HStack(spacing: 6) {
            if let result = displayResult {
                ForEach(result.confirmed) { cat in
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
                ForEach(result.relatedFound, id: \.category.id) { match in
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
                ForEach(result.notFound) { cat in
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
            } else {
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
            if let result = displayResult {
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

    /// Starts the add-to-flezcal flow. If the website check confirmed exactly
    /// one category, skips the picker and goes straight to ConfirmSpotView.
    private func startAddFlow() {
        if let result = displayResult,
           result.confirmed.count == 1,
           let confirmedCat = result.confirmed.first {
            selectedFlezcal = confirmedCat
            showConfirmSpot = true
        } else {
            showFlezcalPicker = true
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                if authService.isSignedIn {
                    startAddFlow()
                } else {
                    pendingAddAfterSignIn = true
                    showSignIn = true
                }
            } label: {
                Label("Add to Flezcal", systemImage: "plus.circle.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(suggestedCategory.color)

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
