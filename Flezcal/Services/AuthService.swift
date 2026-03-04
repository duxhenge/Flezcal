import Foundation
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import CryptoKit

@MainActor
class AuthService: ObservableObject {
    @Published var user: User?
    @Published var isSignedIn = false
    @Published var isLoading = true
    @Published var errorMessage: String?
    /// Set to true when the signed-in user has no display name. ContentView
    /// observes this to present a one-time "What should we call you?" alert.
    @Published var needsDisplayNamePrompt = false

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
                // Sync display name to Firestore on every app launch for signed-in users.
                // This auto-migrates existing users who already have a Firebase Auth name.
                if user != nil {
                    await self?.syncDisplayNameToFirestore()
                }
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
                    await self.syncDisplayNameToFirestore()
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
            await syncDisplayNameToFirestore()
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
            await syncDisplayNameToFirestore()
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

    // MARK: - Delete Account

    /// Deletes all user data from Firestore then removes the Firebase Auth account.
    /// Throws `AuthErrorCode.requiresRecentLogin` if the session is stale.
    func deleteAccount() async throws {
        guard let uid = user?.uid else {
            throw NSError(domain: "AuthService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No user signed in."])
        }

        let db = Firestore.firestore()

        // Delete user's reviews
        let reviews = try await db.collection(FirestoreCollections.reviews)
            .whereField("userID", isEqualTo: uid).getDocuments()
        for doc in reviews.documents { try await doc.reference.delete() }

        // Delete user's verifications
        let verifications = try await db.collection(FirestoreCollections.verifications)
            .whereField("userID", isEqualTo: uid).getDocuments()
        for doc in verifications.documents { try await doc.reference.delete() }

        // Delete user's closure reports
        let closureReports = try await db.collection(FirestoreCollections.closureReports)
            .whereField("reporterUserID", isEqualTo: uid).getDocuments()
        for doc in closureReports.documents { try await doc.reference.delete() }

        // Delete spots added by user
        let spots = try await db.collection(FirestoreCollections.spots)
            .whereField("addedByUserID", isEqualTo: uid).getDocuments()
        for doc in spots.documents { try await doc.reference.delete() }

        // Remove user's UID from reportedByUserIDs arrays on spots they reported
        let reportedSpots = try await db.collection(FirestoreCollections.spots)
            .whereField("reportedByUserIDs", arrayContains: uid).getDocuments()
        for doc in reportedSpots.documents {
            try await doc.reference.updateData([
                "reportedByUserIDs": FieldValue.arrayRemove([uid])
            ])
        }

        // Delete user's display name profile
        try? await db.collection(FirestoreCollections.users).document(uid).delete()

        // Delete the Firebase Auth account (may throw requiresRecentLogin)
        try await user?.delete()

        user = nil
        isSignedIn = false
        errorMessage = nil
    }

    // MARK: - Display Name Sync

    /// Writes the current user's display name to Firestore so the leaderboard
    /// can resolve it for all users. If the user has no display name, sets
    /// `needsDisplayNamePrompt` to trigger the name-entry alert in ContentView.
    func syncDisplayNameToFirestore() async {
        guard let uid = user?.uid else { return }
        let name = user?.displayName?.trimmingCharacters(in: .whitespaces) ?? ""

        if name.isEmpty {
            needsDisplayNamePrompt = true
            // Still write email so admin can identify unnamed users
            if let email = user?.email, !email.isEmpty {
                let db = Firestore.firestore()
                try? await db.collection(FirestoreCollections.users).document(uid).setData([
                    "email": email,
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
            }
            return
        }

        var data: [String: Any] = [
            "displayName": name,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let email = user?.email, !email.isEmpty {
            data["email"] = email
        }

        let db = Firestore.firestore()
        try? await db.collection(FirestoreCollections.users).document(uid).setData(data, merge: true)
    }

    /// Saves a display name to both Firebase Auth and the Firestore `users` collection.
    /// Called from the name prompt alert and ProfileView's "Change Display Name".
    func saveDisplayNameToFirestore(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let currentUser = user else { return }

        // Save to Firebase Auth
        let changeRequest = currentUser.createProfileChangeRequest()
        changeRequest.displayName = trimmed
        try? await changeRequest.commitChanges()
        try? await currentUser.reload()
        self.user = Auth.auth().currentUser

        // Save to Firestore
        var data: [String: Any] = [
            "displayName": trimmed,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let email = self.user?.email, !email.isEmpty {
            data["email"] = email
        }

        let db = Firestore.firestore()
        try? await db.collection(FirestoreCollections.users).document(currentUser.uid).setData(data, merge: true)

        needsDisplayNamePrompt = false
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
