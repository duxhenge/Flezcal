import SwiftUI
import FirebaseFirestore

struct LeaderboardView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var spotService: SpotService
    @StateObject private var reviewService = ReviewService()
    @StateObject private var verificationService = VerificationService()

    @State private var contributors: [ContributorStats] = []
    @State private var myStats: ContributorStats?
    @State private var myRank: Int?
    @State private var isLoading = true
    /// Admin-only: maps user IDs to email addresses for identification.
    @State private var userEmails: [String: String] = [:]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading leaderboard...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if contributors.isEmpty {
                    emptyState
                } else {
                    leaderboardList
                }
            }
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadLeaderboard()
            }
            .refreshable {
                await loadLeaderboard()
            }
        }
    }

    // MARK: - Leaderboard List

    private var leaderboardList: some View {
        List {
            // Current user's rank card (if signed in)
            if let stats = myStats, let rank = myRank {
                Section {
                    MyRankCard(stats: stats, rank: rank)
                }
            }

            // Top contributors
            Section("Top Contributors") {
                let isAdmin = AdminAccess.isAdmin(uid: authService.userID)
                ForEach(Array(contributors.enumerated()), id: \.element.id) { index, stats in
                    ContributorRow(
                        stats: stats,
                        rank: index + 1,
                        email: isAdmin ? userEmails[stats.id] : nil
                    )
                }
            }

            // Scoring info
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How Scoring Works")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    HStack(spacing: 12) {
                        ScoringBadge(label: "Spot", points: "+10") {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.orange)
                        }
                        ScoringBadge(label: "Rating", points: "+5") {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.orange)
                        }
                        ScoringBadge(label: "Find", points: "+3") {
                            Image(systemName: "tag.fill")
                                .foregroundStyle(.orange)
                        }
                        ScoringBadge(label: "Brand", points: "+1") {
                            Image(systemName: "list.bullet")
                                .foregroundStyle(.orange)
                        }
                        ScoringBadge(label: "Confirm", points: "+1") {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "trophy")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("No Contributors Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Be the first to add a flan or mezcal spot and climb the leaderboard!")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No contributors yet. Be the first to add a spot and climb the leaderboard.")
    }

    // MARK: - Load Data

    private func loadLeaderboard() async {
        isLoading = true
        await reviewService.fetchAllReviews()
        await verificationService.fetchAllVerifications()

        // Build display names from multiple sources, with priority:
        // 1. Firestore `users` collection (canonical — all users who have synced)
        // 2. Legacy review `userName` fields (fallback for un-migrated users)
        // 3. Current user's auth display name (always freshest for self)
        var userNames: [String: String] = [:]

        // Priority 1: Firestore users collection
        var emails: [String: String] = [:]
        let usersSnapshot = try? await Firestore.firestore()
            .collection(FirestoreCollections.users)
            .getDocuments()
        if let docs = usersSnapshot?.documents {
            for doc in docs {
                let data = doc.data()
                if let name = data["displayName"] as? String, !name.isEmpty {
                    userNames[doc.documentID] = name
                }
                if let email = data["email"] as? String, !email.isEmpty {
                    emails[doc.documentID] = email
                }
            }
        }
        userEmails = emails

        // Priority 2: Legacy review userName fields (for users who haven't synced yet)
        for review in reviewService.allReviews {
            if userNames[review.userID] == nil {
                userNames[review.userID] = review.userName
            }
        }

        // Priority 3: Current user's auth display name (always freshest for self)
        if let userID = authService.userID {
            userNames[userID] = authService.displayName
        }

        contributors = ContributorStatsBuilder.buildAll(
            spots: spotService.spots,
            reviews: reviewService.allReviews,
            verifications: verificationService.allVerifications,
            userNames: userNames
        )

        #if DEBUG
        // Debug: show all contributor user IDs and their breakdown
        print("[Leaderboard] === DEBUG ===")
        print("[Leaderboard] My userID: \(authService.userID ?? "nil")")
        print("[Leaderboard] isAdmin: \(AdminAccess.isAdmin(uid: authService.userID))")
        print("[Leaderboard] Firestore users docs fetched: \(usersSnapshot?.documents.count ?? 0)")
        print("[Leaderboard] Emails found: \(emails)")
        print("[Leaderboard] Total spots: \(spotService.spots.count), imported: \(spotService.spots.filter { $0.source != nil }.count), user-added: \(spotService.spots.filter { $0.source == nil }.count)")
        print("[Leaderboard] Total ratings: \(reviewService.allReviews.count), verifications: \(verificationService.allVerifications.count)")
        for c in contributors {
            print("[Leaderboard] '\(c.displayName)' id=\(c.id) | spots=\(c.spotsAdded) finds=\(c.categoriesIdentified) brands=\(c.brandsLogged) ratings=\(c.ratingsGiven) verify=\(c.verificationsGiven) → \(c.score)pts")
        }
        let uniqueSpotUIDs = Set(spotService.spots.filter { $0.source == nil }.map { $0.addedByUserID })
        let uniqueRatingUIDs = Set(reviewService.allReviews.map { $0.userID })
        let uniqueVerifyUIDs = Set(verificationService.allVerifications.map { $0.userID })
        print("[Leaderboard] Unique user-added spot UIDs: \(uniqueSpotUIDs)")
        print("[Leaderboard] Unique rating UIDs: \(uniqueRatingUIDs)")
        print("[Leaderboard] Unique verification UIDs: \(uniqueVerifyUIDs)")
        print("[Leaderboard] === END ===")
        #endif

        // Current user stats
        if let userID = authService.userID {
            myStats = ContributorStatsBuilder.buildForUser(
                userID: userID,
                spots: spotService.spots,
                reviews: reviewService.allReviews,
                verifications: verificationService.allVerifications,
                displayName: authService.displayName
            )
            myRank = ContributorStatsBuilder.rankPosition(userID: userID, allStats: contributors)
        }

        isLoading = false
    }
}

