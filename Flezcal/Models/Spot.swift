import Foundation
import CoreLocation

/// Per-category rating aggregate stored on the Spot document.
struct CategoryRating: Codable, Hashable {
    var average: Double
    var count: Int
}

struct Spot: Identifiable, Codable, Hashable {
    static func == (lhs: Spot, rhs: Spot) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var id: String = UUID().uuidString
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let mapItemName: String  // Name from Apple Maps for verification
    var categories: [SpotCategory]  // A spot can be both flan and mezcal
    let addedByUserID: String
    let addedDate: Date
    var averageRating: Double
    var reviewCount: Int

    // Per-category rating aggregates. Key: SpotCategory.rawValue
    // e.g. { "mezcal": { average: 4.8, count: 6 }, "flan": { average: 3.2, count: 4 } }
    var categoryRatings: [String: CategoryRating]?

    // Category offerings — brands, styles, varieties contributed by users.
    // Originally mezcal-only ("mezcalOfferings"), now generalised to all categories.
    // Firestore field: "offerings" (new) or "mezcalOfferings" (legacy).
    var offerings: [String: [String]]?

    // Legacy accessor — reads mezcal offerings from the new structure.
    var mezcalOfferings: [String]? {
        get { offerings?["mezcal"] }
        set {
            if offerings == nil { offerings = [:] }
            offerings?["mezcal"] = newValue
        }
    }

    // Website URL — saved at confirm time from MKMapItem.url (optional)
    // Used by SpotDetailView to perform a cache-first website check when adding categories.
    var websiteURL: String?

    // Photos — userPhotoURL takes priority over auto-generated photoURL
    var photoURL: String?       // auto-generated map snapshot
    var userPhotoURL: String?   // user-uploaded photo (takes priority)

    /// Returns the best available photo URL: user upload first, then auto-generated
    var displayPhotoURL: String? { userPhotoURL ?? photoURL }

    // Moderation
    var isReported: Bool = false
    var reportCount: Int = 0
    var reportedByUserIDs: [String] = []
    var isHidden: Bool = false  // Auto-hidden after 3+ reports

    // Import provenance — nil on all user-added spots
    /// e.g. "mezcalistas", "osm", "brave" — nil means added by a real user
    var source: String? = nil
    /// When the import script ran; nil for user-added spots
    var importDate: Date? = nil
    /// Flips to true the first time a real Flezcal user confirms this spot exists
    var isCommunityVerified: Bool = false

    // Per-category attribution — tracks which user added each category.
    // Key: SpotCategory.rawValue, Value: userID who added that category.
    // nil for pre-existing spots (backward compat — falls back to addedByUserID).
    var categoryAddedBy: [String: String]?

    // Community verification tallies — keyed by SpotCategory.rawValue
    // e.g. {"mezcal": 5, "flan": 2}
    var verificationUpCount: [String: Int]?
    var verificationDownCount: [String: Int]?
    var lastVerificationDate: Date?
    var verificationUserCount: Int = 0  // distinct users who have voted

    // Categories detected by website check but not yet verified by a user.
    // When a ghost pin is confirmed, categories from the website scan are stored here.
    // Once a user verifies a category (thumbs up), it moves from "potential" to "verified".
    var websiteDetectedCategories: [String]?

    // Custom category tags — normalized names of user-created categories associated
    // with this spot (e.g. ["empanadas", "pupusas"]). Stored for data capture and
    // future promotion to hardcoded categories. No ratings/verifications/offerings.
    var customCategoryTags: [String]?

    // Closure reporting
    var closureReportCount: Int = 0
    var locationStatus: String?  // nil = open, "closed" = confirmed closed by admin

    // Owner Verified — manually set by admin; owner fields editable by ownerUserId
    var isOwnerVerified: Bool = false
    var ownerUserId: String?
    var ownerBrands: [String]?        // Brands/products the owner wants to highlight
    var ownerDetails: String?         // Free-text from the owner (hours, story, etc.)
    var reservationURL: String?       // Link to reservation system
    var ownerLockedCategories: [String]?  // Categories the owner has locked from community edits

