//
//  bilingual_reader_watch_flashcard_Watch_AppTests.swift
//  bilingual reader watch flashcard Watch AppTests
//
//  Created by Akram Rasikh on 18/07/2026.
//

import XCTest
@testable import bilingual_reader_watch_flashcard_Watch_App

final class bilingual_reader_watch_flashcard_Watch_AppTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Tests marked async will run the test method on an arbitrary thread managed by the Swift runtime.
    }

    func testSnippetFocusExactMatchFadesOutsideSpan() {
        let focus = SnippetFocus(
            fullText: "hello world again",
            query: "world",
            trimmed: false,
            startOffset: 0,
            lengthAdjustment: 0
        )
        XCTAssertEqual(focus.matchStart, 6)
        XCTAssertEqual(focus.matchEnd, 11)
        XCTAssertEqual(focus.textMatch, "world")
        XCTAssertFalse(focus.hasChanged)
    }

    func testSnippetFocusTrimmedLanguageStepsOneCharacter() {
        var focus = SnippetFocus(
            fullText: "你好世界",
            query: "好世",
            trimmed: true,
            startOffset: 0,
            lengthAdjustment: 0
        )
        XCTAssertEqual(focus.textMatch, "好世")
        focus.moveLeft()
        XCTAssertEqual(focus.textMatch, "你好")
        focus.moveRight()
        focus.moveRight()
        XCTAssertEqual(focus.textMatch, "世界")
        focus.expand()
        XCTAssertEqual(focus.textMatch, "世界")
        XCTAssertEqual(focus.matchEnd, 4)
    }

    func testSnippetFocusWordStepAndReset() {
        var focus = SnippetFocus(
            fullText: "hello world again",
            query: "world",
            trimmed: false,
            startOffset: 0,
            lengthAdjustment: 0
        )
        focus.moveLeft()
        XCTAssertEqual(focus.textMatch, "hello")
        focus.reset()
        focus.expand()
        XCTAssertEqual(focus.textMatch, "world again")
        focus.reset()
        XCTAssertEqual(focus.textMatch, "world")
        XCTAssertFalse(focus.hasChanged)
    }

    func testSnippetFocusWithoutMatchShowsFullText() {
        let focus = SnippetFocus(
            fullText: "bonjour",
            query: "",
            trimmed: false,
            startOffset: 0,
            lengthAdjustment: 0
        )
        XCTAssertFalse(focus.canAdjust)
        XCTAssertEqual(focus.textMatch, "bonjour")
        var moved = focus
        moved.moveLeft()
        XCTAssertEqual(moved.textMatch, "bonjour")
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
