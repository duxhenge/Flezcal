import SwiftUI

struct AdminNotesView: View {
    @ObservedObject var viewModel: AdminViewModel
    @State private var showAddSheet = false
    @State private var expandedNoteID: String?

    var body: some View {
        List {
            if viewModel.notes.isEmpty {
                Section {
                    Text("No notes yet. Tap + to log a decision.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(viewModel.notes) { note in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(note.category.rawValue, systemImage: categoryIcon(note.category))
                                .font(.caption)
                                .foregroundStyle(categoryColor(note.category))

                            Spacer()

                            Text(note.date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(note.title)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(note.content)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(expandedNoteID == note.id ? nil : 3)

                        if note.content.count > 100 {
                            Button {
                                withAnimation {
                                    expandedNoteID = expandedNoteID == note.id ? nil : note.id
                                }
                            } label: {
                                Text(expandedNoteID == note.id ? "Show Less" : "Show More")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await viewModel.deleteNote(note) }
                        } label: {
                            Label("Delete", systemImage: "trash")
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
            AddNoteSheet(viewModel: viewModel)
        }
    }

    private func categoryIcon(_ category: AdminNote.NoteCategory) -> String {
        switch category {
        case .strategy: return "lightbulb"
        case .legal: return "building.columns"
        case .technical: return "wrench.and.screwdriver"
        case .financial: return "dollarsign.circle"
        }
    }

    private func categoryColor(_ category: AdminNote.NoteCategory) -> Color {
        switch category {
        case .strategy: return .purple
        case .legal: return .blue
        case .technical: return .orange
        case .financial: return .green
        }
    }
}

// MARK: - Add Note Sheet

struct AddNoteSheet: View {
    @ObservedObject var viewModel: AdminViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var content = ""
    @State private var category: AdminNote.NoteCategory = .strategy
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)

                DatePicker("Date", selection: $date, displayedComponents: .date)

                Picker("Category", selection: $category) {
                    ForEach(AdminNote.NoteCategory.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(c)
                    }
                }

                Section("Content") {
                    TextEditor(text: $content)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let entry = AdminNote(
                            date: date,
                            title: title,
                            content: content,
                            category: category
                        )
                        Task {
                            await viewModel.addNote(entry)
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }
}
