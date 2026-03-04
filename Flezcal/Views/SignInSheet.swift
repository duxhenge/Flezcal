import SwiftUI
import AuthenticationServices

/// Compact sign-in sheet presented inline when an unsigned user tries to perform
/// a write action (add spot, vote, rate, upload photo, etc.).
///
/// After successful sign-in the sheet auto-dismisses and the parent view can
/// proceed via an `onChange(of: authService.isSignedIn)` observer.
struct SignInSheet: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var showEmailAuth = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "person.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)

                Text("Sign in to Continue")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Create an account to add spots, rate your favorites, and help the community.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                SignInWithAppleButton(.signIn) { request in
                    authService.handleSignInWithAppleRequest(request)
                } onCompletion: { result in
                    authService.handleSignInWithAppleCompletion(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .padding(.horizontal, 40)

                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(.secondary.opacity(0.3))
                    Text("or")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(.secondary.opacity(0.3))
                }
                .padding(.horizontal, 40)

                Button {
                    showEmailAuth = true
                } label: {
                    Label("Continue with Email", systemImage: "envelope")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .padding(.horizontal, 40)

                if let error = authService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Spacer()
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showEmailAuth) {
                EmailAuthView()
            }
            .onChange(of: authService.isSignedIn) { _, signedIn in
                if signedIn {
                    dismiss()
                }
            }
        }
    }
}
