import SwiftUI

/// Admin tab for managing categories on spots.
/// Two modes: **Batch** (remove/merge a category across all spots) and
/// **Per-Spot** (surgically remove a category from one spot).
///
/// Uses `SpotService.adminRemoveCategory()` which cleans up all per-category
/// data: categoryRatings, verificationUpCount/Down, offerings, websiteDetectedCategories,
/// and recalculates averageRating.
struct AdminCategoriesView: View {
    @EnvironmentObject var spotService: SpotService

    // MARK: - Mode

    enum Mode: String, CaseIterable {
        case batch = "Batch"
        case perSpot = "Per-Spot"
    }

    @State private var mode: Mode = .batch

    // MARK: - Batch State

    @State private var selectedCategory: SpotCategory?
    @State private var replacementCategory: SpotCategory?
    @State private var showRemoveAlert = false
    @State private var showMergeAlert = false
    @State private var showMergePicker = false
    @State private var batchInProgress = false
    @State private var batchProgress = 0
    @State private var batchTotal = 0
    @State private var showBatchResult = false
    @State private var batchSucceeded = 0
    @State private var batchFailed = 0
    @State private var batchFailedSpotName: String?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch mode {
            case .batch:
                batchView
            case .perSpot:
                perSpotView
            }
        }
        // Batch remove confirmation
        .alert("Remove Category", isPresented: $showRemoveAlert) {
            Button("Remove from \(affectedCount) Spots", role: .destructive) {
                if let cat = selectedCategory {
                    Task { await batchRemove(cat, replaceWith: nil) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let cat = selectedCategory {
                let skipped = singleCategoryCount(for: cat)
                Text("Remove \(cat.displayName) from \(affectedCount) spots?\n\(skipped) single-category spot\(skipped == 1 ? "" : "s") will be skipped.")
            }
        }
        // Merge confirmation
        .alert("Merge Category", isPresented: $showMergeAlert) {
            Button("Merge \(affectedCount) Spots", role: .destructive) {
                if let source = selectedCategory, let target = replacementCategory {
                    Task { await batchRemove(source, replaceWith: target) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let source = selectedCategory, let target = replacementCategory {
                Text("Replace \(source.displayName) with \(target.displayName) on \(affectedCount) spots?")
            }
        }
        // Batch result
        .alert("Batch Complete", isPresented: $showBatchResult) {
            Button("OK") {}
        } message: {
            if batchFailed == 0 {
                Text("Done! Updated \(batchSucceeded) spot\(batchSucceeded == 1 ? "" : "s").")
            } else {
                Text("Updated \(batchSucceeded), failed at \"\(batchFailedSpotName ?? "unknown")\". \(batchFailed) remaining.")
            }
        }
        // Progress overlay
        .overlay {
            if batchInProgress {
                VStack(spacing: 12) {
                    ProgressView(value: Double(batchProgress), total: max(Double(batchTotal), 1))
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                    Text("\(batchProgress) / \(batchTotal)")
                        .font(.subheadline)
                        .monospacedDigit()
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .disabled(batchInProgress)
    }

    // MARK: - Category Stats

    /// All categories currently in use across visible spots, sorted by count descending.
    private var categoriesInUse: [(category: SpotCategory, count: Int)] {
        var map: [SpotCategory: Int] = [:]
        for spot in visibleSpots {
            for cat in spot.categories {
                map[cat, default: 0] += 1
            }
        }
        return map.map { ($0.key, $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Spots that are not hidden and not closed.
    private var visibleSpots: [Spot] {
        spotService.spots.filter { !$0.isHidden && !$0.isClosed }
    }

    /// Spots that have the selected category AND at least 2 categories (eligible for removal).
    private var affectedCount: Int {
        guard let cat = selectedCategory else { return 0 }
        return visibleSpots.filter { $0.categories.contains(cat) && $0.categories.count > 1 }.count
    }

    /// Spots where the selected category is the ONLY category (will be skipped).
    private func singleCategoryCount(for category: SpotCategory) -> Int {
        visibleSpots.filter { $0.categories.contains(category) && $0.categories.count == 1 }.count
    }

    // MARK: - Batch View

    private var batchView: some View {
        List {
            // Summary
            Section {
                Text("\(categoriesInUse.count) categories across \(visibleSpots.count) spots")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Category list
            Section {
                ForEach(categoriesInUse, id: \.category) { item in
                    Button {
                        selectedCategory = item.category
                    } label: {
                        HStack {
                            Text(item.category.emoji)
                            Text(item.category.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(item.count)")
                                .foregroundStyle(.secondary)
                            if selectedCategory == item.category {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }

            // Selected category detail
            if let cat = selectedCategory {
                let total = categoriesInUse.first(where: { $0.category == cat })?.count ?? 0
                let single = singleCategoryCount(for: cat)
                let removable = affectedCount

                Section("Selected: \(cat.emoji) \(cat.displayName)") {
                    LabeledContent("Total spots", value: "\(total)")
                    LabeledContent("Removable (≥2 categories)", value: "\(removable)")
                    if single > 0 {
                        LabeledContent("Skipped (only category)", value: "\(single)")
                            .foregroundStyle(.orange)
                    }

                    // Actions
                    if removable > 0 {
                        Button(role: .destructive) {
                            showRemoveAlert = true
                        } label: {
                            Label("Remove from All (\(removable))", systemImage: "trash")
                        }

                        Button {
                            showMergePicker = true
                        } label: {
                            Label("Merge Into...", systemImage: "arrow.triangle.merge")
                        }
                    } else {
                        Text("No removable spots (all have only this category)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheet(isPresented: $showMergePicker) {
            mergePicker
        }
    }

    // MARK: - Merge Picker

    private var mergePicker: some View {
        NavigationStack {
            List {
                Section("Replace \(selectedCategory?.displayName ?? "") with:") {
                    ForEach(categoriesInUse.filter { $0.category != selectedCategory }, id: \.category) { item in
                        Button {
                            replacementCategory = item.category
                            showMergePicker = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showMergeAlert = true
                            }
                        } label: {
                            HStack {
                                Text(item.category.emoji)
                                Text(item.category.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(item.count) spots")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Merge Into")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showMergePicker = false }
                }
            }
        }
    }

    // MARK: - Batch Operation

    private func batchRemove(_ category: SpotCategory, replaceWith replacement: SpotCategory?) async {
        let affected = visibleSpots.filter {
            $0.categories.contains(category) && $0.categories.count > 1
        }

        batchInProgress = true
        batchProgress = 0
        batchTotal = affected.count

        var succeeded = 0

        for spot in affected {
            // If merging, add replacement first
            if let replacement, !spot.categories.contains(replacement) {
                let addOK = await spotService.addCategories(
                    spotID: spot.id,
                    newCategories: [replacement],
                    addedBy: AdminAccess.adminUID
                )
                if !addOK {
                    batchSucceeded = succeeded
                    batchFailed = affected.count - succeeded
                    batchFailedSpotName = spot.name
                    batchInProgress = false
                    showBatchResult = true
                    return
                }
            }

            // Remove source category with full cleanup
            let removeOK = await spotService.adminRemoveCategory(
                spotID: spot.id,
                category: category
            )
            if !removeOK {
                batchSucceeded = succeeded
                batchFailed = affected.count - succeeded
                batchFailedSpotName = spot.name
                batchInProgress = false
                showBatchResult = true
                return
            }

            succeeded += 1
            batchProgress = succeeded
        }

        batchSucceeded = succeeded
        batchFailed = 0
        batchFailedSpotName = nil
        batchInProgress = false
        selectedCategory = nil
        showBatchResult = true
    }

    // MARK: - Per-Spot View

    private var perSpotView: some View {
        List {
            Section {
                Text("\(categoriesInUse.count) categories across \(visibleSpots.count) spots")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(categoriesInUse, id: \.category) { item in
                NavigationLink {
                    AdminCategorySpotListView(
                        category: item.category,
                        spotService: spotService
                    )
                } label: {
                    HStack {
                        Text(item.category.emoji)
                        Text(item.category.displayName)
                        Spacer()
                        Text("\(item.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Per-Spot Drill-Down

/// Lists all spots with a given category. Admin can remove the category from
/// individual spots (bypassing the normal "you must have added it" restriction).
private struct AdminCategorySpotListView: View {
    let category: SpotCategory
    let spotService: SpotService

    @State private var showRemoveAlert = false
    @State private var spotToRemoveFrom: Spot?

    private var spotsWithCategory: [Spot] {
        spotService.spots
            .filter { $0.categories.contains(category) && !$0.isHidden && !$0.isClosed }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                Text("\(spotsWithCategory.count) spot\(spotsWithCategory.count == 1 ? "" : "s") with \(category.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(spotsWithCategory, id: \.id) { spot in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(spot.name)
                            .font(.body)
                        Text(cityName(from: spot.address))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // All categories as emoji row — target highlighted
                        HStack(spacing: 4) {
                            ForEach(spot.categories, id: \.rawValue) { cat in
                                Text(cat.emoji)
                                    .font(.caption)
                                    .padding(2)
                                    .background(
                                        cat == category
                                            ? Color.red.opacity(0.2)
                                            : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 4)
                                    )
                            }
                        }
                    }

                    Spacer()

                    if spot.categories.count > 1 {
                        Button(role: .destructive) {
                            spotToRemoveFrom = spot
                            showRemoveAlert = true
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("\(category.emoji) \(category.displayName)")
        .alert("Remove Category", isPresented: $showRemoveAlert) {
            Button("Remove", role: .destructive) {
                if let spot = spotToRemoveFrom {
                    Task {
                        _ = await spotService.adminRemoveCategory(
                            spotID: spot.id,
                            category: category
                        )
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \(category.displayName) from \"\(spotToRemoveFrom?.name ?? "")\"?\n\nThis also cleans up ratings, verification tallies, and offerings for this category.")
        }
    }
}
