import SwiftUI

struct LeaderboardView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var spotService: SpotService
    @StateObject private var reviewService = ReviewService()

    @State private var contributors: [ContributorStats] = []
    @State private var myStats: ContributorStats?
    @State private var myRank: Int?
    @State private var isLoading = true

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
                ForEach(Array(contributors.enumerated()), id: \.element.id) { index, stats in
                    ContributorRow(stats: stats, rank: index + 1)
                }
            }

            // Scoring info
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How Scoring Works")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    HStack(spacing: 16) {
                        ScoringBadge(label: "Spot", points: "+10") {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.orange)
                        }
                        ScoringBadge(label: "Rating", points: "+5") {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.orange)
                        }
                        ScoringBadge(label: "Mezcal", points: "+3") {
                            VeladoraIcon(size: 14)
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
    }

    // MARK: - Load Data

    private func loadLeaderboard() async {
        isLoading = true
        await reviewService.fetchAllReviews()

        // Build display names from reviews (reviews store userName).
        // Also inject the current user's auth display name so spot-only contributors show correctly.
        var userNames: [String: String] = [:]
        for review in reviewService.allReviews {
            if userNames[review.userID] == nil {
                userNames[review.userID] = review.userName
            }
        }
        if let userID = authService.userID {
            userNames[userID] = authService.displayName
        }

        contributors = ContributorStatsBuilder.buildAll(
            spots: spotService.spots,
            reviews: reviewService.allReviews,
            userNames: userNames
        )

        // Current user stats
        if let userID = authService.userID {
            myStats = ContributorStatsBuilder.buildForUser(
                userID: userID,
                spots: spotService.spots,
                reviews: reviewService.allReviews,
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

            Divider()

            HStack(spacing: 0) {
                StatPill(value: "\(stats.spotsAdded)", label: "Spots") {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatPill(value: "\(stats.flanSpotsAdded)", label: "Flan") {
                    FlanIcon(size: 14)
                }
                Spacer()
                StatPill(value: "\(stats.mezcalSpotsAdded)", label: "Mezcal") {
                    VeladoraIcon(size: 14)
                }
                Spacer()
                StatPill(value: "\(stats.mezcalBrandsAdded)", label: "Brands") {
                    Image(systemName: "list.bullet")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatPill(value: "\(stats.reviewsWritten)", label: "Ratings") {
                    Image(systemName: "flame.fill")
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
    }
}

// MARK: - Contributor Row

struct ContributorRow: View {
    let stats: ContributorStats
    let rank: Int

    var body: some View {
        HStack(spacing: 12) {
            // Rank badge
            ZStack {
                Circle()
                    .fill(rankColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text("\(rank)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(rankColor)
            }

            // Name and title
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(stats.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if stats.isBrandCollector {
                        Text("🫙")
                            .font(.caption)
                            .help("Brand Collector — 10+ mezcal brands logged!")
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: stats.rankIcon)
                        .font(.caption2)
                    Text(stats.rankTitle)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Stats summary
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(stats.score) pts")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                    .fixedSize()

                HStack(spacing: 6) {
                    Label("\(stats.spotsAdded)", systemImage: "mappin.circle")
                        .fixedSize()
                    HStack(spacing: 1) {
                        VeladoraIcon(size: 10)
                        Text("\(stats.mezcalBrandsAdded)")
                    }
                    .fixedSize()
                    Label("\(stats.reviewsWritten)", systemImage: "flame")
                        .fixedSize()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
    }
}