    // Silent analytics counters — incremented by AnalyticsService, never shown in v1.0 UI.
    var analyticsViewCount: Int = 0           // All-time spot detail views
    var analyticsReservationClicks: Int = 0   // All-time reservation URL taps
    var geohash4: String?                     // 4-char geohash (~20 km cell) for regional grouping

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // MARK: - Category Helpers

    /// Whether this spot has flan
    var hasFlan: Bool { categories.contains(.flan) }

    /// Whether this spot has mezcal
    var hasMezcal: Bool { categories.contains(.mezcal) }

    /// Whether this spot has handmade tortillas
    var hasTortillas: Bool { categories.contains(.tortillas) }

    /// Offerings for a specific category on this spot
    func offerings(for category: SpotCategory) -> [String] {
        offerings?[category.rawValue] ?? []
    }

    /// Per-category rating for a specific category
    func rating(for category: SpotCategory) -> CategoryRating? {
        categoryRatings?[category.rawValue]
    }

    /// Whether this spot has any offerings listed for any category
    var hasAnyOfferings: Bool {
        offerings?.values.contains(where: { !$0.isEmpty }) ?? false
    }

    /// Primary category (for icon color when only one is needed)
    var primaryCategory: SpotCategory {
        if categories.contains(.flan) && categories.contains(.mezcal) {
            return .mezcal // Default to mezcal for "both" spots
        }
        return categories.first ?? .flan
    }

    /// Whether this spot matches a filter category
    func matchesFilter(_ filter: SpotCategory?) -> Bool {
        guard let filter = filter else { return true }
        return categories.contains(filter)
    }

    // MARK: - Fun Badges

    /// "Hidden Gem": any category rated 4.5+ with few reviews — a great undiscovered item
    var isHiddenGem: Bool {
        if let ratings = categoryRatings {
            return ratings.values.contains { $0.average >= 4.5 && $0.count > 0 && $0.count <= 3 }
        }
        return averageRating >= 4.5 && reviewCount > 0 && reviewCount <= 3
    }

    /// "Recently Verified": added within the last 30 days
    var isRecentlyVerified: Bool {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return addedDate > thirtyDaysAgo
    }

    /// Whether this spot has been confirmed as permanently closed by admin
    var isClosed: Bool { locationStatus == "closed" }

    /// Verification status for a specific category based on running tallies.
    ///
    /// Threshold logic:
    /// - 0 votes + in websiteDetectedCategories → `.potential` (website mentions only)
    /// - 0 votes otherwise → `.unverified`
    /// - 1+ thumbs-up, total < 10 → `.confirmed` (1 user can verify instantly)
    /// - 10+ votes, 70%+ positive → `.confirmed`
    /// - 10+ votes, < 70% positive → `.unverified`
    func verificationStatus(for category: SpotCategory) -> VerificationStatus {
        let ups = verificationUpCount?[category.rawValue] ?? 0
        let downs = verificationDownCount?[category.rawValue] ?? 0
        let total = ups + downs

        // No votes at all
        guard total > 0 else {
            // Check if website scan detected this category
            if websiteDetectedCategories?.contains(category.rawValue) == true {
                return .potential
            }
            return .unverified
        }

        // Fewer than 10 total votes: 1 thumbs-up = confirmed
        if total < 10 {
            return ups > 0 ? .confirmed : .unverified
        }

        // 10+ votes: apply 70% threshold
        let percentage = Double(ups) / Double(total)
        return percentage >= 0.70 ? .confirmed : .unverified
    }

    /// Whether a specific category is verified (confirmed) on this spot
    func isVerified(for category: SpotCategory) -> Bool {
        verificationStatus(for: category) == .confirmed
    }

    /// Whether any category on this spot has been community-verified via the voting system
    var hasAnyVerificationVotes: Bool {
        let totalUps = verificationUpCount?.values.reduce(0, +) ?? 0
        let totalDowns = verificationDownCount?.values.reduce(0, +) ?? 0
        return (totalUps + totalDowns) > 0
    }

