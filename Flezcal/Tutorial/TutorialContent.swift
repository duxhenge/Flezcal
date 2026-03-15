import SwiftUI

// MARK: - Tutorial ID

enum TutorialID: String, CaseIterable, Codable {
    case setupFlezcals
    case spotsTab
    case mapExplore
    case addSpot
    case ratingVerifying
    case leaderboard
}

// MARK: - Tutorial Step

struct TutorialStep {
    /// Matches `.tutorialTarget("id")` on the view. Nil for screenshot-only steps.
    let targetID: String?
    let title: String
    let body: String
    /// Which edge of the card the arrow appears on (points toward the target).
    let arrowEdge: Edge
    /// AppTab constant — switches to this tab before showing the step. Nil = stay on current tab.
    let requiredTab: Int?
    let spotlightShape: SpotlightShape
    /// Asset name for a static screenshot shown inline in the card. Nil = spotlight live element.
    let screenshotImage: String?
    /// Unit-coordinate rect (0–1) defining which region of the screenshot to zoom into.
    /// Nil = show the full image. Example: CGRect(x: 0, y: 0, width: 1, height: 0.5) shows the top half.
    let screenshotCropRegion: CGRect?

    enum SpotlightShape {
        case rect(cornerRadius: CGFloat)
        case capsule
        case circle
        case none
    }

    /// Convenience initializer for live spotlight steps.
    static func spotlight(
        _ targetID: String,
        title: String,
        body: String,
        arrowEdge: Edge = .top,
        requiredTab: Int? = nil,
        shape: SpotlightShape = .rect(cornerRadius: 16)
    ) -> TutorialStep {
        TutorialStep(
            targetID: targetID,
            title: title,
            body: body,
            arrowEdge: arrowEdge,
            requiredTab: requiredTab,
            spotlightShape: shape,
            screenshotImage: nil,
            screenshotCropRegion: nil
        )
    }

    /// Convenience initializer for screenshot-only steps.
    /// `cropRegion` is a unit-coordinate rect (0–1) to zoom into a portion of the image.
    static func screenshot(
        _ imageName: String,
        title: String,
        body: String,
        requiredTab: Int? = nil,
        cropRegion: CGRect? = nil
    ) -> TutorialStep {
        TutorialStep(
            targetID: nil,
            title: title,
            body: body,
            arrowEdge: .top,
            requiredTab: requiredTab,
            spotlightShape: .none,
            screenshotImage: imageName,
            screenshotCropRegion: cropRegion
        )
    }

    /// Convenience initializer for text-only steps (no spotlight, no screenshot).
    static func textOnly(
        title: String,
        body: String,
        requiredTab: Int? = nil
    ) -> TutorialStep {
        TutorialStep(
            targetID: nil,
            title: title,
            body: body,
            arrowEdge: .top,
            requiredTab: requiredTab,
            spotlightShape: .none,
            screenshotImage: nil,
            screenshotCropRegion: nil
        )
    }
}

// MARK: - Tutorial

struct Tutorial: Identifiable {
    let id: TutorialID
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let steps: [TutorialStep]
    let estimatedMinutes: Int

    /// Auto-computed from step content using a stable hash (djb2).
    /// Any text change automatically invalidates the stored completion
    /// so users see updated tutorials without manual version bumps.
    var version: Int {
        var combined = subtitle
        for step in steps {
            combined += step.title + step.body
            combined += step.targetID ?? ""
            combined += step.screenshotImage ?? ""
        }
        // djb2 hash — deterministic across launches (unlike Swift's Hasher)
        var hash: UInt64 = 5381
        for byte in combined.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        return Int(hash & 0x7FFFFFFF)
    }
}

// MARK: - All Tutorials

extension Tutorial {
    static let allTutorials: [Tutorial] = [
        setupFlezcals, spotsTab, mapExplore,   // Getting Started
        addSpot, ratingVerifying,               // Contributing
        leaderboard                             // Growing
    ]

    // MARK: Tutorial 1 — Setting Up Your Flezcals

