import SwiftUI

// MARK: - Tutorial ID

enum TutorialID: String, CaseIterable, Codable {
    case setupFlezcals
    case spotsTab
    case mapExplore
    case addSpot
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
    static let allTutorials: [Tutorial] = [setupFlezcals, spotsTab, mapExplore, addSpot]

    // MARK: Tutorial 1 — Setting Up Your Flezcals

    static let setupFlezcals = Tutorial(
        id: .setupFlezcals,
        title: "Setting Up Your Flezcals",
        subtitle: "Make this app yours. Pick the foods and drinks you actually care about.",
        icon: "heart.circle.fill",
        color: .orange,
        steps: [
            .textOnly(
                title: "Sign In",
                body: "Join our passionate community. Share your best food and drink experiences and where you found them. Signing in lets you add spots, rate them, verify what others have found, and climb the leaderboard. Sign in with Apple is the fastest way. You're free to browse without an account, but the real fun starts when you contribute."
            ),
            .spotlight(
                "pickSubtitle",
                title: "This Is Your Home Base",
                body: "Flezcals are your cravings. Share your very best experiences. Let the community help you find them. Web searches are available but its community input that helps the most.",
                arrowEdge: .bottom,
                requiredTab: AppTab.myPicks,
                shape: .rect(cornerRadius: 12)
            ),
            .spotlight(
                "editButton_mezcal",
                title: "Fine-Tune Your Search",
                body: "Tap here to add improved search terms for your Flezcals.",
                arrowEdge: .top,
                shape: .circle
            ),
            .spotlight(
                "customizeButton",
                title: "Make It Yours",
                body: "There are 50+ trending categories to choose from, and you can have up to 3 active at once. Your picks shape everything: the map, the search results, the ghost pins.",
                arrowEdge: .bottom,
                shape: .rect(cornerRadius: 16)
            ),
            .textOnly(
                title: "Or Create Something New",
                body: "Don't see your thing? Tap \"Create Your Own\" Flezcal category. Name it, pick an emoji, and refine your search terms. We track them and when enough people search for the same thing, it can become an official category."
            ),
        ],
        estimatedMinutes: 1
    )

    // MARK: Tutorial 2 — The Spots Tab

    static let spotsTab = Tutorial(
        id: .spotsTab,
        title: "The Spots Tab",
        subtitle: "Browse, search, and filter verified spots and web search results in one place.",
        icon: "list.bullet",
        color: .purple,
        steps: [
            .screenshot(
                "tutorial_spots_overview",
                title: "Create a List of Spots to Consider",
                body: "Search where you are or anywhere in the world. Search for spots the search terms don't find and add them. Our spot list is better than a web search.",
                requiredTab: AppTab.spots,
                cropRegion: CGRect(x: 0, y: 0.03, width: 1, height: 0.5)
            ),
            .screenshot(
                "tutorial_spots_filters",
                title: "Filter by Category",
                body: "Use filters to see or hide your selected Flezcals.",
                cropRegion: CGRect(x: 0, y: 0.0, width: 1, height: 0.5)
            ),
            .screenshot(
                "tutorial_spots_toggles",
                title: "Choose Your Sources",
                body: "Use toggles to see any or all of Verified, Likely, and Nearby spots.",
                cropRegion: CGRect(x: 0, y: 0.05, width: 1, height: 0.5)
            ),
            .screenshot(
                "tutorial_spots_search",
                title: "Search Any City",
                body: "Tap the location bar to search a different city. Type a name, pick from the suggestions, and the app scans that area for your Flezcals. Great for planning trips.",
                cropRegion: CGRect(x: 0, y: 0.0, width: 1, height: 0.35)
            ),
            .screenshot(
                "tutorial_spots_customize",
                title: "Customize Your Search",
                body: "Tap \"Customize Spot Search\" to fine-tune your search terms and adjust the search radius.",
                cropRegion: CGRect(x: 0, y: 0.02, width: 1, height: 0.42)
            ),
            .screenshot(
                "tutorial_spots_wider",
                title: "Search Wider Area",
                body: "Click \"Search Wider Area\" after the initial search for more potential venues.",
                cropRegion: CGRect(x: 0, y: 0.68, width: 1, height: 0.27)
            ),
        ],
        estimatedMinutes: 1
    )

    // MARK: Tutorial 3 — The Map

