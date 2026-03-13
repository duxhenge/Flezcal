import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class AdminViewModel: ObservableObject {
    // MARK: - Published Data

    @Published var revenueEntries: [AdminRevenueEntry] = []
    @Published var costEntries: [AdminCostEntry] = []
    @Published var deadlines: [AdminDeadline] = []
    @Published var notes: [AdminNote] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - User Metrics (computed from Firestore)

    @Published var totalUsers: Int = 0
    @Published var activeUsers7d: Int = 0
    @Published var activeUsers30d: Int = 0
    @Published var newUsersThisWeek: Int = 0
    @Published var newUsersThisMonth: Int = 0

    private let db = Firestore.firestore()
    private var revenueListener: ListenerRegistration?
    private var costListener: ListenerRegistration?
    private var deadlineListener: ListenerRegistration?
    private var noteListener: ListenerRegistration?

    // MARK: - Firestore Collection Names

    private let revenueCollection = "admin_revenue"
    private let costCollection = "admin_costs"
    private let deadlineCollection = "admin_reminders"
    private let noteCollection = "admin_notes"

    // MARK: - Lifecycle

    func startListening() {
        listenToRevenue()
        listenToCosts()
        listenToDeadlines()
        listenToNotes()
    }

    func stopListening() {
        revenueListener?.remove()
        costListener?.remove()
        deadlineListener?.remove()
        noteListener?.remove()
    }

    // MARK: - Snapshot Listeners

    private func listenToRevenue() {
        revenueListener = db.collection(revenueCollection)
            .order(by: "date", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    Task { @MainActor in self.errorMessage = error.localizedDescription }
                    return
                }
                guard let docs = snapshot?.documents else { return }
                let entries = docs.compactMap { try? $0.data(as: AdminRevenueEntry.self) }
                Task { @MainActor in self.revenueEntries = entries }
            }
    }

    private func listenToCosts() {
        costListener = db.collection(costCollection)
            .order(by: "date", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    Task { @MainActor in self.errorMessage = error.localizedDescription }
                    return
                }
                guard let docs = snapshot?.documents else { return }
                let entries = docs.compactMap { try? $0.data(as: AdminCostEntry.self) }
                Task { @MainActor in self.costEntries = entries }
            }
    }

    private func listenToDeadlines() {
        deadlineListener = db.collection(deadlineCollection)
            .order(by: "dueDate", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    Task { @MainActor in self.errorMessage = error.localizedDescription }
                    return
                }
                guard let docs = snapshot?.documents else { return }
                let entries = docs.compactMap { try? $0.data(as: AdminDeadline.self) }
                Task { @MainActor in self.deadlines = entries }
            }
    }

    private func listenToNotes() {
        noteListener = db.collection(noteCollection)
            .order(by: "date", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    Task { @MainActor in self.errorMessage = error.localizedDescription }
                    return
                }
                guard let docs = snapshot?.documents else { return }
                let entries = docs.compactMap { try? $0.data(as: AdminNote.self) }
                Task { @MainActor in self.notes = entries }
            }
    }

    // MARK: - Revenue CRUD

    func addRevenue(_ entry: AdminRevenueEntry) async {
        do {
            try db.collection(revenueCollection).document(entry.id).setData(from: entry)
        } catch {
            errorMessage = "Failed to add revenue: \(error.localizedDescription)"
        }
    }

    func deleteRevenue(_ entry: AdminRevenueEntry) async {
        do {
            try await db.collection(revenueCollection).document(entry.id).delete()
        } catch {
            errorMessage = "Failed to delete revenue: \(error.localizedDescription)"
        }
    }

    // MARK: - Cost CRUD

    func addCost(_ entry: AdminCostEntry) async {
        do {
            try db.collection(costCollection).document(entry.id).setData(from: entry)
        } catch {
            errorMessage = "Failed to add cost: \(error.localizedDescription)"
        }
    }

    func deleteCost(_ entry: AdminCostEntry) async {
        do {
            try await db.collection(costCollection).document(entry.id).delete()
        } catch {
            errorMessage = "Failed to delete cost: \(error.localizedDescription)"
        }
    }

    // MARK: - Deadline CRUD

    func addDeadline(_ entry: AdminDeadline) async {
        do {
            try db.collection(deadlineCollection).document(entry.id).setData(from: entry)
        } catch {
            errorMessage = "Failed to add deadline: \(error.localizedDescription)"
        }
    }

    func deleteDeadline(_ entry: AdminDeadline) async {
        do {
            try await db.collection(deadlineCollection).document(entry.id).delete()
        } catch {
            errorMessage = "Failed to delete deadline: \(error.localizedDescription)"
        }
    }

    func updateDeadline(_ entry: AdminDeadline) async {
        do {
            try db.collection(deadlineCollection).document(entry.id).setData(from: entry)
        } catch {
            errorMessage = "Failed to update deadline: \(error.localizedDescription)"
        }
    }

    // MARK: - Note CRUD

    func addNote(_ entry: AdminNote) async {
        do {
            try db.collection(noteCollection).document(entry.id).setData(from: entry)
        } catch {
            errorMessage = "Failed to add note: \(error.localizedDescription)"
        }
    }

    func deleteNote(_ entry: AdminNote) async {
        do {
            try await db.collection(noteCollection).document(entry.id).delete()
        } catch {
            errorMessage = "Failed to delete note: \(error.localizedDescription)"
        }
    }

    // MARK: - Seed Initial Deadlines

    func seedInitialDeadlines() async {
        guard deadlines.isEmpty else { return }

        let now = Date()
        let cal = Calendar.current

        let seeds: [AdminDeadline] = [
            AdminDeadline(
                title: "Apple Developer Renewal",
                dueDate: cal.date(byAdding: .year, value: 1, to: now) ?? now,
                category: .financial,
                isRecurring: true,
                notes: "Annual Apple Developer Program renewal ($99/year)"
            ),
            AdminDeadline(
                title: "Domain Renewal",
                dueDate: cal.date(byAdding: .year, value: 1, to: now) ?? now,
                category: .financial,
                isRecurring: true,
                notes: "flezcal.app domain renewal"
            ),
            AdminDeadline(
                title: "ZenBusiness Compliance Renewal",
                dueDate: cal.date(byAdding: .year, value: 1, to: now) ?? now,
                category: .legal,
                isRecurring: true,
                notes: "Annual ZenBusiness compliance/registered agent renewal"
            ),
            AdminDeadline(
                title: "Massachusetts LLC Annual Report",
                dueDate: cal.date(byAdding: .year, value: 1, to: now) ?? now,
                category: .legal,
                isRecurring: true,
                notes: "File annual report with MA Secretary of the Commonwealth"
            ),
            AdminDeadline(
                title: "Quarterly Business Review",
                dueDate: cal.date(byAdding: .month, value: 3, to: now) ?? now,
                category: .financial,
                isRecurring: true,
                notes: "Review revenue, costs, user growth, and product roadmap"
            ),
        ]

        for seed in seeds {
            await addDeadline(seed)
        }
    }

    // MARK: - Computed Revenue Metrics

    var totalRevenueAllTime: Double {
        revenueEntries.reduce(0) { $0 + $1.amount }
    }

    var totalRevenueThisMonth: Double {
        let cal = Calendar.current
        let now = Date()
        return revenueEntries
            .filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    var revenueBySource: [(source: String, total: Double)] {
        var grouped: [String: Double] = [:]
        for entry in revenueEntries {
            grouped[entry.source.rawValue, default: 0] += entry.amount
        }
        return grouped.map { (source: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
    }

    // MARK: - Computed Cost Metrics

    var totalCostsAllTime: Double {
        costEntries.reduce(0) { $0 + $1.amount }
    }

    var totalCostsThisMonth: Double {
        let cal = Calendar.current
        let now = Date()
        return costEntries
            .filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    var costsByCategory: [(category: String, total: Double)] {
        var grouped: [String: Double] = [:]
        for entry in costEntries {
            grouped[entry.category.rawValue, default: 0] += entry.amount
        }
        return grouped.map { (category: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
    }

    var netProfitAllTime: Double {
        totalRevenueAllTime - totalCostsAllTime
    }

    var netProfitThisMonth: Double {
        totalRevenueThisMonth - totalCostsThisMonth
    }

    // MARK: - Monthly Revenue Data (for chart)

    var monthlyRevenue: [(month: String, amount: Double)] {
        monthlyTotals(from: revenueEntries.map { ($0.date, $0.amount) })
    }

    var monthlyCosts: [(month: String, amount: Double)] {
        monthlyTotals(from: costEntries.map { ($0.date, $0.amount) })
    }

    private func monthlyTotals(from entries: [(date: Date, amount: Double)]) -> [(month: String, amount: Double)] {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yy"

        var grouped: [String: Double] = [:]
        var monthOrder: [String: Date] = [:]

        for entry in entries {
            let components = cal.dateComponents([.year, .month], from: entry.date)
            guard let monthStart = cal.date(from: components) else { continue }
            let key = formatter.string(from: monthStart)
            grouped[key, default: 0] += entry.amount
            if monthOrder[key] == nil { monthOrder[key] = monthStart }
        }

        return grouped
            .sorted { (monthOrder[$0.key] ?? .distantPast) < (monthOrder[$1.key] ?? .distantPast) }
            .map { (month: $0.key, amount: $0.value) }
    }

    // MARK: - Spot Metrics (computed from SpotService data)

    func spotMetrics(spots: [Spot]) -> SpotMetrics {
        let cal = Calendar.current
        let now = Date()
        let weekAgo = cal.date(byAdding: .day, value: -7, to: now) ?? now
        let monthAgo = cal.date(byAdding: .month, value: -1, to: now) ?? now

        let total = spots.count
        let newThisWeek = spots.filter { $0.addedDate >= weekAgo }.count
        let newThisMonth = spots.filter { $0.addedDate >= monthAgo }.count
        let pendingVerification = spots.filter { $0.source != nil && !$0.isCommunityVerified }.count

        var byCat: [String: Int] = [:]
        for spot in spots {
            for cat in spot.categories {
                byCat[cat.id, default: 0] += 1
            }
        }

        // Top contributors
        var userSpotCounts: [String: Int] = [:]
        for spot in spots {
            userSpotCounts[spot.addedByUserID, default: 0] += 1
        }
        let topContributors = userSpotCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { TopContributor(userID: $0.key, spotCount: $0.value) }

        // Most popular by review count
        let mostPopular = spots
            .sorted { $0.reviewCount > $1.reviewCount }
            .prefix(5)
            .map { PopularSpot(name: $0.name, reviewCount: $0.reviewCount, avgRating: $0.averageRating) }

        // City breakdown
        var cityCounts: [String: Int] = [:]
        for spot in spots {
            let city = extractCity(from: spot.address)
            cityCounts[city, default: 0] += 1
        }
        let topCities = cityCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { CityCount(city: $0.key, count: $0.value) }

        return SpotMetrics(
            total: total,
            newThisWeek: newThisWeek,
            newThisMonth: newThisMonth,
            pendingVerification: pendingVerification,
            byCategory: byCat,
            topContributors: Array(topContributors),
            mostPopular: Array(mostPopular),
            topCities: Array(topCities)
        )
    }

    private func extractCity(from address: String) -> String {
        let parts = address.components(separatedBy: ",")
        if parts.count >= 2 {
            return parts[parts.count - 2].trimmingCharacters(in: .whitespaces)
        }
        return address
    }

    // MARK: - Health Scorecard

    func healthScore(spotMetrics: SpotMetrics) -> HealthScore {
        let breakEven: HealthStatus = {
            if totalRevenueThisMonth >= totalCostsThisMonth && totalRevenueThisMonth > 0 {
                return .green
            } else if totalRevenueThisMonth > 0 {
                return .yellow
            }
            return .red
        }()

        let revenueGate: RevenueGate = {
            let r = totalRevenueThisMonth
            if r >= 500 { return RevenueGate(current: r, gates: [125, 300, 500], passedGate: 3) }
            if r >= 300 { return RevenueGate(current: r, gates: [125, 300, 500], passedGate: 2) }
            if r >= 125 { return RevenueGate(current: r, gates: [125, 300, 500], passedGate: 1) }
            return RevenueGate(current: r, gates: [125, 300, 500], passedGate: 0)
        }()

        let submissionVelocity = spotMetrics.newThisWeek

        return HealthScore(
            breakEven: breakEven,
            activeUserMilestones: [200, 500, 1000],
            revenueGate: revenueGate,
            submissionVelocity: submissionVelocity
        )
    }
}

// MARK: - Supporting Types

struct SpotMetrics {
    let total: Int
    let newThisWeek: Int
    let newThisMonth: Int
    let pendingVerification: Int
    let byCategory: [String: Int]
    let topContributors: [TopContributor]
    let mostPopular: [PopularSpot]
    let topCities: [CityCount]
}

struct TopContributor: Identifiable {
    let id = UUID()
    let userID: String
    let spotCount: Int
}

struct PopularSpot: Identifiable {
    let id = UUID()
    let name: String
    let reviewCount: Int
    let avgRating: Double
}

struct CityCount: Identifiable {
    let id = UUID()
    let city: String
    let count: Int
}

struct HealthScore {
    let breakEven: HealthStatus
    let activeUserMilestones: [Int]
    let revenueGate: RevenueGate
    let submissionVelocity: Int
}

struct RevenueGate {
    let current: Double
    let gates: [Double]
    let passedGate: Int
}

enum HealthStatus {
    case green, yellow, red

    var label: String {
        switch self {
        case .green: return "Healthy"
        case .yellow: return "Caution"
        case .red: return "Attention"
        }
    }

    var systemImage: String {
        switch self {
        case .green: return "checkmark.circle.fill"
        case .yellow: return "exclamationmark.triangle.fill"
        case .red: return "xmark.circle.fill"
        }
    }
}
