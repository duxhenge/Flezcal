import Foundation
import SwiftUI

// MARK: - Verification Vote

/// A single user's verification vote (and optional rating) for a specific category at a specific spot.
/// Stored in the flat `verifications` Firestore collection, filtered by `spotID`.
///
/// This is the single source of truth for both verification and ratings:
/// - `vote == true` (thumbs up) = "I've been there, they serve this Flezcal"
/// - `vote == false` (thumbs down) = "I've been there, they do NOT serve this Flezcal"
/// - `rating` (1-5, optional) = quality score, only valid when `vote == true`
/// - A rating implies a thumbs-up (verification) — one vote either way, not double-counted
struct Verification: Identifiable, Codable {
    /// Current schema version. Increment when changing the Firestore document shape.
    /// Existing docs without this field are implicitly version 0 (pre-versioning).
    static let currentSchemaVersion = 1

    var schemaVersion: Int = Self.currentSchemaVersion
    var id: String = UUID().uuidString
    let spotID: String
    let userID: String
    let category: String       // SpotCategory.rawValue (e.g. "mezcal", "flan")
    var vote: Bool             // true = confirms (thumbs up), false = denies (thumbs down)
    var rating: Int?           // 1-5 flan rating, only meaningful when vote == true
    let date: Date             // when first voted
    var updatedDate: Date?     // set when user changes their vote or rating
    var isOriginalVerifier: Bool = false  // true for the first user to verify this category on this spot

    // Custom decoder to handle missing schemaVersion on pre-versioning documents.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        spotID = try container.decode(String.self, forKey: .spotID)
        userID = try container.decode(String.self, forKey: .userID)
        category = try container.decode(String.self, forKey: .category)
        vote = try container.decode(Bool.self, forKey: .vote)
        rating = try container.decodeIfPresent(Int.self, forKey: .rating)
        date = try container.decode(Date.self, forKey: .date)
        updatedDate = try container.decodeIfPresent(Date.self, forKey: .updatedDate)
        isOriginalVerifier = try container.decodeIfPresent(Bool.self, forKey: .isOriginalVerifier) ?? false
    }

    // Memberwise init for programmatic creation
    init(spotID: String, userID: String, category: String, vote: Bool,
         rating: Int? = nil, date: Date = Date(), updatedDate: Date? = nil,
         isOriginalVerifier: Bool = false) {
        self.spotID = spotID
        self.userID = userID
        self.category = category
        self.vote = vote
        self.rating = rating
        self.date = date
        self.updatedDate = updatedDate
        self.isOriginalVerifier = isOriginalVerifier
    }
}

// MARK: - Verification Status

/// Aggregate verification state for a single category on a spot.
/// Computed from running tallies stored on the Spot document.
///
/// Threshold logic:
/// - 1 user can verify instantly (< 10 total votes, any thumbs-up = confirmed)
/// - Primary misclick protection: confirmation dialog in AddFlezcalFlow
/// - 10+ votes: 70% positive threshold required to stay confirmed
/// - Original verifier's vote does not expire (until user base is large enough)
/// - Other votes expire after 3 months (rolling window — future enhancement)
enum VerificationStatus {
    case confirmed   // 1+ thumbs-up (< 10 votes), or 70%+ positive (10+ votes)
    case unverified  // no votes, or 10+ votes with < 70% positive
    case potential   // website check detected this Flezcal but no user has verified

    var icon: String {
        switch self {
        case .confirmed:  return "checkmark.seal.fill"
        case .unverified: return "questionmark.circle"
        case .potential:  return "globe"
        }
    }

    var color: Color {
        switch self {
        case .confirmed:  return .green
        case .unverified: return .secondary
        case .potential:  return .blue
        }
    }

    var label: String {
        switch self {
        case .confirmed:  return "Verified"
        case .unverified: return "Unverified"
        case .potential:  return "Website Mentions"
        }
    }
}
