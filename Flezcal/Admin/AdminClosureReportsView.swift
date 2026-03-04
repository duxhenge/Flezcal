import SwiftUI

/// Admin tab listing pending closure reports for review.
/// Admin can confirm a spot is permanently closed or dismiss reports.
struct AdminClosureReportsView: View {
    @ObservedObject var viewModel: AdminViewModel
    @StateObject private var closureService = ClosureReportService()

    @State private var showConfirmAlert = false
    @State private var showDismissAlert = false
    @State private var selectedSpotID: String?
    @State private var selectedSpotName: String?

    var body: some View {
        Group {
            if closureService.isLoading {
                ProgressView("Loading reports...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groupedReports.isEmpty {
                emptyState
            } else {
                reportsList
            }
        }
        .task {
            await closureService.fetchPendingReports()
        }
        .refreshable {
            await closureService.fetchPendingReports()
        }
        .alert("Confirm Closure", isPresented: $showConfirmAlert) {
            Button("Confirm Closed", role: .destructive) {
                if let spotID = selectedSpotID {
                    Task { await confirmClosure(spotID: spotID) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Mark \"\(selectedSpotName ?? "this spot")\" as permanently closed? It will be hidden from the map and list.")
        }
        .alert("Dismiss Reports", isPresented: $showDismissAlert) {
            Button("Dismiss All", role: .destructive) {
                if let spotID = selectedSpotID {
                    Task { await dismissReports(spotID: spotID) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Dismiss all closure reports for \"\(selectedSpotName ?? "this spot")\"? The report count will be reset.")
        }
    }

    // MARK: - Grouped Reports (by spotID)

    private var groupedReports: [(spotID: String, spotName: String, spotCity: String, reports: [ClosureReport])] {
        var groups: [String: [ClosureReport]] = [:]
        for report in closureService.reports {
            groups[report.spotID, default: []].append(report)
        }

        return groups.map { spotID, reports in
            let first = reports.first!
            return (spotID: spotID, spotName: first.spotName, spotCity: first.spotCity, reports: reports)
        }
        .sorted { $0.reports.count > $1.reports.count } // Most reported first
    }

    // MARK: - Reports List

    private var reportsList: some View {
        List {
            Section {
                Text("\(closureService.reports.count) pending \(closureService.reports.count == 1 ? "report" : "reports") across \(groupedReports.count) \(groupedReports.count == 1 ? "spot" : "spots")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(groupedReports, id: \.spotID) { group in
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        // Spot name and city
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.spotName)
                                    .font(.headline)
                                Text(group.spotCity)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Label("\(group.reports.count)", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)
                        }

                        Divider()

                        // Report details
                        ForEach(group.reports) { report in
                            HStack {
                                Image(systemName: "person.circle")
                                    .foregroundStyle(.secondary)
                                Text("Reported \(report.date, style: .relative) ago")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        // Action buttons
                        HStack(spacing: 12) {
                            // Open in Maps
                            Button {
                                openInMaps(spotName: group.spotName, city: group.spotCity)
                            } label: {
                                Label("Maps", systemImage: "map")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)

                            Spacer()

                            // Dismiss reports
                            Button {
                                selectedSpotID = group.spotID
                                selectedSpotName = group.spotName
                                showDismissAlert = true
                            } label: {
                                Label("Dismiss", systemImage: "xmark.circle")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                            .tint(.secondary)

                            // Confirm closed
                            Button {
                                selectedSpotID = group.spotID
                                selectedSpotName = group.spotName
                                showConfirmAlert = true
                            } label: {
                                Label("Close", systemImage: "lock.fill")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.shield")
                .font(.system(size: 50))
                .foregroundStyle(.green)

            Text("No Pending Reports")
                .font(.title3)
                .fontWeight(.semibold)

            Text("All closure reports have been reviewed.")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Actions

    private func confirmClosure(spotID: String) async {
        let success = await closureService.confirmClosure(spotID: spotID)
        if !success {
            // Error is surfaced via closureService.errorMessage
        }
    }

    private func dismissReports(spotID: String) async {
        let success = await closureService.dismissReports(spotID: spotID)
        if !success {
            // Error is surfaced via closureService.errorMessage
        }
    }

    private func openInMaps(spotName: String, city: String) {
        let query = "\(spotName) \(city)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "maps://?q=\(query)") {
            UIApplication.shared.open(url)
        }
    }
}
