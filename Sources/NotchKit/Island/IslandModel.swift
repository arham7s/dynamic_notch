import AppKit
import Observation
import os

/// The single source of truth for what the pill shows and how it reacts.
@MainActor
@Observable
public final class IslandModel {
    public let settings: SettingsStore
    public let nowPlaying: NowPlayingService
    public let timer: TimerService
    public let calls: CallMonitor
    public let power: PowerMonitor
    public let audioRoute: AudioRouteMonitor
    public let tray: TrayStore
    public let calendar: CalendarService
    public let shortcuts: ShortcutsService
    public let levels: LevelMonitor
    public let clipboard: ClipboardHistory
    let camera = CameraAccess()

    public var screen: ScreenMetrics = .sample
    public private(set) var alerts = AlertQueue()
    public private(set) var expandTarget: ExpandTarget?
    public private(set) var preferredPrimary: ActivityKind?
    public private(set) var isHoveringPill = false
    public private(set) var isHoveringNotch = false
    public private(set) var isFileDragNear = false
    public var isDropTargeted = false
    /// Which half of the drop target the files are over.
    public private(set) var targetedZone: DropZone?
    /// True while the user drags a file out of the tray, so it isn't mistaken for a new drop.
    public var isDraggingFromTray = false

    public enum DropZone: Sendable, Equatable {
        case tray
        case airDrop
    }
    /// True while the Appearance settings are open, so the pill shows for live preview.
    public var isPreviewing = false

    /// Asks the app to open the settings window.
    @ObservationIgnored public var onOpenSettings: (() -> Void)?

    @ObservationIgnored private let alarm = AlarmSound()
    /// Kept alive while the focus chime plays.
    @ObservationIgnored private var chime: NSSound?
    @ObservationIgnored private var alertTask: Task<Void, Never>?
    @ObservationIgnored private var collapseTask: Task<Void, Never>?
    @ObservationIgnored private var hoverExpandTask: Task<Void, Never>?
    /// Auto-collapse only starts once the pointer has been inside the expanded pill, so opening
    /// it from the menu bar doesn't collapse it while the pointer travels over.
    @ObservationIgnored private var pointerEnteredExpanded = false
    @ObservationIgnored private let log = Logger(subsystem: Log.subsystem, category: "island")

    public init(
        settings: SettingsStore,
        nowPlaying: NowPlayingService = NowPlayingService(),
        timer: TimerService = TimerService(),
        calls: CallMonitor = CallMonitor(),
        power: PowerMonitor = PowerMonitor(),
        audioRoute: AudioRouteMonitor = AudioRouteMonitor(),
        tray: TrayStore = TrayStore(),
        calendar: CalendarService = CalendarService(),
        shortcuts: ShortcutsService = ShortcutsService(),
        levels: LevelMonitor = LevelMonitor(),
        clipboard: ClipboardHistory = ClipboardHistory()
    ) {
        self.settings = settings
        self.nowPlaying = nowPlaying
        self.timer = timer
        self.calls = calls
        self.power = power
        self.audioRoute = audioRoute
        self.tray = tray
        self.calendar = calendar
        self.shortcuts = shortcuts
        self.levels = levels
        self.clipboard = clipboard

        calendar.onReminder = { [weak self] event in
            guard let self, self.settings.calendarEnabled else { return }
            let minutes = max(0, Int((event.start.timeIntervalSinceNow / 60).rounded()))
            self.receive(.upcomingEvent(title: event.title, minutes: minutes, meetingURL: event.meetingURL))
        }
        shortcuts.onFinish = { [weak self] name, succeeded in
            self?.receive(.shortcut(name: name, succeeded: succeeded))
        }
        levels.onChange = { [weak self] kind, value, muted in
            guard let self, self.settings.levelsEnabled else { return }
            // While an expanded view is open, it stays put; the system indicator still shows.
            guard self.expandTarget == nil else { return }
            self.receive(.level(kind, value: value, muted: muted))
        }

        timer.onFinish = { [weak self] in self?.timerDidFinish() }
        power.onAlert = { [weak self] alert in self?.receive(alert) }
        audioRoute.onAlert = { [weak self] alert in self?.receive(alert) }
        nowPlaying.lingerDuration = settings.pausedMediaLinger
        observeActivities()
        observeSettings()
    }

