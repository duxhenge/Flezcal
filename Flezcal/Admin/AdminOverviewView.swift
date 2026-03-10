import SwiftUI
import Charts

/// Time window filter for pick counts.
private enum PickTimeFilter: String, CaseIterable {
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

struct AdminOverviewView: View {
    @ObservedObject var viewModel: AdminViewModel
    @EnvironmentObject var spotService: SpotService
    @StateObject private var customService = CustomCategoryService()
    @State private var categoryPickCounts: [(categoryID: String, displayName: String, pickCount: Int)] = []
    @State private var picksTimeFilter: PickTimeFilter = .allTime
    @State private var customPicksTimeFilter: PickTimeFilter = .allTime
    @State private var filteredCustomPicks: [(category: CustomCategory, pickCount: Int)] = []

    var body: some View {
        let metrics = viewModel.spotMetrics(spots: spotService.spots)

        ScrollView {
            VStack(spacing: 20) {
                // Quick Links — Beta Feedback & Feature Flags
                quickLinksSection()

                // Financial Snapshot
                financialSnapshotSection()

                // Spot Metrics
                spotMetricsSection(metrics: metrics)

                // Spots by Flezcal (confirmed spots per category)
                spotsByCategorySection(metrics: metrics)

                // Flezcal Picks (user selections)
                categoriesSection(metrics: metrics)

                // Custom Picks Ranking
                customPicksSection()

                // Most Popular Spots
                popularSpotsSection(metrics: metrics)

                // Community Health
                communityHealthSection(spots: spotService.spots)

                // Top Cities
                topCitiesSection(metrics: metrics)

                // Revenue Trend Chart
                if !viewModel.monthlyRevenue.isEmpty {
                    revenueTrendSection()
                }
            }
            .padding()
        }
        .refreshable {
            await spotService.fetchSpots()
            await customService.fetchAll()
            categoryPickCounts = await UserPicksService.fetchPickCounts()
        }
        .task {
            await customService.fetchAll()
            categoryPickCounts = await UserPicksService.fetchPickCounts()
        }
    }

    // MARK: - Quick Links

    @ViewBuilder
    private func quickLinksSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Quick Links", systemImage: "link")
                .font(.headline)

