import AppKit
import Foundation
import Testing
@testable import NotchKit

@Suite("Join meeting links")
struct MeetingLinkTests {
    @Test func findsCommonCallLinks() {
        #expect(CalendarRules.meetingURL(in: ["Join: https://meet.google.com/abc-defg-hij"])?.host == "meet.google.com")
        #expect(CalendarRules.meetingURL(in: [nil, "https://us02web.zoom.us/j/123456789?pwd=xyz"])?.host == "us02web.zoom.us")
        #expect(CalendarRules.meetingURL(in: ["<https://teams.microsoft.com/l/meetup-join/19%3ameeting_x/0>"])?.host == "teams.microsoft.com")
        #expect(CalendarRules.meetingURL(in: ["https://acme.webex.com/meet/pat"])?.host == "acme.webex.com")
    }

    @Test func ignoresOtherLinksAndLookalikes() {
        #expect(CalendarRules.meetingURL(in: ["Agenda: https://docs.google.com/document/d/1"]) == nil)
        #expect(CalendarRules.meetingURL(in: ["https://notzoom.us/j/1", "Room 4B", ""]) == nil)
        #expect(CalendarRules.meetingURL(in: []) == nil)
    }

    @Test func prefersEarlierFields() {
        let url = CalendarRules.meetingURL(in: ["https://zoom.us/j/1", "https://meet.google.com/aaa-bbbb-ccc"])
        #expect(url?.host == "zoom.us")
    }

    @Test func joinIsOfferedFromFifteenMinutesBeforeUntilTheEnd() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let link = try #require(URL(string: "https://meet.google.com/aaa-bbbb-ccc"))
        func event(startsIn minutes: Double, link: URL?) -> CalendarEvent {
            let start = now.addingTimeInterval(minutes * 60)
            return CalendarEvent(id: "e", title: "Call", start: start, end: start.addingTimeInterval(1800), meetingURL: link)
        }
        #expect(CalendarRules.canJoin(event(startsIn: 10, link: link), at: now))
        #expect(CalendarRules.canJoin(event(startsIn: -20, link: link), at: now))
        #expect(!CalendarRules.canJoin(event(startsIn: 40, link: link), at: now))
        #expect(!CalendarRules.canJoin(event(startsIn: -40, link: link), at: now))
        #expect(!CalendarRules.canJoin(event(startsIn: 5, link: nil), at: now))
    }

    @Test func eventAlertWithALinkStaysLonger() throws {
        let link = try #require(URL(string: "https://zoom.us/j/1"))
        #expect(IslandAlert.upcomingEvent(title: "A", minutes: 5).displayDuration == 8)
        #expect(IslandAlert.upcomingEvent(title: "A", minutes: 5, meetingURL: link).displayDuration == 20)
    }
}

@Suite("Focus mode")
struct FocusCycleTests {
    @Test func pomodoroRhythm() {
        var cycle = FocusCycle()
        #expect(cycle.phase == .focus && cycle.duration == 25 * 60)
        var phases: [FocusCycle.Phase] = []
        for _ in 0..<8 {
            cycle.advance()
            phases.append(cycle.phase)
        }
        #expect(phases == [.shortBreak, .focus, .shortBreak, .focus, .shortBreak, .focus, .longBreak, .focus])
        #expect(cycle.completed == 4)
        #expect(FocusCycle.duration(of: .longBreak) == 15 * 60)
    }

    @MainActor
    @Test func timerServiceRunsAndEndsFocus() throws {
        var clock = Date(timeIntervalSince1970: 0)
        let service = TimerService(now: { clock })
        service.startFocus()
        #expect(service.focus?.phase == .focus)
        #expect(service.timer?.duration == FocusCycle.focusLength)

        clock = clock.addingTimeInterval(25 * 60 + 1)
        let next = try #require(service.advanceFocus())
        #expect(next.phase == .shortBreak)
        #expect(service.timer?.duration == FocusCycle.shortBreakLength)
        #expect(service.isActive)

        service.start(duration: 60)
        #expect(service.focus == nil)
        service.startFocus()
        service.cancel()
        #expect(service.focus == nil && service.timer == nil)
    }

    @Test func focusAlertIsShortAndATimerKind() {
        let alert = IslandAlert.focusPhase(.shortBreak, completed: 1)
        #expect(alert.kind == .timer)
        #expect(!alert.isUrgent)
        #expect(alert.displayDuration == 4)
    }
}

@Suite("Clipboard history")
@MainActor
struct ClipboardHistoryTests {
    private func makeHistory() -> (ClipboardHistory, NSPasteboard) {
        let board = NSPasteboard(name: NSPasteboard.Name("DynamicNotchTests-\(UUID().uuidString)"))
        return (ClipboardHistory(pasteboard: board), board)
    }

    @Test func keepsNewestFirstWithoutDuplicates() {
        let (history, board) = makeHistory()
        defer { board.releaseGlobally() }
        history.record("one")
        history.record("two")
        history.record("one")
        history.record("   \n")
        #expect(history.clips.map(\.text) == ["one", "two"])
    }

    @Test func capsAtCapacityAndLength() {
        let (history, board) = makeHistory()
        defer { board.releaseGlobally() }
        for index in 0..<(ClipboardHistory.capacity + 5) {
            history.record("clip \(index)")
        }
        #expect(history.clips.count == ClipboardHistory.capacity)
        #expect(history.clips.first?.text == "clip \(ClipboardHistory.capacity + 4)")
        history.record(String(repeating: "x", count: ClipboardHistory.maximumLength + 50))
        #expect(history.clips.first?.text.count == ClipboardHistory.maximumLength)
    }

    @Test func skipsSecretsFromPasswordManagers() {
        #expect(ClipboardHistory.shouldIgnore(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        #expect(!ClipboardHistory.shouldIgnore(types: ["public.utf8-plain-text"]))

        let (history, board) = makeHistory()
        defer { board.releaseGlobally() }
        history.start()
        board.clearContents()
        let item = NSPasteboardItem()
        item.setString("hunter2", forType: .string)
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        board.writeObjects([item])
        history.poll()
        #expect(history.clips.isEmpty)

        board.clearContents()
        board.setString("hello", forType: .string)
        history.poll()
        #expect(history.clips.map(\.text) == ["hello"])
        history.stop()
        #expect(history.clips.isEmpty)
    }

    @Test func copyingBackIsNotANewEntry() throws {
        let (history, board) = makeHistory()
        defer { board.releaseGlobally() }
        history.start()
        history.record("first")
        history.record("second")
        let first = try #require(history.clips.last)
        history.copy(first)
        history.poll()
        #expect(board.string(forType: .string) == "first")
        #expect(history.clips.map(\.text) == ["first", "second"])
        #expect(history.lastCopiedID == first.id)
        history.stop()
    }
}