    static let setupFlezcals = Tutorial(
        id: .setupFlezcals,
        title: "Setting Up Your \(AppBranding.namePlural)",
        subtitle: "Pick the foods and drinks you care about.",
        icon: "heart.circle.fill",
        color: .orange,
        steps: [
            .textOnly(
                title: "Sign In to Get Started",
                body: "Sign in with Apple to add spots, rate them, and join the leaderboard."
            ),
            .spotlight(
                "pickSubtitle",
                title: "Your Home Base",
                body: "\(AppBranding.namePlural) are your cravings. The community helps you find the best.",
                arrowEdge: .bottom,
                requiredTab: AppTab.myPicks,
                shape: .rect(cornerRadius: 12)
            ),
            .spotlight(
                "editButton_first",
                title: "Fine-Tune Search Terms",
                body: "Tap to customize the search terms for any \(AppBranding.name).",
                arrowEdge: .top,
                shape: .circle
            ),
            .spotlight(
                "customizeButton",
                title: "Swap or Add Categories",
                body: "60+ categories available. Pick up to 3 active \(AppBranding.namePlural).",
                arrowEdge: .bottom,
                shape: .rect(cornerRadius: 16)
            ),
        ],
        estimatedMinutes: 1
    )

    // MARK: Tutorial 2 — The Spots Tab

    static let spotsTab = Tutorial(
        id: .spotsTab,
        title: "The Spots Tab",
        subtitle: "Search, filter, and browse spots anywhere.",
        icon: "list.bullet",
        color: .cyan,
        steps: [
            .screenshot(
                "tutorial_spots_search",
                title: "Search Here or Any City",
                body: "Tap the location bar to search your area or pick a different city.",
                requiredTab: AppTab.spots,
                cropRegion: CGRect(x: 0, y: 0.04, width: 1, height: 0.22)
            ),
            .screenshot(
                "tutorial_spots_customize",
                title: "Customize Your Search Terms",
                body: "Tap \"Customize Spot Search\" to refine terms for each \(AppBranding.name).",
                cropRegion: CGRect(x: 0, y: 0.15, width: 1, height: 0.18)
            ),
            .screenshot(
                "tutorial_spots_overview",
                title: "Browse Your Spot List",
                body: "Spots appear from community data and web searches.",
                cropRegion: CGRect(x: 0, y: 0.18, width: 1, height: 0.55)
            ),
            .screenshot(
                "tutorial_spots_toggles",
                title: "Toggle Verified, Likely, Nearby",
                body: "Control which source types appear in your list.",
                cropRegion: CGRect(x: 0, y: 0.17, width: 1, height: 0.20)
            ),
            .screenshot(
                "tutorial_spots_wider",
                title: "Expand Your Search",
                body: "Tap \"Do a Deeper Scan?\" to check more venues nearby.",
                cropRegion: CGRect(x: 0, y: 0.7, width: 1, height: 0.25)
            ),
        ],
        estimatedMinutes: 1
    )

    // MARK: Tutorial 3 — The Map

    static let mapExplore = Tutorial(
        id: .mapExplore,
        title: "The Map",
        subtitle: "Your \(AppBranding.namePlural), live on a map.",
        icon: "map.fill",
        color: .green,
        steps: [
            .spotlight(
                "mapView",
                title: "Your Discovery Map",
                body: "Pins appear automatically for your active \(AppBranding.namePlural).",
                arrowEdge: .top,
                requiredTab: AppTab.explore,
                shape: .rect(cornerRadius: 0)
            ),
            .screenshot(
                "tutorial_pin_colors",
                title: "Read the Pin Colors",
                body: "Solid = Verified. Green check = Likely. Yellow = Nearby.",
                cropRegion: CGRect(x: 0, y: 0.08, width: 1, height: 0.55)
            ),
            .spotlight(
                "filterPills",
                title: "Filter to One \(AppBranding.name)",
                body: "Tap a pill to isolate one category on the map.",
                arrowEdge: .top,
                shape: .rect(cornerRadius: 20)
            ),
            .screenshot(
                "tutorial_ghost_pin_sheet",
                title: "Tap Any Pin",
                body: "The app scans the website and shows which \(AppBranding.namePlural) match.",
                cropRegion: CGRect(x: 0, y: 0.38, width: 1, height: 0.45)
            ),
            .screenshot(
                "tutorial_search_button",
                title: "Search New Areas",
                body: "Pan the map, then tap \"Search This Area\" to explore.",
                cropRegion: CGRect(x: 0, y: 0.6, width: 1, height: 0.35)
            ),
        ],
        estimatedMinutes: 1
    )

