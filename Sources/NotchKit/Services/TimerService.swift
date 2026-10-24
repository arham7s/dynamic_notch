import AppKit
import Observation

@MainActor
@Observable
public final class TimerService {
    public private(set) var timer: CountdownTimer?
    /// Duration of the last timer started, used by "Repeat".
    public private(set) var lastDuration: TimeInterval?
    /// Set while a focus (Pomodoro) run is going; nil for a plain timer.
    public private(set) var focus: FocusCycle?

    /// Quick starts shown in the pill, beside the Focus chip.
    public static let presets: [TimeInterval] = [60, 300, 600, 900]
    /// Quick starts shown in the menu bar menu, which has more room.
    public static let menuPresets: [TimeInterval] = [60, 180, 300, 600, 900, 1800, 3600]

    /// Called once when a running timer reaches zero.
    @ObservationIgnored public var onFinish: (() -> Void)?
    @ObservationIgnored private var completionTask: Task<Void, Never>?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
        // A timer that ran out while the Mac slept should ring as soon as it wakes.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkCompletion() }
        }
    }

    /// Running or paused; a finished timer is shown by its alert instead.
    public var isActive: Bool {
        guard let timer else { return false }
        return !timer.isFinished
    }

    /// Starts a plain timer, ending any focus run.
    public func start(duration: TimeInterval) {
        focus = nil
        begin(duration: duration)
    }

    /// Starts a focus run with its first 25-minute session.
    public func startFocus() {
        let cycle = FocusCycle()
        focus = cycle
        begin(duration: cycle.duration)
    }

    /// Moves a finished focus phase on to the next one and starts it.
    @discardableResult
    public func advanceFocus() -> FocusCycle? {
        guard var cycle = focus else { return nil }
        cycle.advance()
        focus = cycle
        begin(duration: cycle.duration)
        return cycle
    }

    private func begin(duration: TimeInterval) {
        let started = CountdownTimer(duration: duration, now: now())
        timer = started
        lastDuration = started.duration
        scheduleCompletion()
    }

    public func pause() {
        timer?.pause(now: now())
        scheduleCompletion()
    }

    public func resume() {
        timer?.resume(now: now())
        scheduleCompletion()
    }

    public func togglePause() {
        guard let timer else { return }
        if timer.isPaused { resume() } else { pause() }
    }

    public func add(_ seconds: TimeInterval) {
        timer?.add(seconds, now: now())
        scheduleCompletion()
    }

    public func cancel() {
        timer = nil
        focus = nil
        scheduleCompletion()
    }

    public func repeatLast() {
        guard let lastDuration else { return }
        start(duration: lastDuration)
    }

    /// Checks the clock; called by the scheduled task and safe to call at any time.
    public func checkCompletion() {
        guard var current = timer, current.finishIfDue(now: now()) else { return }
        timer = current
        scheduleCompletion()
        onFinish?()
    }

    private func scheduleCompletion() {
        completionTask?.cancel()
        completionTask = nil
        guard let timer, timer.isRunning else {
            endActivity()
            return
        }
        beginActivity()
        let delay = timer.remaining(at: now())
        completionTask = Task { [weak self] in
            // A tight tolerance: by default the system may fire long sleeps many seconds late.
            try? await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(20))
            guard !Task.isCancelled else { return }
            self?.checkCompletion()
        }
    }

    /// Keeps App Nap from delaying the alarm.
    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Timer running"
        )
    }

    private func endActivity() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
    }
}

/// Plays the timer-done sound a few times, like the Clock app.
@MainActor
final class AlarmSound {
    private var task: Task<Void, Never>?
    private var sound: NSSound?

    func start() {
        stop()
        task = Task { [weak self] in
            let started = Date()
            while !Task.isCancelled, Date().timeIntervalSince(started) < 30 {
                self?.playOnce()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        sound?.stop()
        sound = nil
    }

    private func playOnce() {
        sound?.stop()
        sound = NSSound(named: NSSound.Name("Glass"))
        sound?.play()
    }
}

enum Haptics {
    @MainActor
    static func perform(enabled: Bool) {
        guard enabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
