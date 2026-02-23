import SwiftUI

/// A text field with autocomplete suggestions for mezcal brand names.
/// Users can pick a suggestion or type any custom brand name.
struct MezcalInputField: View {
    @Binding var text: String
    let placeholder: String

    @State private var showSuggestions = false
    @FocusState private var isFocused: Bool

    private var suggestions: [String] {
        MezcalBrands.suggestions(for: text)
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
                                VeladoraIcon(size: 14)
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

#Preview {
    VStack {
        MezcalInputField(text: .constant("Del"), placeholder: "e.g. Del Maguey Vida")
    }
    .padding()
}
