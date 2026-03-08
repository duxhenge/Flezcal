import SwiftUI

/// Manages tutorial state — which tutorial is active, current step, completion tracking.
/// Persists completion state via @AppStorage.
@MainActor
class TutorialService: ObservableObject {
    // MARK: - Published State

    @Published var activeTutorial: Tutorial? = nil
    @Published var currentStepIndex: Int = 0
    @Published var targetFrames: [String: CGRect] = [:]
    /// Set to true after a tutorial completes so the curriculum sheet can re-appear.
    @Published var shouldShowCurriculum: Bool = false

    // MARK: - Persistence

    /// Comma-separated IDs of completed tutorials.
    @AppStorage("tutorial_completed") private var completedRaw: String = ""
    /// Stores "id:version" pairs so we can detect when content has been updated.
    @AppStorage("tutorial_completedVersions") private var completedVersionsRaw: String = ""
    @AppStorage("tutorial_curriculumShown") var hasShownCurriculum: Bool = false

    private(set) var completedTutorials: Set<String> = []

    // MARK: - Tab Switching

    /// ContentView sets this so the tutorial can drive tab selection.
    var switchTab: ((Int) -> Void)?

    // MARK: - Computed

    var currentStep: TutorialStep? {
        guard let tutorial = activeTutorial,
              currentStepIndex < tutorial.steps.count else { return nil }
        return tutorial.steps[currentStepIndex]
    }

    var isActive: Bool { activeTutorial != nil }

    var stepCount: Int { activeTutorial?.steps.count ?? 0 }

    // MARK: - Init

    init() {
        let raw = UserDefaults.standard.string(forKey: "tutorial_completed") ?? ""
        completedTutorials = Set(raw.split(separator: ",").map(String.init))

        // Version check — invalidate tutorials whose content has been updated.
        let versionsRaw = UserDefaults.standard.string(forKey: "tutorial_completedVersions") ?? ""
        var storedVersions: [String: Int] = [:]
        for entry in versionsRaw.split(separator: ",") {
            let parts = entry.split(separator: ":")
            if parts.count == 2, let ver = Int(parts[1]) {
                storedVersions[String(parts[0])] = ver
            }
        }

        var didInvalidate = false
        for tutorial in Tutorial.allTutorials {
            let id = tutorial.id.rawValue
            if completedTutorials.contains(id),
               storedVersions[id] != tutorial.version {
                // Content has been updated since the user completed this tutorial — reset it.
                completedTutorials.remove(id)
                didInvalidate = true
            }
        }

        if didInvalidate {
            completedRaw = completedTutorials.joined(separator: ",")
        }
    }

    // MARK: - Actions

    func start(_ tutorial: Tutorial) {
        activeTutorial = tutorial

        if let tab = tutorial.steps.first?.requiredTab {
            switchTab?(tab)
        }
        // Set step immediately — TutorialOverlay shows the step as soon as the
        // target frame is reported. If the frame isn't available yet (tab still
        // rendering), the overlay shows a brief loading state with a skip button.
        currentStepIndex = 0
    }

    func nextStep() {
        guard let tutorial = activeTutorial else { return }
        let nextIndex = currentStepIndex + 1
        if nextIndex >= tutorial.steps.count {
            complete()
            return
        }

        // If the next step requires a different tab, switch first
        if let tab = tutorial.steps[nextIndex].requiredTab {
            switchTab?(tab)
        }
        currentStepIndex = nextIndex
    }

    func previousStep() {
        guard activeTutorial != nil, currentStepIndex > 0 else { return }
        let prevIndex = currentStepIndex - 1

        // If the previous step requires a different tab, switch first
        if let tab = activeTutorial?.steps[prevIndex].requiredTab {
            switchTab?(tab)
        }
        currentStepIndex = prevIndex
    }

    func skip() {
        activeTutorial = nil
        currentStepIndex = 0

        // Return to the curriculum sheet so the user can pick another tutorial.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.shouldShowCurriculum = true
        }
    }

    func complete() {
        guard let tutorial = activeTutorial else { return }
        let id = tutorial.id.rawValue
        completedTutorials.insert(id)
        completedRaw = completedTutorials.joined(separator: ",")

        // Store the version so we can detect future content updates.
        var storedVersions: [String: Int] = [:]
        for entry in completedVersionsRaw.split(separator: ",") {
            let parts = entry.split(separator: ":")
            if parts.count == 2, let ver = Int(parts[1]) {
                storedVersions[String(parts[0])] = ver
            }
        }
        storedVersions[id] = tutorial.version
        completedVersionsRaw = storedVersions.map { "\($0.key):\($0.value)" }.joined(separator: ",")

        activeTutorial = nil
        currentStepIndex = 0

        // Re-show the curriculum sheet after a brief pause so the user can pick another tutorial.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.shouldShowCurriculum = true
        }
    }

    func isCompleted(_ id: TutorialID) -> Bool {
        completedTutorials.contains(id.rawValue)
    }

    func markCurriculumShown() {
        hasShownCurriculum = true
    }
}