            NavigationLink {
                AdminFeedbackListView()
            } label: {
                HStack {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(.orange)
                        .frame(width: 24)
                    Text("Beta Feedback")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            Divider()

            NavigationLink {
                AdminFeatureFlagsView(featureFlags: FeatureFlagService.shared)
            } label: {
                HStack {
                    Image(systemName: "flag")
                        .foregroundStyle(.orange)
                        .frame(width: 24)
                    Text("Feature Flags")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Financial Snapshot

    @ViewBuilder
    private func financialSnapshotSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Financial Snapshot", systemImage: "chart.pie")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCard(title: "Revenue (Month)", value: formatCurrency(viewModel.totalRevenueThisMonth), color: .green)
                metricCard(title: "Costs (Month)", value: formatCurrency(viewModel.totalCostsThisMonth), color: .red)
                metricCard(title: "Net (Month)", value: formatCurrency(viewModel.netProfitThisMonth),
                           color: viewModel.netProfitThisMonth >= 0 ? .green : .red)
                metricCard(title: "Net (All Time)", value: formatCurrency(viewModel.netProfitAllTime),
                           color: viewModel.netProfitAllTime >= 0 ? .green : .red)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Spot Metrics

    @ViewBuilder
    private func spotMetricsSection(metrics: SpotMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Database", systemImage: "mappin.circle")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCard(title: "Total Spots", value: "\(metrics.total)", color: .orange)
                metricCard(title: "New This Week", value: "\(metrics.newThisWeek)", color: .blue)
                metricCard(title: "New This Month", value: "\(metrics.newThisMonth)", color: .blue)
                metricCard(title: "Pending Verify", value: "\(metrics.pendingVerification)", color: .yellow)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Spots by Flezcal Category

    @ViewBuilder
    private func spotsByCategorySection(metrics: SpotMetrics) -> some View {
        let ranked = metrics.byCategory
            .sorted { $0.value > $1.value }

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Spots by Flezcal", systemImage: "mappin.and.ellipse")
                    .font(.headline)
                Spacer()
                Text("confirmed spots")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if ranked.isEmpty {
                Text("No spots in the database yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(ranked.enumerated()), id: \.element.key) { index, item in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)

                        if let cat = FoodCategory.allKnownCategories.first(where: { $0.displayName == item.key }) {
                            FoodCategoryIcon(category: cat, size: 20)
                        }

                        Text(item.key)
                            .font(.subheadline)
                            .lineLimit(1)

                        Spacer()

                        HStack(spacing: 3) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            Text("\(item.value)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Categories by Pick Popularity

    @ViewBuilder
    private func categoriesSection(metrics: SpotMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Flezcal Picks (\(categoryPickCounts.count))", systemImage: "square.grid.2x2")
                    .font(.headline)
                Spacer()
            }

            Picker("Time", selection: $picksTimeFilter) {
                ForEach(PickTimeFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: picksTimeFilter) { _, newValue in
                Task { await refreshPickCounts(filter: newValue) }
            }

            if categoryPickCounts.isEmpty {
                Text("No pick data for this time period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(categoryPickCounts.prefix(20).enumerated()), id: \.element.categoryID) { index, item in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)

                        if let cat = FoodCategory.allCategories.first(where: { $0.id == item.categoryID }) {
                            FoodCategoryIcon(category: cat, size: 20)
                        }

                        Text(item.displayName)
                            .font(.subheadline)
                            .lineLimit(1)

                        Spacer()

                        HStack(spacing: 3) {
                            Image(systemName: "person.2.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text("\(item.pickCount)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Popular Spots

    @ViewBuilder
    private func popularSpotsSection(metrics: SpotMetrics) -> some View {
        if !metrics.mostPopular.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Most Popular", systemImage: "star.circle")
                    .font(.headline)

                ForEach(metrics.mostPopular) { spot in
                    HStack {
                        Text(spot.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "flame")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("\(spot.reviewCount)")
                                .font(.caption)
                        }
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Top Cities

    @ViewBuilder
    private func topCitiesSection(metrics: SpotMetrics) -> some View {
        if !metrics.topCities.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Top Cities", systemImage: "building.2")
                    .font(.headline)

                ForEach(metrics.topCities) { city in
                    HStack {
                        Text(city.city)
                            .font(.subheadline)
                        Spacer()
                        Text("\(city.count) spots")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Revenue Trend Chart

    @ViewBuilder
    private func revenueTrendSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Revenue Trend", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            Chart {
                ForEach(viewModel.monthlyRevenue, id: \.month) { item in
                    BarMark(
                        x: .value("Month", item.month),
                        y: .value("Revenue", item.amount)
                    )
                    .foregroundStyle(.green.gradient)
                }
            }
            .frame(height: 180)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("$\(Int(v))")
                                .font(.caption2)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Community Health

    @ViewBuilder
    private func communityHealthSection(spots: [Spot]) -> some View {
        let pendingClosures = spots.filter { $0.closureReportCount > 0 && !$0.isClosed }.count
        let closedSpots = spots.filter { $0.isClosed }.count
        let spotsWithVerifications = spots.filter { $0.hasAnyVerificationVotes }.count
        let verificationRate = spots.isEmpty ? 0 : Int(Double(spotsWithVerifications) / Double(spots.count) * 100)

        VStack(alignment: .leading, spacing: 12) {
            Label("Community Health", systemImage: "person.3")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCard(title: "Pending Closures", value: "\(pendingClosures)",
                           color: pendingClosures > 0 ? .orange : .green)
                metricCard(title: "Closed Spots", value: "\(closedSpots)", color: .red)
                metricCard(title: "Verified Spots", value: "\(spotsWithVerifications)", color: .green)
                metricCard(title: "Verification Rate", value: "\(verificationRate)%", color: .blue)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Custom Picks Ranking

    @ViewBuilder
    private func customPicksSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Trending Picks (\(customService.customCategories.count))", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
            }

            Picker("Time", selection: $customPicksTimeFilter) {
                ForEach(PickTimeFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: customPicksTimeFilter) { _, newValue in
                Task { await refreshCustomPickCounts(filter: newValue) }
            }

            if customService.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                let ranked: [(category: CustomCategory, pickCount: Int)] = {
                    if customPicksTimeFilter == .allTime {
                        return customService.topCandidates(limit: 20).map { (category: $0, pickCount: $0.pickCount) }
                    } else {
                        return Array(filteredCustomPicks.prefix(20))
                    }
                }()

                if ranked.isEmpty {
                    Text("No trending picks for this time period.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(Array(ranked.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .frame(width: 20, alignment: .trailing)

                            Text(item.category.emoji)

                            Text(item.category.displayName)
                                .font(.subheadline)
                                .lineLimit(1)

                            Spacer()

                            HStack(spacing: 3) {
                                Image(systemName: "person.2.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.cyan)
                                Text("\(item.pickCount)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }

                            if item.pickCount >= 5 {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Data Refresh

    private func refreshPickCounts(filter: PickTimeFilter) async {
        if let since = filter.since {
            categoryPickCounts = await UserPicksService.fetchPickCounts(since: since)
        } else {
            categoryPickCounts = await UserPicksService.fetchPickCounts()
        }
    }

    private func refreshCustomPickCounts(filter: PickTimeFilter) async {
        if let since = filter.since {
            filteredCustomPicks = await customService.fetchPickCounts(since: since)
        } else {
            filteredCustomPicks = []
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

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$0"
    }

}
