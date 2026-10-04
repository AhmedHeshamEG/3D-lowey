@testable import HmmCommands
import XCTest

/// A tiny document: a list of words. Commands append, remove and set a counter.
private struct Words: Equatable {
    var items: [String] = []
    var counter = 0
}

private enum WordCommand: EditCommand, Equatable {
    case append(String)
    case removeLast
    case setCounter(Int)
    case fail
    indirect case batch(String, [WordCommand])

    struct Failure: Error {}

    var label: String {
        switch self {
        case .append: "Add Word"
        case .removeLast: "Remove Word"
        case .setCounter: "Set Counter"
        case .fail: "Fail"
        case let .batch(label, _): label
        }
    }

    func apply(to target: inout Words) throws -> (inverse: WordCommand, changes: Int) {
        switch self {
        case let .append(word):
            target.items.append(word)
            return (.removeLast, 1)
        case .removeLast:
            guard let last = target.items.popLast() else { throw Failure() }
            return (.append(last), 1)
        case let .setCounter(value):
            let old = target.counter
            target.counter = value
            return (.setCounter(old), 1)
        case .fail:
            throw Failure()
        case let .batch(label, commands):
            var copy = target
            var inverses: [WordCommand] = []
            for command in commands {
                try inverses.append(command.apply(to: &copy).inverse)
            }
            target = copy
            return (.batch(label, inverses.reversed()), commands.count)
        }
    }

    static func group(_ label: String, _ commands: [WordCommand]) -> WordCommand {
        .batch(label, commands)
    }
}

final class CommandStackTests: XCTestCase {
    func testPerformUndoRedo() throws {
        var words = Words()
        var stack = CommandStack<WordCommand>()
        try stack.perform(.append("a"), on: &words)
        try stack.perform(.append("b"), on: &words)
        XCTAssertEqual(words.items, ["a", "b"])
        XCTAssertEqual(stack.undoTitle, "Undo Add Word")
        try stack.undo(on: &words)
        XCTAssertEqual(words.items, ["a"])
        XCTAssertEqual(stack.redoTitle, "Redo Add Word")
        try stack.redo(on: &words)
        XCTAssertEqual(words.items, ["a", "b"])
        XCTAssertEqual(stack.revision, 4)
    }

    func testNewCommandClearsRedo() throws {
        var words = Words()
        var stack = CommandStack<WordCommand>()
        try stack.perform(.append("a"), on: &words)
        try stack.undo(on: &words)
        XCTAssertTrue(stack.canRedo)
        try stack.perform(.append("b"), on: &words)
        XCTAssertFalse(stack.canRedo)
    }

    func testCoalescingKeepsFirstInverse() throws {
        var words = Words()
        var stack = CommandStack<WordCommand>()
        for value in 1 ... 5 {
            try stack.perform(.setCounter(value), on: &words, coalesceKey: "drag")
        }
        XCTAssertEqual(stack.undoStack.count, 1)
        XCTAssertEqual(words.counter, 5)
        try stack.undo(on: &words)
        XCTAssertEqual(words.counter, 0)
        try stack.redo(on: &words)
        XCTAssertEqual(words.counter, 5)
    }

    func testEndCoalescingStartsANewStep() throws {
        var words = Words()
        var stack = CommandStack<WordCommand>()
        try stack.perform(.setCounter(1), on: &words, coalesceKey: "drag")
        stack.endCoalescing()
        try stack.perform(.setCounter(2), on: &words, coalesceKey: "drag")
        XCTAssertEqual(stack.undoStack.count, 2)
    }

    func testDifferentKeysDoNotMerge() throws {
        var words = Words()
        var stack = CommandStack<WordCommand>()
        try stack.perform(.setCounter(1), on: &words, coalesceKey: "a")
        try stack.perform(.setCounter(2), on: &words, coalesceKey: "b")
        XCTAssertEqual(stack.undoStack.count, 2)
    }

