import SwiftUI
import Charts

struct AdminOverviewView: View {
    @ObservedObject var viewModel: AdminViewModel
    @EnvironmentObject var spotService: SpotService

    var body: some View {
        let metrics = viewModel.spotMetrics(spots: spotService.spots)
        let health = viewModel.healthScore(spotMetrics: metrics)

        ScrollView {
            VStack(spacing: 20) {
                // Health Scorecard
                healthScorecardSection(health: health, metrics: metrics)

                // Financial Snapshot
                financialSnapshotSection()

                // Spot Metrics
                spotMetricsSection(metrics: metrics)

                // Top Categories
                categoriesSection(metrics: metrics)

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
        }
    }

    // MARK: - Health Scorecard

    @ViewBuilder
    private func healthScorecardSection(health: HealthScore, metrics: SpotMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Business Health", systemImage: "heart.text.square")
                .font(.headline)

            HStack(spacing: 16) {
                healthIndicator(
                    title: "Break-Even",
                    status: health.breakEven
                )

                healthIndicator(
                    title: "Submissions",
                    status: metrics.newThisWeek > 0 ? .green : .yellow
                )
            }

            // Revenue Gates
            VStack(alignment: .leading, spacing: 6) {
                Text("Revenue Milestones")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(Array(health.revenueGate.gates.enumerated()), id: \.offset) { idx, gate in
                    HStack {
                        Image(systemName: health.revenueGate.passedGate > idx
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(health.revenueGate.passedGate > idx ? .green : .secondary)
                        Text("$\(Int(gate))/month")
                            .font(.subheadline)
                        Spacer()
                        if health.revenueGate.passedGate <= idx {
                            let remaining = gate - health.revenueGate.current
                            Text("$\(Int(max(0, remaining))) to go")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func healthIndicator(title: String, status: HealthStatus) -> some View {
        VStack(spacing: 4) {
            Image(systemName: status.systemImage)
                .font(.title2)
                .foregroundStyle(colorForStatus(status))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(status.label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(colorForStatus(status))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
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

    // MARK: - Categories Breakdown

    @ViewBuilder
    private func categoriesSection(metrics: SpotMetrics) -> some View {
        if !metrics.byCategory.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("By Category", systemImage: "square.grid.2x2")
                    .font(.headline)

                let sorted = metrics.byCategory.sorted { $0.value > $1.value }
                ForEach(sorted, id: \.key) { cat, count in
                    HStack {
                        Text(cat)
                            .font(.subheadline)
                        Spacer()
                        Text("\(count)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
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

    private func colorForStatus(_ status: HealthStatus) -> Color {
        switch status {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }
}