    public func startServices() {
        nowPlaying.start()
        calls.start()
        power.start()
        audioRoute.start()
        calendar.start()
        levels.start()
        updateClipboardWatching()
        if !settings.hasShownWelcome {
            settings.hasShownWelcome = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.receive(.welcome)
            }
        }
    }

    public func stopServices() {
        nowPlaying.stop()
        calls.stop()
        power.stop()
        audioRoute.stop()
        calendar.stop()
        levels.stop()
        clipboard.stop()
        alarm.stop()
    }

    // MARK: Derived state

    public var engine: LayoutEngine {
        LayoutEngine(screen: screen, appearance: settings.appearance)
    }

    public var activeActivities: Set<ActivityKind> {
        var active = Set<ActivityKind>()
        if settings.callsEnabled, calls.session != nil { active.insert(.call) }
        if settings.timerEnabled, timer.isActive { active.insert(.timer) }
        if settings.nowPlayingEnabled, nowPlaying.isActivityVisible { active.insert(.nowPlaying) }
        return active
    }

    public var presentation: IslandPresentation {
        PresentationResolver.resolve(PresentationInput(
            activeActivities: activeActivities,
            preferredPrimary: preferredPrimary,
            alert: alerts.current,
            expandTarget: expandTarget,
            isFileDragNear: acceptsFileDrops && isFileDragNear,
            isDropTargeted: acceptsFileDrops && isDropTargeted,
            showWhenIdle: settings.showWhenIdle,
            isHoveringNotch: isHoveringNotch,
            isPreviewing: isPreviewing
        ))
    }

    public var homeHasMedia: Bool {
        settings.nowPlayingEnabled && nowPlaying.info?.hasContent == true
    }

    /// Files can be dropped on the notch when at least one destination is on.
    public var acceptsFileDrops: Bool {
        settings.airDropEnabled || settings.trayEnabled
    }

    /// The calendar row shows the next event, or a button to connect the calendar.
    public var showsCalendarRow: Bool {
        guard settings.calendarEnabled else { return false }
        switch calendar.access {
        case .notAsked: return true
        case .granted: return calendar.nextEvent != nil
        case .denied: return false
        }
    }

    public var favoriteShortcuts: [String] {
        guard settings.shortcutsEnabled else { return [] }
        return settings.favoriteShortcuts
    }

    public var homeContent: HomeContent {
        HomeContent(
            hasMedia: homeHasMedia,
            hasEvent: showsCalendarRow,
            hasTimer: settings.timerEnabled,
            hasShortcuts: !favoriteShortcuts.isEmpty
        )
    }

    /// Tabs shown at the top of the Home view.
    public var homeTabs: [HomeTab] {
        var tabs: [HomeTab] = [.home]
        if settings.trayEnabled { tabs.append(.tray) }
        if settings.mirrorEnabled { tabs.append(.mirror) }
        return tabs
    }

    public var layout: IslandLayout {
        engine.layout(for: presentation, home: homeContent, hovering: isHoveringPill)
    }

    // MARK: Pointer

    /// Updates hover state for a pointer position in window coordinates. Returns whether the
    /// window should receive mouse events there.
    @discardableResult
    public func pointerMoved(to point: CGPoint?) -> Bool {
        let current = presentation
        let engine = engine
        let resting = engine.layout(for: current, home: homeContent, hovering: false)
        let inside = point.map { point in
            engine.interactiveRects(for: current, layout: resting).contains { $0.contains(point) }
        } ?? false

        if case .hidden = current {
            setHovering(pill: false, notch: inside)
        } else {
            setHovering(pill: inside, notch: false)
        }

        if current.isExpandedFamily {
            if inside {
                pointerEnteredExpanded = true
                collapseTask?.cancel()
                collapseTask = nil
            } else if pointerEnteredExpanded, settings.collapseOnPointerExit, expandTarget != nil {
                scheduleCollapse()
            }
        }

        if settings.expandOnHover, inside, case .compact(let primary, _) = current {
            scheduleHoverExpand(.activity(primary))
        } else if settings.expandOnHover, inside, case .hidden = current {
            scheduleHoverExpand(.home)
        } else if !inside {
            hoverExpandTask?.cancel()
            hoverExpandTask = nil
        }

        return inside || isFileDragNear
    }

    private func setHovering(pill: Bool, notch: Bool) {
        if isHoveringPill != pill { isHoveringPill = pill }
        if isHoveringNotch != notch { isHoveringNotch = notch }
    }

    /// A click anywhere outside the pill.
    public func outsideClick() {
        if expandTarget != nil {
            collapse()
        }
    }

    // MARK: Taps and gestures

    public func tapPill() {
        switch presentation {
        case .hidden, .idle:
            expand(.home)
        case .compact(let primary, _):
            expand(.activity(primary))
        case .alert(let alert) where alert != .timerFinished:
            dismissAlert()
        default:
            break
        }
    }

    public func tapBubble() {
        if case .compact(_, let secondary?) = presentation {
            expand(.activity(secondary))
        }
    }

    public func expand(_ target: ExpandTarget) {
        hoverExpandTask?.cancel()
        collapseTask?.cancel()
        collapseTask = nil
        pointerEnteredExpanded = isHoveringPill
        if expandTarget != target {
            expandTarget = target
            Haptics.perform(enabled: settings.hapticsEnabled)
        }
    }

    public func collapse() {
        collapseTask?.cancel()
        collapseTask = nil
        pointerEnteredExpanded = false
        guard expandTarget != nil else { return }
        expandTarget = nil
        pumpAlerts()
    }

    /// Two-finger swipe: bring the next activity to the front.
    public func cyclePrimary(forward: Bool) {
        let active = activeActivities
        let current = PresentationResolver.ordered(active, preferred: preferredPrimary).first
        guard let next = PresentationResolver.nextPrimary(active, current: current, forward: forward) else { return }
        preferredPrimary = next
        Haptics.perform(enabled: settings.hapticsEnabled)
    }

    private func scheduleCollapse() {
        guard collapseTask == nil else { return }
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, let self else { return }
            self.collapseTask = nil
            if !self.isHoveringPill {
                self.collapse()
            }
        }
    }

    private func scheduleHoverExpand(_ target: ExpandTarget) {
        guard hoverExpandTask == nil else { return }
        hoverExpandTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self else { return }
            self.hoverExpandTask = nil
            switch (target, self.presentation) {
            case (.activity(let kind), .compact(let primary, _)) where self.isHoveringPill && primary == kind:
                self.expand(target)
            case (.home, .hidden) where self.isHoveringNotch:
                self.expand(.home)
                self.pointerEnteredExpanded = true
            default:
                break
            }
        }
    }

    // MARK: Alerts

    public func receive(_ alert: IslandAlert) {
        guard isEnabled(alert) else { return }
        if alerts.enqueue(alert, now: Date()) {
            scheduleAlertExpiry()
        }
        pumpAlerts()
    }

    public func dismissAlert() {
        if alerts.current == .timerFinished {
            stopTimerAlarm()
            return
        }
        alerts.dismissCurrent()
        pumpAlerts()
        scheduleAlertExpiry()
    }

    private func isEnabled(_ alert: IslandAlert) -> Bool {
        switch alert {
        case .charging: settings.chargingAlertsEnabled
        case .lowBattery: settings.lowBatteryAlertsEnabled
        case .headphones: settings.headphoneAlertsEnabled
        case .level: settings.levelsEnabled
        case .upcomingEvent: settings.calendarEnabled
        case .timerFinished, .focusPhase, .welcome, .shortcut: true
        }
    }

    private func pumpAlerts() {
        if alerts.promote(now: Date(), allowNonUrgent: expandTarget == nil) {
            scheduleAlertExpiry()
        }
    }

    private func scheduleAlertExpiry() {
        alertTask?.cancel()
        alertTask = nil
        guard let expiry = alerts.expiry else { return }
        let delay = max(0, expiry.timeIntervalSinceNow)
        alertTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            let wasTimer = self.alerts.current == .timerFinished
            let removed = self.alerts.expire(now: Date())
            self.alertTask = nil
            if removed {
                if wasTimer {
                    // Nobody stopped it: clear the finished timer along with its alert.
                    self.alarm.stop()
                    self.timer.cancel()
                }
                self.pumpAlerts()
            }
            // Covers a wake-up before the deadline (for example after a clock change).
            if self.alertTask == nil {
                self.scheduleAlertExpiry()
            }
        }
    }

    // MARK: Timer

    public func startTimer(_ duration: TimeInterval) {
        stopAlarmIfNeeded()
        timer.start(duration: duration)
        collapse()
    }

    public func cancelTimer() {
        timer.cancel()
    }

    /// Starts a Pomodoro run: 25 min focus, 5 min breaks, a long break every fourth session.
    public func startFocus() {
        stopAlarmIfNeeded()
        timer.startFocus()
        collapse()
    }

    /// Opens an event's video call and closes the notch.
    public func joinMeeting(_ url: URL) {
        NSWorkspace.shared.open(url)
        alerts.removeAll(of: .calendar)
        collapse()
        pumpAlerts()
        scheduleAlertExpiry()
    }

    private func timerDidFinish() {
        // A focus run rolls straight into its next phase with one chime instead of the alarm.
        if timer.focus != nil, let next = timer.advanceFocus() {
            if settings.timerSound {
                chime?.stop()
                chime = NSSound(named: NSSound.Name("Glass"))
                chime?.play()
            }
            receive(.focusPhase(next.phase, completed: next.completed))
            return
        }
        receive(.timerFinished)
        if settings.timerSound {
            alarm.start()
        }
    }

    /// "Stop" on the timer-done alert.
    public func stopTimerAlarm() {
        alarm.stop()
        timer.cancel()
        alerts.removeAll(of: .timer)
        pumpAlerts()
        scheduleAlertExpiry()
    }

    /// "Repeat" on the timer-done alert.
    public func repeatTimer() {
        alarm.stop()
        alerts.removeAll(of: .timer)
        timer.repeatLast()
        pumpAlerts()
        scheduleAlertExpiry()
    }

    private func stopAlarmIfNeeded() {
        if alerts.current == .timerFinished || alerts.pending.contains(.timerFinished) {
            alarm.stop()
            alerts.removeAll(of: .timer)
            pumpAlerts()
        }
    }

    // MARK: AirDrop

    public func fileDragChanged(isDragging: Bool, at point: CGPoint?) {
        if !isDragging {
            isDraggingFromTray = false
        }
        let near = acceptsFileDrops && isDragging && !isDraggingFromTray
            && (point.map { engine.dropZone.contains($0) } ?? false)
        if near != isFileDragNear {
            isFileDragNear = near
        }
        if !isDragging, isDropTargeted {
            setTargeted(nil, true)
        }
    }

    /// Called by each half of the drop target as files move over it.
    public func setTargeted(_ zone: DropZone?, _ targeted: Bool) {
        if targeted {
            targetedZone = zone
        } else if zone == nil || targetedZone == zone {
            targetedZone = nil
        }
        let any = targetedZone != nil
        if isDropTargeted != any { isDropTargeted = any }
    }

    /// Keeps dropped files in the tray and shows them.
    @discardableResult
    public func addToTray(_ urls: [URL]) -> Int {
        isFileDragNear = false
        setTargeted(nil, false)
        let added = tray.add(urls)
        if added > 0 {
            Haptics.perform(enabled: settings.hapticsEnabled)
            expand(.tray)
            pointerEnteredExpanded = true
        } else {
            NSSound.beep()
        }
        return added
    }

    public func showTab(_ tab: HomeTab) {
        if tab == .tray { tray.pruneMissing() }
        if tab == .mirror { camera.refresh() }
        expand(ExpandTarget(tab))
    }

    /// Sends dropped files with AirDrop. Returns false if AirDrop can't take them.
    @discardableResult
    public func airDrop(_ urls: [URL]) -> Bool {
        isFileDragNear = false
        setTargeted(nil, false)
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            log.notice("AirDrop is not available for the dropped items")
            NSSound.beep()
            return false
        }
        Haptics.perform(enabled: settings.hapticsEnabled)
        NSApp.activate()
        service.perform(withItems: urls)
        return true
    }

    // MARK: Clipboard

    /// Copies a remembered clip back to the clipboard.
    public func copyClip(_ clip: ClipboardHistory.Clip) {
        clipboard.copy(clip)
        Haptics.perform(enabled: settings.hapticsEnabled)
    }

    /// Clipboard history needs both the Tray and its own switch; turning either off forgets it.
    private func updateClipboardWatching() {
        if settings.trayEnabled && settings.clipboardHistoryEnabled {
            clipboard.start()
        } else if clipboard.isRunning || !clipboard.clips.isEmpty {
            clipboard.stop()
        }
    }

    // MARK: Observation

    /// Clears choices that point at activities which have ended, so they don't come back
    /// expanded the next time the activity starts.
    private func observeActivities() {
        withObservationTracking {
            _ = activeActivities
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reconcile()
                self.observeActivities()
            }
        }
    }

    private func reconcile() {
        let active = activeActivities
        if case .activity(let kind) = expandTarget, !active.contains(kind) {
            expandTarget = nil
            pumpAlerts()
        }
        if let preferredPrimary, !active.contains(preferredPrimary) {
            self.preferredPrimary = nil
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.pausedMediaLinger
            _ = settings.airDropEnabled
            _ = settings.trayEnabled
            _ = settings.mirrorEnabled
            _ = settings.clipboardHistoryEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.nowPlaying.lingerDuration = self.settings.pausedMediaLinger
                if !self.acceptsFileDrops {
                    self.isFileDragNear = false
                    self.setTargeted(nil, false)
                }
                if case .tray = self.expandTarget, !self.settings.trayEnabled { self.collapse() }
                if case .mirror = self.expandTarget, !self.settings.mirrorEnabled { self.collapse() }
                self.updateClipboardWatching()
                self.observeSettings()
            }
        }
    }
}
