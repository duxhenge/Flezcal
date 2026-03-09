import SwiftUI

/// Admin tab showing custom category rankings, trending terms, and pick counts.
/// Uses CustomCategoryService to fetch data from Firestore.
struct AdminCustomPicksView: View {
    @ObservedObject var viewModel: AdminViewModel
    @StateObject private var customService = CustomCategoryService()

    @State private var trendingTerms: [(term: String, count: Int)] = []
    @State private var trendWindow: TrendWindow = .week
    @State private var rankingFilter: RankingFilter = .allTime
    @State private var filteredRankings: [(category: CustomCategory, pickCount: Int)] = []

    enum TrendWindow: String, CaseIterable {
        case week = "7 Days"
        case month = "30 Days"
        case allTime = "All Time"

        var date: Date {
            let cal = Calendar.current
            switch self {
            case .week: return cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            case .month: return cal.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            case .allTime: return Date.distantPast
            }
        }
    }

    enum RankingFilter: String, CaseIterable {
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
        Group {
            if customService.isLoading {
                ProgressView("Loading custom picks...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if customService.customCategories.isEmpty {
                emptyState
            } else {
                picksList
            }
        }
        .task {
            await customService.fetchAll()
            #if DEBUG
            print("[AdminCustomPicks] fetchAll complete: \(customService.customCategories.count) categories, error: \(customService.errorMessage ?? "none")")
            for cat in customService.customCategories {
                print("[AdminCustomPicks]   \(cat.emoji) \(cat.displayName) — pickCount: \(cat.pickCount)")
            }
            #endif
            await refreshTrending()
        }
        .refreshable {
            await customService.fetchAll()
            await refreshTrending()
        }
    }

    // MARK: - Picks List

    private var picksList: some View {
        ScrollView {
            VStack(spacing: 20) {
                summarySection
                rankingsSection
                trendingSection
            }
            .padding()
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private var summarySection: some View {
        let categories = customService.customCategories
        let totalPicks = categories.reduce(0) { $0 + $1.pickCount }

        VStack(alignment: .leading, spacing: 12) {
            Label("Custom Picks Summary", systemImage: "sparkles")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCard(title: "Unique Terms", value: "\(categories.count)", color: .purple)
                metricCard(title: "Total Picks", value: "\(totalPicks)", color: .blue)
                metricCard(title: "Promotion Ready", value: "\(promotionCandidates.count)", color: .green)
                metricCard(title: "Single-User", value: "\(singleUserTerms.count)", color: .secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Rankings

    @ViewBuilder
    private var rankingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Rankings by Pick Count", systemImage: "list.number")
                .font(.headline)

            Picker("Time", selection: $rankingFilter) {
                ForEach(RankingFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: rankingFilter) { _, newValue in
                Task { await refreshRankings(filter: newValue) }
            }

            let ranked: [(category: CustomCategory, pickCount: Int)] = {
                if rankingFilter == .allTime {
                    return customService.topCandidates(limit: 20).map { (category: $0, pickCount: $0.pickCount) }
                } else {
                    return Array(filteredRankings.prefix(20))
                }
            }()

            if ranked.isEmpty {
                Text("No custom picks for this time period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(ranked.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 10) {
                        Text("#\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .trailing)

                        Text(item.category.emoji)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.category.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(item.category.websiteKeywords.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: "person.2")
                                .font(.caption)
                                .foregroundStyle(.purple)
                            Text("\(item.pickCount)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }

                        if item.pickCount >= 5 {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)

                    if index < ranked.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Trending

    @ViewBuilder
    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Trending", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
                Picker("Window", selection: $trendWindow) {
                    ForEach(TrendWindow.allCases, id: \.self) { window in
                        Text(window.rawValue).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
            .onChange(of: trendWindow) {
                Task { await refreshTrending() }
            }

            if trendingTerms.isEmpty {
                Text("No search events in this window.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(trendingTerms.enumerated()), id: \.offset) { index, item in
                    HStack {
                        Text(item.term)
                            .font(.subheadline)
                        Spacer()
                        Text("\(item.count) \(item.count == 1 ? "search" : "searches")")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        trendBar(count: item.count, maxCount: trendingTerms.first?.count ?? 1)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 50))
                .foregroundStyle(.purple)

            Text("No Custom Picks Yet")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Custom categories created by users will appear here ranked by popularity.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func metricCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func trendBar(count: Int, maxCount: Int) -> some View {
        let fraction = maxCount > 0 ? CGFloat(count) / CGFloat(maxCount) : 0
        let barWidth = Swift.max(1, 60 * fraction)
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.purple.opacity(0.4))
            .frame(width: barWidth, height: 14)
    }

    /// Categories with 5+ picks — candidates for promotion to hardcoded.
    private var promotionCandidates: [CustomCategory] {
        customService.customCategories.filter { $0.pickCount >= 5 }
    }

    /// Categories with only 1 picker.
    private var singleUserTerms: [CustomCategory] {
        customService.customCategories.filter { $0.pickCount <= 1 }
    }

    private func refreshTrending() async {
        trendingTerms = await customService.trendingTerms(since: trendWindow.date, limit: 15)
    }

    private func refreshRankings(filter: RankingFilter) async {
        if let since = filter.since {
            filteredRankings = await customService.fetchPickCounts(since: since)
        } else {
            filteredRankings = []
        }
    }
}
