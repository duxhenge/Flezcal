import SwiftUI

/// Admin view for toggling feature flags and editing prompt text.
struct AdminFeatureFlagsView: View {
    @ObservedObject var featureFlags: FeatureFlagService
    @StateObject private var feedbackService = BetaFeedbackService()
    @State private var editingPrompt: String = ""
    @State private var isEditingPrompt = false
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