    // MARK: Tutorial 4 — Adding a Spot

    static let addSpot = Tutorial(
        id: .addSpot,
        title: "Adding a Spot",
        subtitle: "Found something great? Share it with the community.",
        icon: "mappin.circle.fill",
        color: .blue,
        steps: [
            .screenshot(
                "tutorial_spot_sheet",
                title: "Spot a Green Checkmark",
                body: "Green means a web search found a match for your \(AppBranding.name).",
                cropRegion: CGRect(x: 0, y: 0.38, width: 1, height: 0.35)
            ),
            .screenshot(
                "tutorial_category_chips",
                title: "Check the Category Matches",
                body: "Solid = verified. Green check = likely match from a web scan.",
                cropRegion: CGRect(x: 0, y: 0.35, width: 1, height: 0.35)
            ),
            .screenshot(
                "tutorial_add_button",
                title: "Tap Add to Verify It",
                body: "You're building the guide that helps everyone.",
                cropRegion: CGRect(x: 0, y: 0.7, width: 1, height: 0.25)
            ),
            .screenshot(
                "tutorial_pick_category",
                title: "Pick the \(AppBranding.name) Category",
                body: "Choose which \(AppBranding.name) this spot offers.",
                cropRegion: CGRect(x: 0, y: 0.04, width: 1, height: 0.45)
            ),
            .screenshot(
                "tutorial_confirm_spot",
                title: "Add Offerings and Details",
                body: "Next up: rate and verify in the Rating & Verifying tutorial.",
                cropRegion: CGRect(x: 0, y: 0.35, width: 1, height: 0.5)
            ),
        ],
        estimatedMinutes: 1
    )

    // MARK: Tutorial 5 — Rating & Verifying

    static let ratingVerifying = Tutorial(
        id: .ratingVerifying,
        title: "Rating & Verifying",
        subtitle: "Rate what you've tried. Help the best spots rise.",
        icon: "flame.fill",
        color: .purple,
        steps: [
            .screenshot(
                "tutorial_rate_prompt",
                title: "Find the Rate Button",
                body: "On any spot, tap \"Add your rating\" under a \(AppBranding.name).",
                requiredTab: AppTab.spots,
                cropRegion: CGRect(x: 0, y: 0.28, width: 1, height: 0.3)
            ),
            .screenshot(
                "tutorial_rating_picker",
                title: "Pick Your Flan Rating",
                body: "1-5 flans, from Confirmed Spot up to World Class.",
                cropRegion: CGRect(x: 0, y: 0.37, width: 1, height: 0.35)
            ),
            .screenshot(
                "tutorial_rating_confirm",
                title: "Confirm Your Rating",
                body: "Review your choice. Only rate what you've actually tried.",
                cropRegion: CGRect(x: 0, y: 0.33, width: 1, height: 0.32)
            ),
            .screenshot(
                "tutorial_verify_button",
                title: "Report Inaccurate Pins",
                body: "Tap \"Not accurate, remove pin\" to clean up bad results.",
                cropRegion: CGRect(x: 0, y: 0.55, width: 1, height: 0.35)
            ),
        ],
        estimatedMinutes: 1
    )

    // MARK: Tutorial 6 — The Leaderboard

    static let leaderboard = Tutorial(
        id: .leaderboard,
        title: "The Leaderboard",
        subtitle: "See how your contributions stack up.",
        icon: "trophy.fill",
        color: .yellow,
        steps: [
            .screenshot(
                "tutorial_leaderboard_rank",
                title: "Check Your Rank",
                body: "See where you stand among the top contributors.",
                requiredTab: AppTab.leaderboard,
                cropRegion: CGRect(x: 0, y: 0.07, width: 1, height: 0.45)
            ),
            .screenshot(
                "tutorial_leaderboard_scoring",
                title: "Understand the Scoring",
                body: "Spot +10, Rating +5, Find +3, Brand +1, Confirm +1.",
                cropRegion: CGRect(x: 0, y: 0.84, width: 1, height: 0.16)
            ),
        ],
        estimatedMinutes: 1
    )
}
