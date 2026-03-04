import SwiftUI

struct AgeVerificationView: View {
    @AppStorage("hasPassedAgeVerification") private var hasPassedAgeVerification = false
    @State private var denied = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon
            Image("AppIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .accessibilityLabel("Flezcal app icon")

            // App name
            Text("Flezcal")
                .font(.largeTitle.bold())
                .foregroundStyle(.orange)

            if denied {
                // Denial state — no way to proceed
                Text("You must be at least 21 years old to use Flezcal.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                // Verification prompt
                Text("This app includes alcohol-related content.\nAre you 21 or older?")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    // Primary "Yes" button
                    Button {
                        hasPassedAgeVerification = true
                    } label: {
                        Text("Yes, I'm 21+")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityLabel("Confirm I am 21 or older")
                    .accessibilityHint("Grants access to the app")

                    // Secondary "No" button
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            denied = true
                        }
                    } label: {
                        Text("No")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("I am not 21 or older")
                }
                .padding(.horizontal, 40)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .interactiveDismissDisabled()
    }
}

#Preview {
    AgeVerificationView()
}
