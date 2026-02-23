import XCTest

final class ExploreSearchUITest: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testExploreSearchForBarra() throws {
        let app = XCUIApplication()
        app.launch()

        // Wait for app to fully load
        sleep(4)

        // Tap the "List" tab (second tab in tab bar)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "Tab bar not found")
        let listTab = tabBar.buttons["List"]
        XCTAssertTrue(listTab.waitForExistence(timeout: 5), "List tab not found")
        listTab.tap()
        sleep(2)

        // Take screenshot to see current state
        let ss1 = app.screenshot()
        let a1 = XCTAttachment(screenshot: ss1)
        a1.name = "1_list_tab"
        a1.lifetime = .keepAlways
        add(a1)

        // The segmented control has "Community" and "Explore" segments
        // Use the segmented control specifically, not the tab bar
        let segmentedControl = app.segmentedControls.firstMatch
        XCTAssertTrue(segmentedControl.waitForExistence(timeout: 5), "Segmented control not found")
        NSLog("🧪 [UITest] Segmented control exists: %d", segmentedControl.exists ? 1 : 0)

        let exploreSegment = segmentedControl.buttons["Explore"]
        XCTAssertTrue(exploreSegment.waitForExistence(timeout: 5), "Explore segment not found")
        exploreSegment.tap()
        sleep(1)

        // Take screenshot after switching to Explore
        let ss2 = app.screenshot()
        let a2 = XCTAttachment(screenshot: ss2)
        a2.name = "2_explore_mode"
        a2.lifetime = .keepAlways
        add(a2)

        // Find the search field and type "Barra"
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field not found")
        NSLog("🧪 [UITest] Search field found, placeholder: %@", searchField.placeholderValue ?? "nil")
        searchField.tap()
        Thread.sleep(forTimeInterval: 0.5)
        searchField.typeText("Barra")
        NSLog("🧪 [UITest] Typed 'Barra', waiting for results...")

        // Wait up to 8 seconds for results
        sleep(3)

        // Take screenshot to see result state
        let ss3 = app.screenshot()
        let a3 = XCTAttachment(screenshot: ss3)
        a3.name = "3_after_typing_barra"
        a3.lifetime = .keepAlways
        add(a3)

        sleep(3)

        let ss4 = app.screenshot()
        let a4 = XCTAttachment(screenshot: ss4)
        a4.name = "4_after_wait"
        a4.lifetime = .keepAlways
        add(a4)

        // Log all visible static texts
        let texts = app.staticTexts.allElementsBoundByIndex.map { $0.label }
        NSLog("🧪 [UITest] All visible texts: %@", texts.joined(separator: " | "))

        let cells = app.cells
        NSLog("🧪 [UITest] Cell count: %d", cells.count)

        // Check for results
        let hasResults = cells.count > 0 ||
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Apple Maps'")).firstMatch.exists

        XCTAssertTrue(hasResults,
            "Expected search results after typing 'Barra'. Texts found: \(texts.joined(separator: ", "))")
    }
}