// MARK: - My Rank Card

struct MyRankCard: View {
    let stats: ContributorStats
    let rank: Int

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: stats.rankIcon)
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Rank")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("#\(rank) \u{2022} \(stats.rankTitle)")
                        .font(.headline)
                }

                Spacer()

                Text("\(stats.score) pts")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your rank: number \(rank), \(stats.rankTitle), \(stats.score) points")

            Divider()

            // Row 1: Spots + top 2 categories
            HStack(spacing: 0) {
                StatPill(value: "\(stats.spotsAdded)", label: "Spots") {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.secondary)
                }
                ForEach(stats.topCategories(2), id: \.id) { entry in
                    Spacer()
                    if let cat = SpotCategory(rawValue: entry.id) {
                        StatPill(value: "\(entry.count)", label: cat.displayName) {
                            CategoryIcon(category: cat, size: 16)
                        }
                    }
                }
                // Pad with spacers if fewer than 2 top categories
                if stats.topCategories(2).count < 2 {
                    Spacer()
                }
            }

            // Row 2: Finds, Brands, Ratings, Verified
            HStack(spacing: 0) {
                StatPill(value: "\(stats.categoriesIdentified)", label: "Finds") {
                    Image(systemName: "tag")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatPill(value: "\(stats.brandsLogged)", label: "Brands") {
                    Image(systemName: "list.bullet")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatPill(value: "\(stats.ratingsGiven)", label: "Ratings") {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatPill(value: "\(stats.verificationsGiven)", label: "Verified") {
                    Image(systemName: "checkmark.seal")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Stat Pill

struct StatPill<Icon: View>: View {
    let value: String
    let label: String
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        VStack(spacing: 4) {
            icon()
                .font(.caption)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}

// MARK: - Contributor Row

struct ContributorRow: View {
    let stats: ContributorStats
    let rank: Int
    /// Admin-only: email address for identification. Nil for non-admin users.
    var email: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: rank badge, name, points
            HStack(spacing: 10) {
                // Rank badge
                ZStack {
                    Circle()
                        .fill(rankColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Text("\(rank)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(rankColor)
                }

                // Name and title
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(stats.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if stats.isBrandCollector {
                            Text("🫙")
                                .font(.caption)
                                .help("Brand Collector — 10+ mezcal brands logged!")
                                .accessibilityLabel("Brand Collector")
                        }
                    }

                    HStack(spacing: 4) {
                        Image(systemName: stats.rankIcon)
                            .font(.caption2)
                        Text(stats.rankTitle)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)

                    // Admin-only: email address
                    if let email {
                        Text(email)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Text("\(stats.score) pts")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                    .fixedSize()
            }

            // Bottom row: stats chips
            HStack(spacing: 12) {
                Label("\(stats.spotsAdded)", systemImage: "mappin.circle")
                Label("\(stats.categoriesIdentified)", systemImage: "tag")
                Label("\(stats.brandsLogged)", systemImage: "list.bullet")
                Label("\(stats.ratingsGiven)", systemImage: "flame")
                Label("\(stats.verificationsGiven)", systemImage: "checkmark.seal")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 42) // align with name (32 badge + 10 spacing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(stats.spotsAdded) spots, \(stats.categoriesIdentified) finds, \(stats.brandsLogged) brands, \(stats.ratingsGiven) ratings, \(stats.verificationsGiven) verifications")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var rankColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .secondary
        }
    }
}

// MARK: - Scoring Badge

struct ScoringBadge<Icon: View>: View {
    let label: String
    let points: String
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        VStack(spacing: 4) {
            icon()
                .font(.caption)
            Text(points)
                .font(.caption)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(points) points")
    }
}