    static let mapExplore = Tutorial(
        id: .mapExplore,
        title: "The Map",
        subtitle: "Your Flezcals, live on a map. Let the app do the hunting.",
        icon: "map.fill",
        color: .green,
        steps: [
            .spotlight(
                "mapView",
                title: "Your Discovery Map",
                body: "This is where the magic of community input will grow your experience. The best information comes from spots with Flezcals verified by people like you.\n\nThe app can also search for your Flezcals among unverified spots when limited community input is available. Search anywhere in the world.",
                arrowEdge: .top,
                requiredTab: AppTab.explore,
                shape: .rect(cornerRadius: 0)
            ),
            .screenshot(
                "tutorial_pin_colors",
                title: "What the Colors Mean",
                body: "Solid pins are Verified spots, the most valuable information we have.\n\nGreen pins with checkmarks are Likely web search matches that are found with your keywords on websites.\n\nYellow ghost pins are Nearby spots that may need a deeper website search. Click on one if it seems like a likely spot for your Flezcal.",
                cropRegion: CGRect(x: 0, y: 0.05, width: 1, height: 0.6)
            ),
            .spotlight(
                "filterPills",
                title: "Zero In",
                body: "Looking for just one Flezcal? Tap to filter the map.",
                arrowEdge: .top,
                shape: .rect(cornerRadius: 20)
            ),
            .spotlight(
                "pinToggles",
                title: "Control What You See",
                body: "Three toggles: Verified, Likely, and Nearby.\n\nTurn them on or off to focus on what matters.\n\nThe counts tell you how many of each are around you.",
                arrowEdge: .top,
                shape: .rect(cornerRadius: 12)
            ),
            .screenshot(
                "tutorial_ghost_pin_sheet",
                title: "Tap Any Pin",
                body: "Curious about a spot? Tap it. The app runs a deep website scan and tells you exactly which of your Flezcals it found.",
                cropRegion: CGRect(x: 0, y: 0.08, width: 1, height: 0.38)
            ),
            .screenshot(
                "tutorial_search_button",
                title: "Explore New Territory",
                body: "Pan the map anywhere and tap \"Search This Area\". Road trip or vacation planning starts here.",
                cropRegion: CGRect(x: 0, y: 0.78, width: 1, height: 0.15)
            ),
            .screenshot(
                "tutorial_deeper_scan",
                title: "Go Deeper",
                body: "After the first scan, tap \"Search Wider Area\" to check even more venues. Hidden gems that were further away get promoted to your map.",
                cropRegion: CGRect(x: 0, y: 0.78, width: 1, height: 0.15)
            ),
        ],
        estimatedMinutes: 2
    )

    // MARK: Tutorial 4 — Adding a Spot

    static let addSpot = Tutorial(
        id: .addSpot,
        title: "Adding a Spot",
        subtitle: "You found something great. Now share it so others can find it too.",
        icon: "mappin.circle.fill",
        color: .blue,
        steps: [
            .screenshot(
                "tutorial_spot_sheet",
                title: "Adding Spots",
                body: "A green checkmark is a potential new Flezcal spot for you to try out and verify.",
                cropRegion: CGRect(x: 0, y: 0.08, width: 1, height: 0.35)
            ),
            .screenshot(
                "tutorial_category_chips",
                title: "Read the Chips",
                body: "Solid color is already verified by the community.\n\nGreen ✓ = your search term found something.\n\nYellow ? = Still a possibility. If the name looks promising check it out.",
                cropRegion: CGRect(x: 0, y: 0.25, width: 1, height: 0.2)
            ),
            .screenshot(
                "tutorial_add_button",
                title: "Claim It",
                body: "Tap here to add this spot to Flezcal. You're building the guide that helps everyone find the good stuff.",
                cropRegion: CGRect(x: 0.05, y: 0.82, width: 0.9, height: 0.12)
            ),
            .screenshot(
                "tutorial_pick_category",
                title: "Verifying a New Spot",
                body: "Pick which Flezcal this spot offers.\n\nAdditional Flezcals can be added one at a time.",
                cropRegion: CGRect(x: 0, y: 0.02, width: 1, height: 0.55)
            ),
            .screenshot(
                "tutorial_confirm_spot",
                title: "Share What You Know",
                body: "Add specific offerings: brands, flavors, styles. The details you share are what make someone else's visit better.",
                cropRegion: CGRect(x: 0, y: 0.48, width: 1, height: 0.42)
            ),
            .screenshot(
                "tutorial_rate_spot",
                title: "Rate It",
                body: "We have high standards to identify the best!\n\nYour rating helps the best spots rise to the top.\n\nOnly rate what you've actually tried.",
                cropRegion: CGRect(x: 0, y: 0.28, width: 1, height: 0.65)
            ),
        ],
        estimatedMinutes: 2
    )
}
