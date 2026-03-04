import SwiftUI
import Charts

struct AdminRevenueView: View {
    @ObservedObject var viewModel: AdminViewModel
    @State private var showAddSheet = false

    var body: some View {
        List {
            // Summary
            Section("Summary") {
                HStack {
                    Text("This Month")
                    Spacer()
                    Text(formatCurrency(viewModel.totalRevenueThisMonth))
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }

                HStack {
                    Text("All Time")
                    Spacer()
                    Text(formatCurrency(viewModel.totalRevenueAllTime))
                        .fontWeight(.semibold)
                }
            }

            // By Source
            if !viewModel.revenueBySource.isEmpty {
                Section("By Source") {
                    ForEach(viewModel.revenueBySource, id: \.source) { item in
                        HStack {
                            Text(item.source)
                            Spacer()
                            Text(formatCurrency(item.total))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Monthly Chart
            if !viewModel.monthlyRevenue.isEmpty {
                Section("Monthly Trend") {
                    Chart {
                        ForEach(viewModel.monthlyRevenue, id: \.month) { item in
                            BarMark(
                                x: .value("Month", item.month),
                                y: .value("Revenue", item.amount)
                            )
                            .foregroundStyle(.green.gradient)
                        }
                    }
                    .frame(height: 160)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            // Entries
            Section("Entries") {
                if viewModel.revenueEntries.isEmpty {
                    Text("No revenue entries yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.revenueEntries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.source.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(formatCurrency(entry.amount))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.green)
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
                                Task { await viewModel.deleteRevenue(entry) }
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
            AddRevenueSheet(viewModel: viewModel)
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

// MARK: - Add Revenue Sheet

struct AddRevenueSheet: View {
    @ObservedObject var viewModel: AdminViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var amountText = ""
    @State private var source: AdminRevenueEntry.RevenueSource = .other
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)

                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)

                Picker("Source", selection: $source) {
                    ForEach(AdminRevenueEntry.RevenueSource.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }

                TextField("Notes", text: $notes)
            }
            .navigationTitle("Add Revenue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let amount = Double(amountText), amount > 0 else { return }
                        let entry = AdminRevenueEntry(
                            date: date,
                            amount: amount,
                            source: source,
                            notes: notes
                        )
                        Task {
                            await viewModel.addRevenue(entry)
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
