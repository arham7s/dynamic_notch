import Foundation

/// Pomodoro rhythm: 25 minutes of focus, 5 minutes of break, and a 15-minute break after
/// every fourth focus session. A value type so it can be tested without a clock.
public struct FocusCycle: Equatable, Sendable {
    public enum Phase: String, Equatable, Sendable {
        case focus
        case shortBreak
        case longBreak
    }

    public static let focusLength: TimeInterval = 25 * 60
    public static let shortBreakLength: TimeInterval = 5 * 60
    public static let longBreakLength: TimeInterval = 15 * 60
    public static let sessionsBeforeLongBreak = 4

    public private(set) var phase: Phase = .focus
    /// Focus sessions finished so far in this run.
    public private(set) var completed = 0

    public init() {}

    public var isBreak: Bool { phase != .focus }

    public var duration: TimeInterval {
        Self.duration(of: phase)
    }

    public static func duration(of phase: Phase) -> TimeInterval {
        switch phase {
        case .focus: focusLength
        case .shortBreak: shortBreakLength
        case .longBreak: longBreakLength
        }
    }

    /// Focus → break (long every fourth time) → focus → …
    public mutating func advance() {
        switch phase {
        case .focus:
            completed += 1
            phase = completed % Self.sessionsBeforeLongBreak == 0 ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            phase = .focus
        }
    }

    /// Short label for the timer views.
    public static func title(_ phase: Phase) -> String {
        switch phase {
        case .focus: String(localized: "Focus")
        case .shortBreak: String(localized: "Break")
        case .longBreak: String(localized: "Long Break")
        }
    }

    public static func symbol(_ phase: Phase) -> String {
        switch phase {
        case .focus: "brain.head.profile"
        case .shortBreak, .longBreak: "cup.and.saucer.fill"
        }
    }
}
