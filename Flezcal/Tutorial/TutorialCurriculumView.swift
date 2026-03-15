import SwiftUI

/// Sheet showing the tutorial curriculum — tutorials grouped by experience level
/// with progress tracking and start/replay buttons.
struct TutorialCurriculumView: View {
    @ObservedObject var tutorialService: TutorialService
    @Environment(\.dismiss) private var dismiss

    private var tutorialGroups: [TutorialGroup] {
        [
            TutorialGroup(
                title: "Getting Started",
                subtitle: "Learn the basics",
                tutorials: [.setupFlezcals, .spotsTab, .mapExplore]
            ),
            TutorialGroup(
                title: "Contributing",
                subtitle: "Share your finds",
                tutorials: [.addSpot, .ratingVerifying]
            ),
            TutorialGroup(
                title: "Growing",
                subtitle: "Track your impact",
                tutorials: [.leaderboard]
            ),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "book.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)

                        Text("Learn \(AppBranding.name)")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Quick tutorials to help you get the most out of the app.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .padding(.top, 8)

                    // Progress summary
                    let completedCount = Tutorial.allTutorials.filter {
                        tutorialService.isCompleted($0.id)
                    }.count
                    if completedCount > 0 {
                        Text("\(completedCount) of \(Tutorial.allTutorials.count) completed")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                    }

                    // Grouped tutorial cards
                    ForEach(tutorialGroups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            // Section header
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.title)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                Text(group.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 4)

                            // Tutorial cards in this group
                            ForEach(group.tutorials) { tutorial in
                                TutorialCurriculumCard(
                                    tutorial: tutorial,
                                    isCompleted: tutorialService.isCompleted(tutorial.id),
                                    onStart: {
                                        dismiss()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                            tutorialService.start(tutorial)
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 32)
            }
            .navigationTitle("Tutorials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Tutorial Group

private struct TutorialGroup {
    let title: String
    let subtitle: String
    let tutorials: [Tutorial]
}

// MARK: - Tutorial Card

private struct TutorialCurriculumCard: View {
    let tutorial: Tutorial
    let isCompleted: Bool
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: tutorial.icon)
                .font(.title2)
                .foregroundStyle(tutorial.color)
                .frame(width: 48, height: 48)
                .background(tutorial.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Text
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(tutorial.title)
                        .font(.headline)

                    if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Text(tutorial.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label("\(tutorial.steps.count) steps", systemImage: "list.number")
                    Label("~\(tutorial.estimatedMinutes) min", systemImage: "clock")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            // Action button
            Button {
                onStart()
            } label: {
                Text(isCompleted ? "Replay" : "Start")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(tutorial.color)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(tutorial.color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(tutorial.color.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

#Preview {
    TutorialCurriculumView(tutorialService: TutorialService())
}