    func testGroupIsOneStepWithItsLabel() throws {
        var words = Words()
        var stack = CommandStack<WordCommand>()
        stack.beginGroup("Add Lamp")
        try stack.perform(.append("base"), on: &words)
        try stack.perform(.append("shade"), on: &words)
        XCTAssertTrue(stack.isGrouping)
        XCTAssertFalse(stack.canUndo, "nothing is undoable while a group is open")
        try stack.endGroup()
        XCTAssertEqual(stack.undoStack.count, 1)
        XCTAssertEqual(stack.undoTitle, "Undo Add Lamp")
        try stack.undo(on: &words)
        XCTAssertEqual(words.items, [])
        XCTAssertEqual(stack.redoTitle, "Redo Add Lamp")
        try stack.redo(on: &words)
        XCTAssertEqual(words.items, ["base", "shade"])
    }

    func testNestedGroupsProduceOneEntry() throws {
        var words = Words()
        var stack = CommandStack<WordCommand>()
        stack.beginGroup("Outer")
        try stack.perform(.append("a"), on: &words)
        stack.beginGroup("Inner")
        try stack.perform(.append("b"), on: &words)
        try stack.endGroup()
        try stack.endGroup()
        XCTAssertEqual(stack.undoStack.count, 1)
        try stack.undo(on: &words)
        XCTAssertEqual(words.items, [])
    }

    func testEmptyGroupRecordsNothing() throws {
        var stack = CommandStack<WordCommand>()
        stack.beginGroup("Nothing")
        try stack.endGroup()
        XCTAssertFalse(stack.canUndo)
        XCTAssertThrowsError(try stack.endGroup())
    }

    func testCancelGroupRevertsItsCommands() throws {
        var words = Words(items: ["keep"])
        var stack = CommandStack<WordCommand>()
        stack.beginGroup("Half done")
        try stack.perform(.append("a"), on: &words)
        try stack.perform(.append("b"), on: &words)
        try stack.cancelGroup(on: &words)
        XCTAssertEqual(words.items, ["keep"])
        XCTAssertFalse(stack.canUndo)
    }

    func testFailedCommandLeavesStackAndTargetAlone() throws {
        var words = Words(items: ["a"])
        var stack = CommandStack<WordCommand>()
        XCTAssertThrowsError(try stack.perform(.fail, on: &words))
        XCTAssertEqual(words.items, ["a"])
        XCTAssertFalse(stack.canUndo)
        XCTAssertEqual(stack.revision, 0)
    }

    func testFailedUndoKeepsTheEntry() throws {
        var words = Words()
        var stack = CommandStack<WordCommand>()
        try stack.perform(.append("a"), on: &words)
        words.items.removeAll() // someone broke the rules
        XCTAssertThrowsError(try stack.undo(on: &words))
        XCTAssertTrue(stack.canUndo)
    }

    func testLimitDropsOldestSteps() throws {
        var words = Words()
        var stack = CommandStack<WordCommand>(limit: 3)
        for index in 0 ..< 5 {
            try stack.perform(.append("\(index)"), on: &words)
        }
        XCTAssertEqual(stack.undoStack.count, 3)
        for _ in 0 ..< 3 {
            try stack.undo(on: &words)
        }
        XCTAssertEqual(words.items, ["0", "1"])
        XCTAssertNil(try stack.undo(on: &words))
    }

    func testTouchAndClear() throws {
        var words = Words()
        var stack = CommandStack<WordCommand>()
        try stack.perform(.append("a"), on: &words)
        stack.touch()
        XCTAssertEqual(stack.revision, 2)
        stack.clear()
        XCTAssertFalse(stack.canUndo)
        XCTAssertEqual(stack.undoTitle, "Undo")
        XCTAssertEqual(stack.redoTitle, "Redo")
    }

    func testDefaultCoalescingGroupsCommands() {
        let merged = WordCommand.coalesced(.append("a"), .append("b"))
        XCTAssertEqual(merged, .batch("Add Word", [.append("a"), .append("b")]))
        let inverse = WordCommand.coalescedInverse(earlier: .removeLast, later: .setCounter(0))
        XCTAssertEqual(inverse, .batch("Remove Word", [.setCounter(0), .removeLast]))
    }
}
