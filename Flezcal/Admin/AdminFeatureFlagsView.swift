import SwiftUI

/// Admin view for toggling feature flags and editing prompt text.
struct AdminFeatureFlagsView: View {
    @ObservedObject var featureFlags: FeatureFlagService
    @StateObject private var feedbackService = BetaFeedbackService()
    @State private var editingPrompt: String = ""
    @State private var isEditingPrompt = false
    @State private var editingTrendingEmoji: String = ""
    @State private var isEditingTrendingEmoji = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            // MARK: - Beta Feedback toggle
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Beta Feedback")
                            .font(.headline)
                        Text(featureFlags.betaFeedbackEnabled ? "Active" : "Disabled")
                            .font(.caption)
                            .foregroundStyle(featureFlags.betaFeedbackEnabled ? .green : .secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { featureFlags.betaFeedbackEnabled },
                        set: { newValue in
                            Task {
                                do {
                                    try await featureFlags.setBetaFeedbackEnabled(newValue)
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                    ))
                    .labelsHidden()
                }

                // Feedback count
                HStack {
                    Text("Submissions")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(feedbackService.feedbackCount)")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            } header: {
                Text("Beta Feedback")
            } footer: {
                Text("Shows a floating feedback button for all testers. Changes take effect immediately.")
            }

            // MARK: - Prompt text
            Section("Prompt Text") {
                if isEditingPrompt {
                    TextEditor(text: $editingPrompt)
                        .frame(minHeight: 80)
                    HStack {
                        Button("Cancel") {
                            isEditingPrompt = false
                        }
                        Spacer()
                        Button("Save") {
                            Task {
                                do {
                                    try await featureFlags.setBetaFeedbackPromptText(editingPrompt)
                                    isEditingPrompt = false
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                        .fontWeight(.semibold)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(featureFlags.betaFeedbackPromptText)
                            .font(.subheadline)
                        Button("Edit") {
                            editingPrompt = featureFlags.betaFeedbackPromptText
                            isEditingPrompt = true
                        }
                        .font(.caption)
                    }
                }
            }

            // MARK: - Trending Emoji
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trending Flezcal Emoji")
                            .font(.headline)
                        Text("Default icon for all custom/trending categories")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(featureFlags.trendingEmoji)
                        .font(.largeTitle)
                }

                if isEditingTrendingEmoji {
                    HStack {
                        TextField("Emoji", text: $editingTrendingEmoji)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Spacer()
                        Button("Cancel") {
                            isEditingTrendingEmoji = false
                        }
                        Button("Save") {
                            let emoji = editingTrendingEmoji.trimmingCharacters(in: .whitespaces)
                            guard !emoji.isEmpty else { return }
                            Task {
                                do {
                                    try await featureFlags.setTrendingEmoji(emoji)
                                    isEditingTrendingEmoji = false
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                        .fontWeight(.semibold)
                    }
                } else {
                    Button("Change Emoji") {
                        editingTrendingEmoji = featureFlags.trendingEmoji
                        isEditingTrendingEmoji = true
                    }
                    .font(.caption)
                }
            } header: {
                Text("Display")
            } footer: {
                Text("Changes apply to all trending Flezcals across the app in real-time.")
            }

            // MARK: - Error
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Feature Flags")
        .task {
            await feedbackService.fetchCount()
        }
    }
}
