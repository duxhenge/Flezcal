import SwiftUI
import Charts

struct AdminCostsView: View {
    @ObservedObject var viewModel: AdminViewModel
    @State private var showAddSheet = false

    var body: some View {
        List {
            // Summary
            Section("Summary") {
                HStack {
                    Text("This Month")
                    Spacer()
                    Text(formatCurrency(viewModel.totalCostsThisMonth))
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                }

                HStack {
                    Text("All Time")
                    Spacer()
                    Text(formatCurrency(viewModel.totalCostsAllTime))
                        .fontWeight(.semibold)
                }

                HStack {
                    Text("Net Profit (Month)")
                    Spacer()
                    Text(formatCurrency(viewModel.netProfitThisMonth))
                        .fontWeight(.semibold)
                        .foregroundStyle(viewModel.netProfitThisMonth >= 0 ? .green : .red)
                }

                HStack {
                    Text("Net Profit (All Time)")
                    Spacer()
                    Text(formatCurrency(viewModel.netProfitAllTime))
                        .fontWeight(.semibold)
                        .foregroundStyle(viewModel.netProfitAllTime >= 0 ? .green : .red)
                }
            }

            // By Category
            if !viewModel.costsByCategory.isEmpty {
                Section("By Category") {
                    ForEach(viewModel.costsByCategory, id: \.category) { item in
                        HStack {
                            Text(item.category)
                            Spacer()
                            Text(formatCurrency(item.total))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Monthly Chart
            if !viewModel.monthlyCosts.isEmpty {
                Section("Monthly Trend") {
                    Chart {
                        ForEach(viewModel.monthlyCosts, id: \.month) { item in
                            BarMark(
                                x: .value("Month", item.month),
                                y: .value("Costs", item.amount)
                            )
                            .foregroundStyle(.red.gradient)
                        }
                    }
                    .frame(height: 160)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            // Entries
            Section("Entries") {
                if viewModel.costEntries.isEmpty {
                    Text("No cost entries yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.costEntries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.category.rawValue)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    if entry.isRecurring {
                                        Label("Recurring", systemImage: "repeat")
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                    }
                                }
                                Spacer()
                                Text(formatCurrency(entry.amount))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.red)
                            }
                            HStack {
                                Text(entry.date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !entry.notes.isEmpty {
                                    Text("- \(entry.notes)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteCost(entry) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddCostSheet(viewModel: viewModel)
        }
    }

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$0"
    }
}

// MARK: - Add Cost Sheet

struct AddCostSheet: View {
    @ObservedObject var viewModel: AdminViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var amountText = ""
    @State private var category: AdminCostEntry.CostCategory = .other
    @State private var notes = ""
    @State private var isRecurring = false

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)

                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)

                Picker("Category", selection: $category) {
                    ForEach(AdminCostEntry.CostCategory.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(c)
                    }
                }

                Toggle("Recurring", isOn: $isRecurring)

                TextField("Notes", text: $notes)
            }
            .navigationTitle("Add Cost")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let amount = Double(amountText), amount > 0 else { return }
                        let entry = AdminCostEntry(
                            date: date,
                            amount: amount,
                            category: category,
                            notes: notes,
                            isRecurring: isRecurring
                        )
                        Task {
                            await viewModel.addCost(entry)
                            dismiss()
                        }
                    }
                    .disabled(Double(amountText) == nil || (Double(amountText) ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
