import Foundation
import UIKit
@preconcurrency import MapKit
import FirebaseFirestore
@preconcurrency import FirebaseStorage

/// Handles all photo operations for spots:
/// - Generating map snapshot thumbnails (auto-photo when a spot is added)
/// - Uploading user-selected photos from camera/library
/// - Saving photo URLs back to Firestore
@MainActor
class PhotoService: ObservableObject {
    @Published var isUploading = false
    @Published var uploadError: String?

    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    // MARK: - Map Snapshot (auto-photo, no API key needed)

    /// Renders a 400×300 map snapshot centred on the given coordinate.
    /// Used automatically when a new spot is added.
    func generateMapSnapshot(coordinate: CLLocationCoordinate2D) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
        )
        options.size = CGSize(width: 400, height: 300)
        options.mapType = .standard
        options.showsBuildings = true

        return await withCheckedContinuation { continuation in
            let snapshotter = MKMapSnapshotter(options: options)
            snapshotter.start { @Sendable snapshot, error in
                guard let snapshot = snapshot, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }

                // Draw a pin marker on the snapshot at the spot coordinate
                let image = UIGraphicsImageRenderer(size: options.size).image { _ in
                    snapshot.image.draw(at: .zero)

                    // Draw orange circle pin
                    let point = snapshot.point(for: coordinate)
                    let pinRect = CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)
                    let pinPath = UIBezierPath(ovalIn: pinRect)
                    UIColor(red: 0.9, green: 0.45, blue: 0.0, alpha: 1.0).setFill()
                    pinPath.fill()
                    UIColor.white.setStroke()
                    pinPath.lineWidth = 2
                    pinPath.stroke()
                }

                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - Upload to Firebase Storage

    /// Uploads a UIImage to Firebase Storage under spots/{spotID}/photo.jpg
    /// Returns the public download URL string, or nil on failure.
    func uploadSpotPhoto(_ image: UIImage, spotID: String, isUserPhoto: Bool = false) async -> String? {
        guard let data = image.jpegData(compressionQuality: 0.75) else { return nil }

        let filename = isUserPhoto ? "user_photo.jpg" : "photo.jpg"
        let ref = storage.reference().child("spots/\(spotID)/\(filename)")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        do {
            _ = try await ref.putDataAsync(data, metadata: metadata)
            let url = try await ref.downloadURL()
            return url.absoluteString
        } catch {
            uploadError = "Photo upload failed: \(error.localizedDescription)"
            CrashReporter.record(error, context: "PhotoService.uploadSpotPhoto")
            return nil
        }
    }

    // MARK: - Save URL to Firestore

    /// Saves the auto-generated photo URL to the spot document
    func savePhotoURL(_ url: String, spotID: String) async {
        do {
            let update: [String: Any] = ["photoURL": url]
            try await db.collection(FirestoreCollections.spots).document(spotID).updateData(update)
        } catch {
            uploadError = "Failed to save photo: \(error.localizedDescription)"
            CrashReporter.record(error, context: "PhotoService.savePhotoURL")
        }
    }

    /// Saves the user-uploaded photo URL to the spot document
    func saveUserPhotoURL(_ url: String, spotID: String) async {
        do {
            let update: [String: Any] = ["userPhotoURL": url]
            try await db.collection(FirestoreCollections.spots).document(spotID).updateData(update)
        } catch {
            uploadError = "Failed to save photo: \(error.localizedDescription)"
            CrashReporter.record(error, context: "PhotoService.saveUserPhotoURL")
        }
    }

    // MARK: - Fetch current URL from Firestore (for optimistic UI refresh)

    func fetchUserPhotoURL(spotID: String) async -> String? {
        guard let doc = try? await db.collection(FirestoreCollections.spots).document(spotID).getDocument(),
              let data = doc.data() else { return nil }
        return data["userPhotoURL"] as? String
    }

    // MARK: - Combined: upload + save

    /// Full flow: upload image, then save URL to Firestore. Shows isUploading state.
    func uploadAndSaveUserPhoto(_ image: UIImage, spotID: String) async {
        isUploading = true
        uploadError = nil
        if let url = await uploadSpotPhoto(image, spotID: spotID, isUserPhoto: true) {
            await saveUserPhotoURL(url, spotID: spotID)
        }
        isUploading = false
    }
}
