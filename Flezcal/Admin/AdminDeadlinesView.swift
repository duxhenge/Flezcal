import SwiftUI

struct AdminDeadlinesView: View {
    @ObservedObject var viewModel: AdminViewModel
    @State private var showAddSheet = false

    var body: some View {
        List {
            if viewModel.deadlines.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Text("No deadlines yet")
                            .foregroundStyle(.secondary)
                        Button("Seed Initial Deadlines") {
                            Task { await viewModel.seedInitialDeadlines() }
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            } else {
                // Overdue
                let overdue = viewModel.deadlines.filter { $0.isOverdue }
                if !overdue.isEmpty {
                    Section("Overdue") {
                        ForEach(overdue) { deadline in
                            deadlineRow(deadline)
                        }
                    }
                }

                // Due Soon (within 7 days)
                let dueSoon = viewModel.deadlines.filter { $0.isDueSoon }
                if !dueSoon.isEmpty {
                    Section("Due Soon") {
                        ForEach(dueSoon) { deadline in
                            deadlineRow(deadline)
                        }
                    }
                }

                // Upcoming
                let upcoming = viewModel.deadlines.filter { !$0.isOverdue && !$0.isDueSoon }
                if !upcoming.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcoming) { deadline in
                            deadlineRow(deadline)
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
            AddDeadlineSheet(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func deadlineRow(_ deadline: AdminDeadline) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(statusColor(deadline))
                    .frame(width: 8, height: 8)

                Text(deadline.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if deadline.isRecurring {
                    Image(systemName: "repeat")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            HStack {
                Label(deadline.category.rawValue, systemImage: categoryIcon(deadline.category))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(deadline.dueDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(deadline.isOverdue ? .red : .secondary)
            }

            if !deadline.notes.isEmpty {
                Text(deadline.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await viewModel.deleteDeadline(deadline) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func statusColor(_ deadline: AdminDeadline) -> Color {
        if deadline.isOverdue { return .red }
        if deadline.isDueSoon { return .yellow }
        return .green
    }

    private func categoryIcon(_ category: AdminDeadline.DeadlineCategory) -> String {
        switch category {
        case .legal: return "building.columns"
        case .financial: return "dollarsign.circle"
        case .development: return "hammer"
        case .marketing: return "megaphone"
        }
    }
}

// MARK: - Add Deadline Sheet

struct AddDeadlineSheet: View {
    @ObservedObject var viewModel: AdminViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var dueDate = Date()
    @State private var category: AdminDeadline.DeadlineCategory = .financial
    @State private var isRecurring = false
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)

                DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)

                Picker("Category", selection: $category) {
                    ForEach(AdminDeadline.DeadlineCategory.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(c)
                    }
                }

                Toggle("Recurring", isOn: $isRecurring)

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            .navigationTitle("Add Deadline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let entry = AdminDeadline(
                            title: title,
                            dueDate: dueDate,
                            category: category,
                            isRecurring: isRecurring,
                            notes: notes
                        )
                        Task {
                            await viewModel.addDeadline(entry)
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