    // MARK: - Backward Compatibility

    /// Supports reading old Firestore documents that have a single "category" field
    /// and old "mezcalOfferings" field (migrated to "offerings" dict).
    enum CodingKeys: String, CodingKey {
        case id, name, address, latitude, longitude, mapItemName
        case categories, category  // "category" for old data
        case addedByUserID, addedDate, averageRating, reviewCount, categoryRatings
        case offerings            // new: { "mezcal": [...], "pizza": [...] }
        case mezcalOfferings      // legacy: [String] — auto-migrated on read
        case websiteURL
        case photoURL, userPhotoURL
        case isReported, reportCount, reportedByUserIDs, isHidden
        case source, importDate, categoryAddedBy
        case isCommunityVerified = "communityVerified"
        case verificationUpCount, verificationDownCount
        case lastVerificationDate, verificationUserCount
        case websiteDetectedCategories
        case customCategoryTags
        case closureReportCount, locationStatus
        case isOwnerVerified = "ownerVerified"
        case ownerUserId, ownerBrands, ownerDetails
        case reservationURL, ownerLockedCategories
        case analyticsViewCount, analyticsReservationClicks, geohash4
    }

    init(id: String = UUID().uuidString,
         name: String, address: String,
         latitude: Double, longitude: Double,
         mapItemName: String, categories: [SpotCategory],
         addedByUserID: String, addedDate: Date,
         averageRating: Double, reviewCount: Int,
         categoryRatings: [String: CategoryRating]? = nil,
         offerings: [String: [String]]? = nil,
         websiteURL: String? = nil,
         photoURL: String? = nil,
         userPhotoURL: String? = nil,
         source: String? = nil,
         importDate: Date? = nil,
         isCommunityVerified: Bool = false,
         categoryAddedBy: [String: String]? = nil,
         verificationUpCount: [String: Int]? = nil,
         verificationDownCount: [String: Int]? = nil,
         lastVerificationDate: Date? = nil,
         verificationUserCount: Int = 0,
         websiteDetectedCategories: [String]? = nil,
         customCategoryTags: [String]? = nil,
         closureReportCount: Int = 0,
         locationStatus: String? = nil,
         isOwnerVerified: Bool = false,
         ownerUserId: String? = nil,
         ownerBrands: [String]? = nil,
         ownerDetails: String? = nil,
         reservationURL: String? = nil,
         ownerLockedCategories: [String]? = nil,
         analyticsViewCount: Int = 0,
         analyticsReservationClicks: Int = 0,
         geohash4: String? = nil) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.mapItemName = mapItemName
        self.categories = categories
        self.addedByUserID = addedByUserID
        self.addedDate = addedDate
        self.averageRating = averageRating
        self.reviewCount = reviewCount
        self.categoryRatings = categoryRatings
        self.offerings = offerings
        self.websiteURL = websiteURL
        self.photoURL = photoURL
        self.userPhotoURL = userPhotoURL
        self.source = source
        self.importDate = importDate
        self.isCommunityVerified = isCommunityVerified
        self.categoryAddedBy = categoryAddedBy
        self.verificationUpCount = verificationUpCount
        self.verificationDownCount = verificationDownCount
        self.lastVerificationDate = lastVerificationDate
        self.verificationUserCount = verificationUserCount
        self.websiteDetectedCategories = websiteDetectedCategories
        self.customCategoryTags = customCategoryTags
        self.closureReportCount = closureReportCount
        self.locationStatus = locationStatus
        self.isOwnerVerified = isOwnerVerified
        self.ownerUserId = ownerUserId
        self.ownerBrands = ownerBrands
        self.ownerDetails = ownerDetails
        self.reservationURL = reservationURL
        self.ownerLockedCategories = ownerLockedCategories
        self.analyticsViewCount = analyticsViewCount
        self.analyticsReservationClicks = analyticsReservationClicks
        self.geohash4 = geohash4
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        mapItemName = try container.decode(String.self, forKey: .mapItemName)

