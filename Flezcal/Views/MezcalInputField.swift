import SwiftUI

/// A text field with autocomplete suggestions for any category's offerings.
/// Shows up to 5 matching suggestions from the provided list as the user types.
/// Users can pick a suggestion or type any custom value.
struct OfferingInputField: View {
    @Binding var text: String
    let placeholder: String
    /// All known offerings for this category — static brands + community-sourced.
    /// The view filters this list as the user types.
    let knownOfferings: [String]
    /// SF Symbol shown next to each suggestion. Defaults to "tag" for generic categories.
    var suggestionIcon: String = "tag"
    /// If true, uses VeladoraIcon instead of an SF Symbol (mezcal-specific).
    var useVeladoraIcon: Bool = false

    @State private var showSuggestions = false
    @FocusState private var isFocused: Bool

    private var suggestions: [String] {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return knownOfferings.filter { $0.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onChange(of: text) { _, newValue in
                    showSuggestions = isFocused && !newValue.isEmpty && !suggestions.isEmpty
                }
                .onChange(of: isFocused) { _, focused in
                    showSuggestions = focused && !text.isEmpty && !suggestions.isEmpty
                }

            if showSuggestions {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions.prefix(5), id: \.self) { suggestion in
                        Button {
                            text = suggestion
                            showSuggestions = false
                            isFocused = false
                        } label: {
                            HStack {
                                if useVeladoraIcon {
                                    VeladoraIcon(size: 14)
                                } else {
                                    Image(systemName: suggestionIcon)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(suggestion)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        Divider()
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            }
        }
    }
}

// MARK: - Legacy wrapper

/// Convenience wrapper that uses the static MezcalBrands list + VeladoraIcon.
/// Keeps existing call sites working without changes during migration.
struct MezcalInputField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        OfferingInputField(
            text: $text,
            placeholder: placeholder,
            knownOfferings: MezcalBrands.all,
            useVeladoraIcon: true
        )
    }
}

// MARK: - Community offerings aggregator

/// Aggregates offerings across all saved spots for a given category,
/// ranked by frequency (most common first). For mezcal, merges the
/// static brand list as a base so users see suggestions even before
/// any community data exists.
enum CommunityOfferings {

    /// Returns a deduplicated, frequency-ranked list of known offerings
    /// for the given category, drawn from all saved spots.
    /// For mezcal and tea, static lists are used as a base,
    /// supplemented by any community-added entries not on the list.
    static func suggestions(for category: SpotCategory, from spots: [Spot]) -> [String] {
        // Count how many spots list each offering
        var frequency: [String: Int] = [:]
        for spot in spots where !spot.isHidden && !spot.isClosed {
            for offering in spot.offerings(for: category) {
                let trimmed = offering.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                frequency[trimmed, default: 0] += 1
            }
        }

        // Categories with curated suggestion lists (Firestore override > hardcoded > nil)
        let staticList: [String]? = {
            if let firestoreList = OfferingListService.overridesSnapshot[category.rawValue],
               !firestoreList.isEmpty {
                return firestoreList
            }
            return switch category {
            case .mezcal: MezcalBrands.all
            case .tea:    TeaVarieties.all
            default:      nil
            }
        }()

        if let staticList {
            let staticSet = Set(staticList.map { $0.lowercased() })
            let communityExtras = frequency.keys
                .filter { !staticSet.contains($0.lowercased()) }
                .sorted { (frequency[$0] ?? 0) > (frequency[$1] ?? 0) }
            return staticList + communityExtras
        }

        // Other categories: sort by frequency (most popular first), then alphabetically
        return frequency.keys.sorted { a, b in
            let fa = frequency[a] ?? 0
            let fb = frequency[b] ?? 0
            if fa != fb { return fa > fb }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        OfferingInputField(
            text: .constant("Del"),
            placeholder: "e.g. Del Maguey Vida",
            knownOfferings: MezcalBrands.all,
            useVeladoraIcon: true
        )
        OfferingInputField(
            text: .constant("Class"),
            placeholder: "e.g. Classic, Coconut",
            knownOfferings: ["Classic", "Coconut", "Cheese Flan", "Chocolate"],
            suggestionIcon: "birthday.cake"
        )
    }
    .padding()
}
