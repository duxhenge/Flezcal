import SwiftUI

/// Floating feedback button overlay. Shown when betaFeedbackEnabled is true.
/// Positioned in the bottom-right corner, above the tab bar.
struct BetaFeedbackButton: View {
    @ObservedObject var featureFlags: FeatureFlagService
    let userPickNames: [String]

    @State private var showFeedbackForm = false

    var body: some View {
        // Only show when feature flag is enabled
        if featureFlags.betaFeedbackEnabled {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        showFeedbackForm = true
                    } label: {
                        VStack(spacing: 4) {
                            Text("Beta Feedback")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(.orange.gradient)
                                        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                                )

                            Image(systemName: "text.bubble.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(
                                    Circle()
                                        .fill(.orange.gradient)
                                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                                )
                        }
                    }
                    .accessibilityLabel("Send feedback")
                    .accessibilityHint("Opens the beta feedback form")
                    .padding(.trailing, 16)
                    // Sit above the tab bar
                    .padding(.bottom, 90)
                }
            }
            .transition(.scale.combined(with: .opacity))
            .animation(.easeInOut(duration: 0.25), value: featureFlags.betaFeedbackEnabled)
            .sheet(isPresented: $showFeedbackForm) {
                BetaFeedbackFormView(
                    featureFlags: featureFlags,
                    userPickNames: userPickNames
                )
                .presentationDetents([.large])
            }
        }
    }
}
