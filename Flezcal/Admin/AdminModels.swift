import Foundation

// MARK: - Revenue Entry

struct AdminRevenueEntry: Identifiable, Codable {
    var id: String = UUID().uuidString
    var date: Date
    var amount: Double
    var source: RevenueSource
    var notes: String

    enum RevenueSource: String, Codable, CaseIterable {
        case featuredListing = "Featured Listing"
        case affiliate = "Affiliate"
        case sponsorship = "Sponsorship"
        case premiumSubscription = "Premium Subscription"
        case other = "Other"
    }
}

// MARK: - Cost Entry

struct AdminCostEntry: Identifiable, Codable {
    var id: String = UUID().uuidString
    var date: Date
    var amount: Double
    var category: CostCategory
    var notes: String
    var isRecurring: Bool

    enum CostCategory: String, Codable, CaseIterable {
        case appleDeveloper = "Apple Developer"
        case domain = "Domain"
        case zenBusiness = "ZenBusiness"
        case firebase = "Firebase"
        case insurance = "Insurance"
        case legal = "Legal"
        case marketing = "Marketing"
        case other = "Other"
    }
}

// MARK: - Deadline / Reminder

struct AdminDeadline: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var dueDate: Date
    var category: DeadlineCategory
    var isRecurring: Bool
    var notes: String

    enum DeadlineCategory: String, Codable, CaseIterable {
        case legal = "Legal"
        case financial = "Financial"
        case development = "Development"
        case marketing = "Marketing"
    }

    var isOverdue: Bool {
        dueDate < Date()
    }

    var isDueSoon: Bool {
        let sevenDaysFromNow = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return dueDate <= sevenDaysFromNow && !isOverdue
    }
}

// MARK: - Note / Decision Log

struct AdminNote: Identifiable, Codable {
    var id: String = UUID().uuidString
    var date: Date
    var title: String
    var content: String
    var category: NoteCategory

    enum NoteCategory: String, Codable, CaseIterable {
        case strategy = "Strategy"
        case legal = "Legal"
        case technical = "Technical"
        case financial = "Financial"
    }
}
