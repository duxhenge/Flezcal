import Foundation
import CoreLocation

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
    var communityVerified: Bool = false

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // MARK: - Category Helpers

    /// Whether this spot has flan
    var hasFlan: Bool { categories.contains(.flan) }

    /// Whether this spot has mezcal
    var hasMezcal: Bool { categories.contains(.mezcal) }

    /// Offerings for a specific category on this spot
    func offerings(for category: SpotCategory) -> [String] {
        offerings?[category.rawValue] ?? []
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

    /// "Hidden Gem": high average rating but few reviews — a great undiscovered spot
    var isHiddenGem: Bool { averageRating >= 4.5 && reviewCount > 0 && reviewCount <= 3 }

    /// "Recently Verified": added within the last 30 days
    var isRecentlyVerified: Bool {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return addedDate > thirtyDaysAgo
    }

    /// "Perfect Pairing": serves both flan AND mezcal
    var isPerfectPairing: Bool { hasFlan && hasMezcal }

    // MARK: - Backward Compatibility

    /// Supports reading old Firestore documents that have a single "category" field
    /// and old "mezcalOfferings" field (migrated to "offerings" dict).
    enum CodingKeys: String, CodingKey {
        case id, name, address, latitude, longitude, mapItemName
        case categories, category  // "category" for old data
        case addedByUserID, addedDate, averageRating, reviewCount
        case offerings            // new: { "mezcal": [...], "pizza": [...] }
        case mezcalOfferings      // legacy: [String] — auto-migrated on read
        case websiteURL
        case photoURL, userPhotoURL
        case isReported, reportCount, reportedByUserIDs, isHidden
        case source, importDate, communityVerified
    }

    init(id: String = UUID().uuidString,
         name: String, address: String,
         latitude: Double, longitude: Double,
         mapItemName: String, categories: [SpotCategory],
         addedByUserID: String, addedDate: Date,
         averageRating: Double, reviewCount: Int,
         offerings: [String: [String]]? = nil,
         websiteURL: String? = nil,
         photoURL: String? = nil,
         userPhotoURL: String? = nil,
         source: String? = nil,
         importDate: Date? = nil,
         communityVerified: Bool = false) {
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
        self.offerings = offerings
        self.websiteURL = websiteURL
        self.photoURL = photoURL
        self.userPhotoURL = userPhotoURL
        self.source = source
        self.importDate = importDate
        self.communityVerified = communityVerified
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

        addedByUserID = try container.decode(String.self, forKey: .addedByUserID)
        addedDate = try container.decode(Date.self, forKey: .addedDate)
        averageRating = try container.decode(Double.self, forKey: .averageRating)
        reviewCount = try container.decode(Int.self, forKey: .reviewCount)
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
        communityVerified = try container.decodeIfPresent(Bool.self, forKey: .communityVerified) ?? false
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
        try container.encode(communityVerified, forKey: .communityVerified)
    }
}
