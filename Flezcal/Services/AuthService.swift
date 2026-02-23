import Foundation
import FirebaseAuth
import AuthenticationServices
import CryptoKit

@MainActor
class AuthService: ObservableObject {
    @Published var user: User?
    @Published var isSignedIn = false
    @Published var isLoading = true
    @Published var errorMessage: String?

    // For Sign in with Apple
    private var currentNonce: String?
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    init() {
        // Listen for auth state changes
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
                self?.isSignedIn = user != nil
                self?.isLoading = false
            }
        }
    }

    deinit {
        // Remove the Firebase auth listener to prevent a retain cycle and
        // avoid callbacks firing after this object has been deallocated.
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Sign in with Apple

    /// Generates a nonce and returns the Sign in with Apple request
    func handleSignInWithAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    /// Processes the Sign in with Apple result
    func handleSignInWithAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Unexpected credential type."
                return
            }

            guard let nonce = currentNonce else {
                errorMessage = "Invalid state: no login request was sent."
                return
            }

            guard let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                errorMessage = "Unable to get identity token."
                return
            }

            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )

            // Capture the name now — Apple only sends it on the first sign-in
            let appleGivenName = appleIDCredential.fullName?.givenName
            let appleFullName: String? = {
                let components = [appleIDCredential.fullName?.givenName,
                                  appleIDCredential.fullName?.familyName]
                let joined = components.compactMap { $0 }.joined(separator: " ")
                return joined.isEmpty ? nil : joined
            }()

            Task {
                do {
                    let result = try await Auth.auth().signIn(with: credential)
                    // Save the display name if Firebase doesn't have one yet
                    if result.user.displayName?.isEmpty != false,
                       let name = appleFullName ?? appleGivenName {
                        let changeRequest = result.user.createProfileChangeRequest()
                        changeRequest.displayName = name
                        try await changeRequest.commitChanges()
                        try await result.user.reload()
                    }
                    self.user = Auth.auth().currentUser
                    self.isSignedIn = true
                    self.errorMessage = nil
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }

        case .failure(let error):
            // Don't show error if user simply cancelled
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Email & Password

    func signIn(email: String, password: String) async {
        errorMessage = nil
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            self.user = result.user
            self.isSignedIn = true
        } catch {
            self.errorMessage = friendlyError(error)
        }
    }

    func createAccount(email: String, password: String, displayName: String) async {
        errorMessage = nil
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)

            // Set display name
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()

            // Refresh local user to pick up the display name
            try await result.user.reload()
            self.user = Auth.auth().currentUser
            self.isSignedIn = true
        } catch {
            self.errorMessage = friendlyError(error)
        }
    }

    /// Converts Firebase auth errors into user-friendly messages
    private func friendlyError(_ error: Error) -> String {
        let code = (error as NSError).code
        switch code {
        case AuthErrorCode.wrongPassword.rawValue:
            return "Incorrect password. Please try again."
        case AuthErrorCode.invalidEmail.rawValue:
            return "Please enter a valid email address."
        case AuthErrorCode.emailAlreadyInUse.rawValue:
            return "An account with this email already exists. Try signing in."
        case AuthErrorCode.weakPassword.rawValue:
            return "Password must be at least 6 characters."
        case AuthErrorCode.userNotFound.rawValue:
            return "No account found with this email. Try creating one."
        case AuthErrorCode.networkError.rawValue:
            return "Network error. Please check your connection."
        default:
            return error.localizedDescription
        }
    }

    // MARK: - Sign Out

    func signOut() {
        do {
            try Auth.auth().signOut()
            user = nil
            isSignedIn = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    var displayName: String {
        user?.displayName ?? "Flan & Mezcal Fan"
    }

    var userID: String? {
        user?.uid
    }

    // MARK: - Nonce Utilities (required for Sign in with Apple)

    private func randomNonceString(length: Int = 32) -> String {
        guard length > 0 else { return "" }
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        guard errorCode == errSecSuccess else {
            // Cryptographic RNG failure — surface as a sign-in error rather than crashing
            errorMessage = "Sign in failed: could not generate secure token. Please try again."
            return ""
        }

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        return String(nonce)
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}
