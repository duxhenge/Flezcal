import SwiftUI

/// Admin view showing unified Flezcal rankings across built-in and custom categories.
/// Rankings determine which categories appear in the Top 50 vs Trending tier.
/// The admin can view pick counts by time window and recompute rankings.
struct AdminRankingsView: View {
    @StateObject private var customService = CustomCategoryService()
    @StateObject private var rankingService = RankingService()

    @State private var timeFilter: TimeFilter = .year
    @State private var rankedList: [RankedCategory] = []
    @State private var isComputing = false
    @State private var lastError: String?
    @State private var hasLoaded = false

    enum TimeFilter: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
        case allTime = "All"

        var since: Date? {
            let cal = Calendar.current
            switch self {
            case .week: return cal.date(byAdding: .day, value: -7, to: Date())
            case .month: return cal.date(byAdding: .month, value: -1, to: Date())
            case .year: return cal.date(byAdding: .year, value: -1, to: Date())
            case .allTime: return nil
            }
        }
    }

    var body: some View {
        List {
            headerSection
            rankingsSection
        }
        .listStyle(.insetGrouped)
        .task {
            await customService.fetchAll()
            await loadRankings()
        }
        .onChange(of: timeFilter) { _, _ in
            Task { await loadRankings() }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Flezcal Rankings")
                        .font(.headline)
                    Spacer()
                    if let date = rankingService.lastUpdated {
                        Text("Updated \(date, style: .relative) ago")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Time", selection: $timeFilter) {
                    ForEach(TimeFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    recomputeButton
                    Spacer()
                    statsLabel
                }
            }
        }
    }

    @ViewBuilder
    private var recomputeButton: some View {
        Button {
            Task { await recomputeRankings() }
        } label: {
            HStack(spacing: 6) {
                if isComputing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                Text("Recompute")
            }
            .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(isComputing)
    }

    @ViewBuilder
    private var statsLabel: some View {
        let top50Count = rankedList.filter { $0.tier == .top50 }.count
        let trendingCount = rankedList.filter { $0.tier == .trending }.count
        HStack(spacing: 8) {
            Label("\(top50Count)", systemImage: "star.fill")
                .foregroundStyle(.orange)
            Label("\(trendingCount)", systemImage: "arrow.up.right")
                .foregroundStyle(.cyan)
        }
        .font(.caption)
    }

    // MARK: - Rankings list

    @ViewBuilder
    private var rankingsSection: some View {
        if let error = lastError {
            Section {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }

        if rankedList.isEmpty && hasLoaded {
            Section {
                Text("No ranking data. Tap Recompute to generate.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        } else {
            // Top 50
            let top50 = rankedList.filter { $0.tier == .top50 }
            if !top50.isEmpty {
                Section("Top 50 Flezcals") {
                    ForEach(top50) { entry in
                        rankingRow(entry)
                    }
                }
            }

            // Trending
            let trending = rankedList.filter { $0.tier == .trending }
            if !trending.isEmpty {
                Section("Trending Flezcals") {
                    ForEach(trending) { entry in
                        rankingRow(entry)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rankingRow(_ entry: RankedCategory) -> some View {
        HStack(spacing: 10) {
            Text("#\(entry.rank)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(entry.tier == .top50 ? .orange : .cyan)
                .frame(minWidth: 36, alignment: .trailing)
                .fixedSize()

            Text(entry.emoji)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.displayName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if entry.isCustom {
                        Text("Custom")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.cyan.opacity(0.7)))
                    }
                }
            }

            Spacer()

            HStack(spacing: 3) {
                Image(systemName: "person.2")
                    .font(.caption2)
                Text("\(entry.pickCount)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .fixedSize()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Data loading

    private func loadRankings() async {
        lastError = nil

        // Fetch pick counts for the selected time window
        let builtInCounts: [String: Int]
        let customCounts: [String: Int]

        if let since = timeFilter.since {
            // Time-filtered counts
            let builtInResults = await UserPicksService.fetchPickCounts(since: since)
            builtInCounts = Dictionary(
                builtInResults.map { ($0.categoryID, $0.pickCount) },
                uniquingKeysWith: { _, last in last }
            )
            let customResults = await customService.fetchPickCounts(since: since)
            customCounts = Dictionary(
                customResults.map { ($0.category.normalizedName, $0.pickCount) },
                uniquingKeysWith: { _, last in last }
            )
        } else {
            // All-time counts
            let builtInResults = await UserPicksService.fetchPickCounts()
            builtInCounts = Dictionary(
                builtInResults.map { ($0.categoryID, $0.pickCount) },
                uniquingKeysWith: { _, last in last }
            )
            // For custom all-time, use the pickCount stored on the category itself
            customCounts = Dictionary(
                customService.customCategories.map { ($0.normalizedName, $0.pickCount) },
                uniquingKeysWith: { _, last in last }
            )
        }

        // Build display list (same logic as computeAndSaveRankings but read-only)
        var all: [RankedCategory] = []

        for cat in FoodCategory.allCategories {
            let count = builtInCounts[cat.id] ?? 0
            all.append(RankedCategory(
                categoryID: cat.id,
                displayName: cat.displayName,
                emoji: cat.emoji,
                rank: 0,
                pickCount: count,
                tier: .top50,
                isCustom: false
            ))
        }

        for custom in customService.customCategories {
            let count = customCounts[custom.normalizedName] ?? 0
            all.append(RankedCategory(
                categoryID: "custom_\(custom.normalizedName)",
                displayName: custom.displayName,
                emoji: FeatureFlagService.trendingEmojiSnapshot,
                rank: 0,
                pickCount: count,
                tier: .trending,
                isCustom: true
            ))
        }

        all.sort { lhs, rhs in
            if lhs.pickCount != rhs.pickCount { return lhs.pickCount > rhs.pickCount }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        for i in all.indices {
            all[i].rank = i + 1
            all[i].tier = i < 50 ? .top50 : .trending
        }

        rankedList = all
        hasLoaded = true
    }

    private func recomputeRankings() async {
        isComputing = true
        lastError = nil
        defer { isComputing = false }

        // Always recompute from yearly data (the public ranking basis)
        let since = Calendar.current.date(byAdding: .year, value: -1, to: Date())

        let builtInCounts: [String: Int]
        let customCounts: [String: Int]

        if let since {
            let builtInResults = await UserPicksService.fetchPickCounts(since: since)
            builtInCounts = Dictionary(
                builtInResults.map { ($0.categoryID, $0.pickCount) },
                uniquingKeysWith: { _, last in last }
            )
            let customResults = await customService.fetchPickCounts(since: since)
            customCounts = Dictionary(
                customResults.map { ($0.category.normalizedName, $0.pickCount) },
                uniquingKeysWith: { _, last in last }
            )
        } else {
            builtInCounts = [:]
            customCounts = [:]
        }

        do {
            let result = try await rankingService.computeAndSaveRankings(
                builtInCounts: builtInCounts,
                customCounts: customCounts,
                customCategories: customService.customCategories
            )
            rankedList = result
        } catch {
            lastError = "Failed to save rankings: \(error.localizedDescription)"
        }
    }
}
