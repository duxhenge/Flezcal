import SwiftUI

struct EmailAuthView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var isCreateAccount = false
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    Image(systemName: "envelope.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.orange)
                        .padding(.top, 20)

                    Text(isCreateAccount ? "Create Account" : "Sign In")
                        .font(.title2)
                        .fontWeight(.semibold)

                    // Form fields
                    VStack(spacing: 14) {
                        if isCreateAccount {
                            TextField("Display Name", text: $displayName)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.name)
                                .autocorrectionDisabled()
                        }

                        TextField("Email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(isCreateAccount ? .newPassword : .password)
                    }
                    .padding(.horizontal, 24)

                    // Error message
                    if let error = authService.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // Submit button
                    Button {
                        submit()
                    } label: {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        } else {
                            Text(isCreateAccount ? "Create Account" : "Sign In")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .padding(.horizontal, 24)
                    .disabled(!isFormValid || isLoading)

                    // Toggle between sign in / create account
                    Button {
                        withAnimation {
                            isCreateAccount.toggle()
                            authService.errorMessage = nil
                        }
                    } label: {
                        if isCreateAccount {
                            Text("Already have an account? **Sign In**")
                        } else {
                            Text("Don't have an account? **Create One**")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: authService.isSignedIn) { _, signedIn in
                if signedIn {
                    dismiss()
                }
            }
        }
    }

    private var isFormValid: Bool {
        // Require at least one non-whitespace char before @, a domain, and a TLD.
        // Firebase will catch anything truly malformed; this prevents obvious typos.
        let emailValid = email.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+"#,
                                     options: .regularExpression) != nil
        let passwordValid = password.count >= 6
        let nameValid = !isCreateAccount || !displayName.trimmingCharacters(in: .whitespaces).isEmpty
        return emailValid && passwordValid && nameValid
    }

    private func submit() {
        isLoading = true
        Task {
            if isCreateAccount {
                await authService.createAccount(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password,
                    displayName: displayName.trimmingCharacters(in: .whitespaces)
                )
            } else {
                await authService.signIn(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password
                )
            }
            isLoading = false
        }
    }
}

#Preview {
    EmailAuthView()
        .environmentObject(AuthService())
}
