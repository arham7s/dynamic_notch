import Foundation
import Observation

public enum DisplayChoice: String, CaseIterable, Sendable, Identifiable {
    /// The built-in display if it has a notch, otherwise the main display.
    case automatic
    /// The display that holds the menu bar.
    case main

    public var id: String { rawValue }
}

/// User preferences, saved to UserDefaults as soon as they change.
@MainActor
@Observable
public final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults

    public var appearance: NotchAppearance {
        didSet {
            // The layout engine clamps too, so out-of-range values can never reach the screen.
            let value = appearance.clamped()
            defaults.set(value.style.rawValue, forKey: Key.style)
            defaults.set(value.pitchBlack, forKey: Key.pitchBlack)
            defaults.set(value.size.rawValue, forKey: Key.size)
            defaults.set(value.width, forKey: Key.width)
            defaults.set(value.height, forKey: Key.height)
            defaults.set(value.verticalOffset, forKey: Key.verticalOffset)
            defaults.set(value.horizontalOffset, forKey: Key.horizontalOffset)
        }
    }

    public var showWhenIdle: Bool { didSet { defaults.set(showWhenIdle, forKey: Key.showWhenIdle) } }
    public var expandOnHover: Bool { didSet { defaults.set(expandOnHover, forKey: Key.expandOnHover) } }
    public var collapseOnPointerExit: Bool { didSet { defaults.set(collapseOnPointerExit, forKey: Key.collapseOnPointerExit) } }
    public var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Key.haptics) } }
    public var liquidAnimations: Bool { didSet { defaults.set(liquidAnimations, forKey: Key.liquid) } }
    public var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Key.menuBarIcon) } }
    public var display: DisplayChoice { didSet { defaults.set(display.rawValue, forKey: Key.display) } }
    public var timerSound: Bool { didSet { defaults.set(timerSound, forKey: Key.timerSound) } }

    public var nowPlayingEnabled: Bool { didSet { defaults.set(nowPlayingEnabled, forKey: Key.nowPlaying) } }
    public var timerEnabled: Bool { didSet { defaults.set(timerEnabled, forKey: Key.timer) } }
    public var callsEnabled: Bool { didSet { defaults.set(callsEnabled, forKey: Key.calls) } }
    public var airDropEnabled: Bool { didSet { defaults.set(airDropEnabled, forKey: Key.airDrop) } }
    public var chargingAlertsEnabled: Bool { didSet { defaults.set(chargingAlertsEnabled, forKey: Key.charging) } }
    public var lowBatteryAlertsEnabled: Bool { didSet { defaults.set(lowBatteryAlertsEnabled, forKey: Key.lowBattery) } }
    public var headphoneAlertsEnabled: Bool { didSet { defaults.set(headphoneAlertsEnabled, forKey: Key.headphones) } }
    public var trayEnabled: Bool { didSet { defaults.set(trayEnabled, forKey: Key.tray) } }
    /// Keep recent copied text in the Tray. Off by default; held in memory only.
    public var clipboardHistoryEnabled: Bool { didSet { defaults.set(clipboardHistoryEnabled, forKey: Key.clipboardHistory) } }
    public var mirrorEnabled: Bool { didSet { defaults.set(mirrorEnabled, forKey: Key.mirror) } }
    public var calendarEnabled: Bool { didSet { defaults.set(calendarEnabled, forKey: Key.calendar) } }
    public var shortcutsEnabled: Bool { didSet { defaults.set(shortcutsEnabled, forKey: Key.shortcuts) } }
    /// Shortcut names pinned to the Home tab, in order.
    public var favoriteShortcuts: [String] { didSet { defaults.set(favoriteShortcuts, forKey: Key.favoriteShortcuts) } }
    /// Show volume and brightness changes in the notch.
    public var levelsEnabled: Bool { didSet { defaults.set(levelsEnabled, forKey: Key.levels) } }

    public static let maximumFavoriteShortcuts = 4

    /// Set after the first-launch hint has been shown.
    public var hasShownWelcome: Bool { didSet { defaults.set(hasShownWelcome, forKey: Key.welcome) } }
    /// How long a paused track stays in the pill.
    public var pausedMediaLinger: TimeInterval { didSet { defaults.set(pausedMediaLinger, forKey: Key.linger) } }

    public static let lingerChoices: [TimeInterval] = [10, 30, 60, 300]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let standard = NotchAppearance.standard
        appearance = NotchAppearance(
            style: defaults.string(forKey: Key.style).flatMap(NotchStyle.init(rawValue:)) ?? standard.style,
            width: defaults.object(forKey: Key.width) as? Double ?? standard.width,
            height: defaults.object(forKey: Key.height) as? Double ?? standard.height,
            verticalOffset: defaults.object(forKey: Key.verticalOffset) as? Double ?? standard.verticalOffset,
            horizontalOffset: defaults.object(forKey: Key.horizontalOffset) as? Double ?? standard.horizontalOffset,
            pitchBlack: defaults.object(forKey: Key.pitchBlack) as? Bool ?? standard.pitchBlack,
            size: defaults.string(forKey: Key.size).flatMap(NotchSize.init(rawValue:)) ?? standard.size
        ).clamped()
        showWhenIdle = defaults.object(forKey: Key.showWhenIdle) as? Bool ?? false
        expandOnHover = defaults.object(forKey: Key.expandOnHover) as? Bool ?? false
        collapseOnPointerExit = defaults.object(forKey: Key.collapseOnPointerExit) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        liquidAnimations = defaults.object(forKey: Key.liquid) as? Bool ?? true
        showMenuBarIcon = defaults.object(forKey: Key.menuBarIcon) as? Bool ?? true
        display = (defaults.string(forKey: Key.display)).flatMap(DisplayChoice.init(rawValue:)) ?? .automatic
        timerSound = defaults.object(forKey: Key.timerSound) as? Bool ?? true
        nowPlayingEnabled = defaults.object(forKey: Key.nowPlaying) as? Bool ?? true
        timerEnabled = defaults.object(forKey: Key.timer) as? Bool ?? true
        callsEnabled = defaults.object(forKey: Key.calls) as? Bool ?? true
        airDropEnabled = defaults.object(forKey: Key.airDrop) as? Bool ?? true
        chargingAlertsEnabled = defaults.object(forKey: Key.charging) as? Bool ?? true
        lowBatteryAlertsEnabled = defaults.object(forKey: Key.lowBattery) as? Bool ?? true
        headphoneAlertsEnabled = defaults.object(forKey: Key.headphones) as? Bool ?? true
        hasShownWelcome = defaults.bool(forKey: Key.welcome)
        trayEnabled = defaults.object(forKey: Key.tray) as? Bool ?? true
        clipboardHistoryEnabled = defaults.object(forKey: Key.clipboardHistory) as? Bool ?? false
        mirrorEnabled = defaults.object(forKey: Key.mirror) as? Bool ?? true
        calendarEnabled = defaults.object(forKey: Key.calendar) as? Bool ?? true
        shortcutsEnabled = defaults.object(forKey: Key.shortcuts) as? Bool ?? true
        favoriteShortcuts = Array((defaults.stringArray(forKey: Key.favoriteShortcuts) ?? []).prefix(Self.maximumFavoriteShortcuts))
        levelsEnabled = defaults.object(forKey: Key.levels) as? Bool ?? true
        let linger = defaults.object(forKey: Key.linger) as? Double ?? 30
        pausedMediaLinger = Self.lingerChoices.contains(linger) ? linger : 30
    }

    /// Pins or unpins a shortcut on the Home tab. Returns false when the list is full.
    @discardableResult
    public func toggleFavorite(_ name: String) -> Bool {
        if let index = favoriteShortcuts.firstIndex(of: name) {
            favoriteShortcuts.remove(at: index)
            return true
        }
        guard favoriteShortcuts.count < Self.maximumFavoriteShortcuts else { return false }
        favoriteShortcuts.append(name)
        return true
    }

    public func resetAppearance() {
        appearance = .standard
    }

    private enum Key {
        static let style = "shape.style"
        static let pitchBlack = "shape.pitchBlack"
        static let size = "shape.size"
        static let width = "shape.width"
        static let height = "shape.height"
        static let verticalOffset = "shape.verticalOffset"
        static let horizontalOffset = "shape.horizontalOffset"
        static let showWhenIdle = "behavior.showWhenIdle"
        static let expandOnHover = "behavior.expandOnHover"
        static let collapseOnPointerExit = "behavior.collapseOnPointerExit"
        static let haptics = "behavior.haptics"
        static let liquid = "behavior.liquidAnimations"
        static let menuBarIcon = "general.showMenuBarIcon"
        static let display = "general.display"
        static let timerSound = "timer.sound"
        static let nowPlaying = "activity.nowPlaying"
        static let timer = "activity.timer"
        static let calls = "activity.calls"
        static let airDrop = "activity.airDrop"
        static let charging = "alert.charging"
        static let lowBattery = "alert.lowBattery"
        static let headphones = "alert.headphones"
        static let linger = "nowPlaying.pausedLinger"
        static let welcome = "app.hasShownWelcome"
        static let tray = "home.tray"
        static let clipboardHistory = "home.clipboardHistory"
        static let mirror = "home.mirror"
        static let calendar = "home.calendar"
        static let shortcuts = "home.shortcuts"
        static let favoriteShortcuts = "home.favoriteShortcuts"
        static let levels = "alert.levels"
    }
}
