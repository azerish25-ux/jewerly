//
//  StudioUITests.swift
//  JewelcraftUITests
//
//  One end-to-end walk through the studio, plus the two things that break
//  quietly: filtering and accessibility labels.
//
//  The unit suite covers the kernel; this covers the claim that a person can
//  open a design, see it priced, read its gem report and put it in the register.
//  Controls live inside a scrolling bench, so taps scroll them into view first —
//  a test that assumes they are on screen is a test that fails on a small iPad.
//

import XCTest

final class StudioUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    // MARK: - Helpers

    private func plates() -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "design-"))
    }

    /// Scrolls the bench until `element` is hittable, or gives up after a few
    /// swipes. Returns whether it became hittable.
    @discardableResult
    private func reveal(_ element: XCUIElement, swipes: Int = 6) -> Bool {
        guard element.waitForExistence(timeout: 20) else { return false }
        if element.isHittable { return true }
        let scroller = app.scrollViews.firstMatch
        guard scroller.exists else { return element.isHittable }
        for _ in 0..<swipes {
            if element.isHittable { return true }
            scroller.swipeUp()
        }
        return element.isHittable
    }

    // MARK: - Tests

    func testDesignCanBeConfiguredQuotedAndOrdered() throws {
        XCTAssertTrue(
            app.navigationBars["Jewelcraft"].waitForExistence(timeout: 30),
            "The studio window should appear"
        )

        XCTAssertTrue(plates().firstMatch.waitForExistence(timeout: 30), "The catalogue should load plates")
        XCTAssertGreaterThan(plates().count, 1, "The fixture catalogue should hold more than one design")

        plates().firstMatch.tap()

        // The engine builds the ring and the quote panel fills in from it.
        let total = app.staticTexts["quote-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 120), "The quote should be computed for the open design")
        XCTAssertTrue(total.label.contains("$"), "The quote should be money, got \(total.label)")

        // The gem report opens and lists the centre stone.
        let reportToggle = app.buttons["gem-report-toggle"]
        XCTAssertTrue(reveal(reportToggle), "The gem report toggle should be reachable")
        reportToggle.tap()
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "CENTRE")).firstMatch
                .waitForExistence(timeout: 10),
            "The gem report should call out the centre stone"
        )

        // Adding to the register produces a reference number.
        let add = app.buttons["add-to-order"]
        XCTAssertTrue(reveal(add), "The order button should be reachable on the bench")
        XCTAssertTrue(add.isEnabled, "A priced ring should be orderable")
        add.tap()

        let receipt = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "JWL-")
        ).firstMatch
        XCTAssertTrue(receipt.waitForExistence(timeout: 30), "Adding to the register should yield a reference")
    }

    func testFiltersNarrowTheCatalogueAndCanBeCleared() throws {
        XCTAssertTrue(app.navigationBars["Jewelcraft"].waitForExistence(timeout: 30))

        XCTAssertTrue(plates().firstMatch.waitForExistence(timeout: 30))
        let initialCount = plates().count

        app.buttons["facet-toggle"].tap()

        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("zzzz-no-such-design")

        XCTAssertTrue(
            app.staticTexts["Nothing matches that yet"].waitForExistence(timeout: 15),
            "A keyword with no match should show the empty state"
        )
        XCTAssertLessThan(plates().count, initialCount, "The result count should drop")

        let clear = app.buttons["clear-filters"]
        XCTAssertTrue(clear.waitForExistence(timeout: 10))
        clear.tap()

        XCTAssertTrue(plates().firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(plates().count, initialCount, "Clearing the search should restore the full catalogue")
    }

    func testEveryPlateHasAnAccessibleLabel() throws {
        XCTAssertTrue(app.navigationBars["Jewelcraft"].waitForExistence(timeout: 30))
        XCTAssertTrue(plates().firstMatch.waitForExistence(timeout: 30))

        let inspected = min(plates().count, 12)
        for index in 0..<inspected {
            let plate = plates().element(boundBy: index)
            XCTAssertFalse(plate.label.isEmpty, "Plate \(index) should expose a spoken label")
            XCTAssertTrue(plate.isEnabled, "Plate \(index) should be selectable")
        }
    }
}
