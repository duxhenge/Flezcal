import SwiftUI

/// Admin view for browsing, filtering, and exporting beta feedback.
struct AdminFeedbackListView: View {
    @StateObject private var feedbackService = BetaFeedbackService()
    @State private var selectedFilter: FeedbackCategory?
    @State private var copiedToClipboard = false

    private var filteredItems: [BetaFeedback] {
        guard let filter = selectedFilter else { return feedbackService.feedbackItems }
        return feedbackService.feedbackItems.filter { $0.category == filter.rawValue }
    }

    var body: some View {
        List {
            // MARK: - Controls
            Section {
                // Filter picker
                HStack {
                    Text("Filter")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Category", selection: $selectedFilter) {
                        Text("All").tag(FeedbackCategory?.none)
                        ForEach(FeedbackCategory.allCases) { cat in
                            Label(cat.displayName, systemImage: cat.iconName).tag(Optional(cat))
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Export button
                Button {
                    let json = feedbackService.exportAsJSON()
                    UIPasteboard.general.string = json
                    copiedToClipboard = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copiedToClipboard = false
                    }
                } label: {
                    HStack {
                        Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.clipboard")
                        Text(copiedToClipboard ? "Copied to clipboard!" : "Export as JSON")
                    }
                }
                .disabled(feedbackService.feedbackItems.isEmpty)

                // Count
                HStack {
                    Text("Showing")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(filteredItems.count) of \(feedbackService.feedbackItems.count)")
                        .monospacedDigit()
                }
            }

            // MARK: - Feedback items
            if filteredItems.isEmpty {
                Section {
                    Text("No feedback yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(filteredItems) { item in
                        NavigationLink {
                            AdminFeedbackDetailView(feedback: item)
                        } label: {
                            feedbackRow(item)
                        }
                    }
                }
            }
        }
        .navigationTitle("Feedback (\(feedbackService.feedbackItems.count))")
        .task {
            await feedbackService.fetchAllFeedback()
        }
        .refreshable {
            await feedbackService.fetchAllFeedback()
        }
    }

    // MARK: - Row

    private func feedbackRow(_ item: BetaFeedback) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Category tag
                Label(item.feedbackCategory.displayName, systemImage: item.feedbackCategory.iconName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(categoryColor(item.feedbackCategory))

                Spacer()

                Text(item.formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !item.city.isEmpty {
                Text(item.city)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(item.feedbackText)
                .font(.subheadline)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private func categoryColor(_ cat: FeedbackCategory) -> Color {
        switch cat {
        case .bug: return .red
        case .suggestion: return .blue
        case .content: return .green
        case .design: return .purple
        case .other: return .secondary
        }
    }
}

// MARK: - Detail View

struct AdminFeedbackDetailView: View {
    let feedback: BetaFeedback

    var body: some View {
        List {
            Section("Feedback") {
                VStack(alignment: .leading, spacing: 8) {
                    Label(feedback.feedbackCategory.displayName, systemImage: feedback.feedbackCategory.iconName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if !feedback.city.isEmpty {
                        Label(feedback.city, systemImage: "mappin")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(feedback.feedbackText)
                        .font(.body)
                        .padding(.top, 4)
                }
            }

            Section("Device Info") {
                detailRow("App Version", feedback.appVersion)
                detailRow("Build", feedback.buildNumber)
                detailRow("Device", feedback.deviceModel)
                detailRow("iOS", feedback.iOSVersion)
            }

            Section("User") {
                detailRow("User ID", feedback.userId)
                detailRow("Submitted", feedback.formattedDate)
            }

            if !feedback.selectedCategories.isEmpty {
                Section("Active Flezcal Picks") {
                    ForEach(feedback.selectedCategories, id: \.self) { pick in
                        Text(pick)
                            .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("Feedback Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .monospaced()
        }
    }
}