        // Try reading "categories" array first, fall back to old single "category"
        if let cats = try? container.decode([SpotCategory].self, forKey: .categories) {
            categories = cats
        } else if let cat = try? container.decode(SpotCategory.self, forKey: .category) {
            categories = [cat]
        } else {
            categories = [.flan]
        }
        #if DEBUG
        let customCats = categories.filter(\.isCustom)
        if !customCats.isEmpty {
            print("[CustomFlezcal] Decoded spot with custom categories: \(customCats.map(\.rawValue))")
        }
        #endif

        addedByUserID = try container.decode(String.self, forKey: .addedByUserID)
        addedDate = try container.decode(Date.self, forKey: .addedDate)
        averageRating = try container.decode(Double.self, forKey: .averageRating)
        reviewCount = try container.decode(Int.self, forKey: .reviewCount)
        categoryRatings = try container.decodeIfPresent([String: CategoryRating].self, forKey: .categoryRatings)
        // Read new "offerings" dict first, fall back to legacy "mezcalOfferings" array
        if let dict = try? container.decodeIfPresent([String: [String]].self, forKey: .offerings) {
            offerings = dict
        } else if let legacy = try? container.decodeIfPresent([String].self, forKey: .mezcalOfferings), !legacy.isEmpty {
            offerings = ["mezcal": legacy]
        } else {
            offerings = nil
        }
        websiteURL = try container.decodeIfPresent(String.self, forKey: .websiteURL)
        photoURL = try container.decodeIfPresent(String.self, forKey: .photoURL)
        userPhotoURL = try container.decodeIfPresent(String.self, forKey: .userPhotoURL)
        isReported = try container.decodeIfPresent(Bool.self, forKey: .isReported) ?? false
        reportCount = try container.decodeIfPresent(Int.self, forKey: .reportCount) ?? 0
        reportedByUserIDs = try container.decodeIfPresent([String].self, forKey: .reportedByUserIDs) ?? []
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        source = try container.decodeIfPresent(String.self, forKey: .source)
        importDate = try container.decodeIfPresent(Date.self, forKey: .importDate)
        isCommunityVerified = try container.decodeIfPresent(Bool.self, forKey: .isCommunityVerified) ?? false
        categoryAddedBy = try container.decodeIfPresent([String: String].self, forKey: .categoryAddedBy)
        verificationUpCount = try container.decodeIfPresent([String: Int].self, forKey: .verificationUpCount)
        verificationDownCount = try container.decodeIfPresent([String: Int].self, forKey: .verificationDownCount)
        lastVerificationDate = try container.decodeIfPresent(Date.self, forKey: .lastVerificationDate)
        verificationUserCount = try container.decodeIfPresent(Int.self, forKey: .verificationUserCount) ?? 0
        websiteDetectedCategories = try container.decodeIfPresent([String].self, forKey: .websiteDetectedCategories)
        customCategoryTags = try container.decodeIfPresent([String].self, forKey: .customCategoryTags)
        closureReportCount = try container.decodeIfPresent(Int.self, forKey: .closureReportCount) ?? 0
        locationStatus = try container.decodeIfPresent(String.self, forKey: .locationStatus)
        isOwnerVerified = try container.decodeIfPresent(Bool.self, forKey: .isOwnerVerified) ?? false
        ownerUserId = try container.decodeIfPresent(String.self, forKey: .ownerUserId)
        ownerBrands = try container.decodeIfPresent([String].self, forKey: .ownerBrands)
        ownerDetails = try container.decodeIfPresent(String.self, forKey: .ownerDetails)
        reservationURL = try container.decodeIfPresent(String.self, forKey: .reservationURL)
        ownerLockedCategories = try container.decodeIfPresent([String].self, forKey: .ownerLockedCategories)
        analyticsViewCount = try container.decodeIfPresent(Int.self, forKey: .analyticsViewCount) ?? 0
        analyticsReservationClicks = try container.decodeIfPresent(Int.self, forKey: .analyticsReservationClicks) ?? 0
        geohash4 = try container.decodeIfPresent(String.self, forKey: .geohash4)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(address, forKey: .address)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(mapItemName, forKey: .mapItemName)
        try container.encode(categories, forKey: .categories)
        try container.encode(addedByUserID, forKey: .addedByUserID)
        try container.encode(addedDate, forKey: .addedDate)
        try container.encode(averageRating, forKey: .averageRating)
        try container.encode(reviewCount, forKey: .reviewCount)
        try container.encodeIfPresent(categoryRatings, forKey: .categoryRatings)
        try container.encodeIfPresent(offerings, forKey: .offerings)
        // Also write legacy mezcalOfferings for backward compat with older app versions
        try container.encodeIfPresent(offerings?["mezcal"], forKey: .mezcalOfferings)
        try container.encodeIfPresent(websiteURL, forKey: .websiteURL)
        try container.encodeIfPresent(photoURL, forKey: .photoURL)
        try container.encodeIfPresent(userPhotoURL, forKey: .userPhotoURL)
        try container.encode(isReported, forKey: .isReported)
        try container.encode(reportCount, forKey: .reportCount)
        try container.encode(reportedByUserIDs, forKey: .reportedByUserIDs)
        try container.encode(isHidden, forKey: .isHidden)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(importDate, forKey: .importDate)
        try container.encode(isCommunityVerified, forKey: .isCommunityVerified)
        try container.encodeIfPresent(categoryAddedBy, forKey: .categoryAddedBy)
        try container.encodeIfPresent(verificationUpCount, forKey: .verificationUpCount)
        try container.encodeIfPresent(verificationDownCount, forKey: .verificationDownCount)
        try container.encodeIfPresent(lastVerificationDate, forKey: .lastVerificationDate)
        try container.encode(verificationUserCount, forKey: .verificationUserCount)
        try container.encodeIfPresent(websiteDetectedCategories, forKey: .websiteDetectedCategories)
        try container.encodeIfPresent(customCategoryTags, forKey: .customCategoryTags)
        try container.encode(closureReportCount, forKey: .closureReportCount)
        try container.encodeIfPresent(locationStatus, forKey: .locationStatus)
        try container.encode(isOwnerVerified, forKey: .isOwnerVerified)
        try container.encodeIfPresent(ownerUserId, forKey: .ownerUserId)
        try container.encodeIfPresent(ownerBrands, forKey: .ownerBrands)
        try container.encodeIfPresent(ownerDetails, forKey: .ownerDetails)
        try container.encodeIfPresent(reservationURL, forKey: .reservationURL)
        try container.encodeIfPresent(ownerLockedCategories, forKey: .ownerLockedCategories)
        try container.encode(analyticsViewCount, forKey: .analyticsViewCount)
        try container.encode(analyticsReservationClicks, forKey: .analyticsReservationClicks)
        try container.encodeIfPresent(geohash4, forKey: .geohash4)
    }

    // MARK: - Owner Helpers

    /// Whether the given user is the verified owner of this spot
    func isOwner(userID: String?) -> Bool {
        guard let userID, isOwnerVerified, let ownerUserId else { return false }
        return userID == ownerUserId
    }

    /// Whether a category is locked by the owner (community edits blocked)
    func isCategoryLocked(_ category: SpotCategory) -> Bool {
        ownerLockedCategories?.contains(category.rawValue) ?? false
    }

    // MARK: - Category Attribution

    /// Who added a specific category. Falls back to original spot creator for legacy data.
    func categoryAddedByUser(_ category: SpotCategory) -> String? {
        categoryAddedBy?[category.rawValue] ?? addedByUserID
    }

    /// Whether the given user can remove a specific category (they added it).
    func canRemoveCategory(_ category: SpotCategory, userID: String?) -> Bool {
        guard let userID else { return false }
        return categoryAddedByUser(category) == userID
    }
}
