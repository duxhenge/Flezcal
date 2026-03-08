import SwiftUI

/// Modal sheet for submitting beta feedback.
struct BetaFeedbackFormView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var feedbackService = BetaFeedbackService()
    @ObservedObject var featureFlags: FeatureFlagService

    /// The user's currently selected Flezcal pick names, passed from ContentView.
    let userPickNames: [String]

    @State private var selectedCategory: FeedbackCategory = .suggestion
    @State private var city: String = ""
    @State private var feedbackText: String = ""
    @State private var showThankYou = false

    /// Pre-fill city from the last submission.
    @AppStorage("betaFeedback_lastCity") private var lastCity: String = ""

    private var canSubmit: Bool {
        feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
    }

    var body: some View {
        NavigationStack {
            Form {
                // Prompt text from feature flag
                Section {
                    Text(featureFlags.betaFeedbackPromptText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                // Category picker
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(FeedbackCategory.allCases) { cat in
                            Label(cat.displayName, systemImage: cat.iconName)
                                .tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // City
                Section("City (optional)") {
                    TextField("What city are you exploring?", text: $city)
                        .textContentType(.addressCity)
                        .autocorrectionDisabled()
                }

                // Feedback text
                Section("Your feedback") {
                    TextEditor(text: $feedbackText)
                        .frame(minHeight: 150)
                        .overlay(alignment: .topLeading) {
                            if feedbackText.isEmpty {
                                Text("Tell us what you think...")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }

                    if !canSubmit && !feedbackText.isEmpty {
                        Text("Please write at least 10 characters.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Submit
                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if feedbackService.isSubmitting {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Sending...")
                            } else {
                                Text("Submit Feedback")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit || feedbackService.isSubmitting)
                }
            }
            .navigationTitle("Share Your Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear {
                if city.isEmpty && !lastCity.isEmpty {
                    city = lastCity
                }
            }
            .overlay {
                if showThankYou {
                    thankYouOverlay
                }
            }
        }
    }

    // MARK: - Submit

    private func submit() async {
        let success = await feedbackService.submitFeedback(
            category: selectedCategory,
            city: city.trimmingCharacters(in: .whitespacesAndNewlines),
            feedbackText: feedbackText.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedCategories: userPickNames
        )
        if success {
            // Remember the city for next time
            if !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lastCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            showThankYou = true
            try? await Task.sleep(for: .seconds(2))
            dismiss()
        }
    }

    // MARK: - Thank you overlay

    private var thankYouOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Thank you!")
                .font(.title2)
                .fontWeight(.bold)
            Text("Your feedback helps make Flezcal better.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.3), value: showThankYou)
    }
}
