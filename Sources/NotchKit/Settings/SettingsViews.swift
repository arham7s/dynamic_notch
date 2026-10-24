import AppKit
import ServiceManagement
import SwiftUI

/// Coloured rounded-square icon used by System Settings rows.
private struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color.gradient))
    }
}

private struct IconToggle: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    let symbol: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                SettingsIcon(symbol: symbol, color: color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: General

struct GeneralSettingsView: View {
    @Bindable var settings: SettingsStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var needsApproval = SMAppService.mainApp.status == .requiresApproval
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if needsApproval {
                    HStack {
                        Text("Allow Dynamic Notch in Login Items to finish.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                            .controlSize(.small)
                    }
                }
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Toggle("Show in menu bar", isOn: $settings.showMenuBarIcon)
                Picker("Display", selection: $settings.display) {
                    Text("Automatic").tag(DisplayChoice.automatic)
                    Text("Main display").tag(DisplayChoice.main)
                }
            } footer: {
                Text("Automatic uses the built-in display when it has a notch. When the menu bar icon is hidden, open Dynamic Notch again from Applications to get back here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Show when idle", isOn: $settings.showWhenIdle)
                Toggle("Expand on hover", isOn: $settings.expandOnHover)
                Toggle("Collapse when the pointer leaves", isOn: $settings.collapseOnPointerExit)
                Toggle("Liquid animations", isOn: $settings.liquidAnimations)
                Toggle("Haptic feedback", isOn: $settings.hapticsEnabled)
            }

            Section("Timer") {
                Toggle("Play a sound when a timer ends", isOn: $settings.timerSound)
            }
        }
        .formStyle(.grouped)
        // The switch can also change in System Settings; pick that up whenever the tab shows.
        .onAppear { syncLaunchAtLogin() }
    }

    private func syncLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        needsApproval = status == .requiresApproval
        let enabled = status == .enabled || status == .requiresApproval
        if launchAtLogin != enabled {
            launchAtLogin = enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let status = SMAppService.mainApp.status
        let isOn = status == .enabled || status == .requiresApproval
        guard enabled != isOn else { return }
        defer { needsApproval = SMAppService.mainApp.status == .requiresApproval }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            launchError = String(localized: "Couldn’t change this setting: \(error.localizedDescription)")
            let actual = SMAppService.mainApp.status == .enabled
            if actual != enabled {
                launchAtLogin = actual
            }
        }
    }
}

// MARK: Appearance

struct AppearanceSettingsView: View {
    @Bindable var settings: SettingsStore
    /// Read live, so the ranges follow display changes while the window is open.
    let model: IslandModel

    private var screen: ScreenMetrics { model.screen }

    var body: some View {
        Form {
            Section {
                Picker("Style", selection: $settings.appearance.style) {
                    Text("Notch").tag(NotchStyle.notch)
                    Text("Floating pill").tag(NotchStyle.island)
                }
                .pickerStyle(.segmented)
                Toggle("Pitch black", isOn: $settings.appearance.pitchBlack)
            } footer: {
                Text(settings.appearance.style == .notch
                    ? "The notch itself grows to show what’s happening. Pitch black removes the shadow and outline so the extension is indistinguishable from the notch."
                    : "A separate pill floats below the notch. Pitch black removes its shadow and outline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Size", selection: $settings.appearance.size) {
                    Text("Small").tag(NotchSize.small)
                    Text("Medium").tag(NotchSize.medium)
                    Text("Large").tag(NotchSize.large)
                }
                .pickerStyle(.segmented)
                slider("Width", value: $settings.appearance.width, range: NotchAppearance.widthRange, step: 2)
                slider("Thickness", value: $settings.appearance.height, range: NotchAppearance.heightRange, step: 1)
            } header: {
                Text("Size")
            } footer: {
                Text(settings.appearance.style == .notch && screen.hasNotch
                    ? "Size scales everything the notch shows. Width and thickness fine-tune the compact shape; thickness never goes below the height of the notch."
                    : "Size scales everything the pill shows. Width and thickness fine-tune the compact pill.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                slider("Vertical offset", value: $settings.appearance.verticalOffset, range: NotchAppearance.verticalOffsetRange, step: 1)
                slider("Horizontal offset", value: $settings.appearance.horizontalOffset, range: horizontalRange, step: 2)
            } header: {
                Text("Position")
            } footer: {
                Text(settings.appearance.style == .notch
                    ? "Position applies to the floating pill. In notch style the shape always grows from the notch."
                    : "Negative vertical offsets pull the pill up into the notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(settings.appearance.style == .notch)

            Section {
                HStack {
                    Text("The shape stays visible while this tab is open, so you can see each change.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Defaults") { settings.resetAppearance() }
                        .disabled(settings.appearance == .standard)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var horizontalRange: ClosedRange<Double> {
        let half = max(40, Double(screen.size.width) / 2 - 300)
        return -half...half
    }

    /// Continuous slider (a stepped one draws a tick per step) that stores rounded values.
    private func slider(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        let rounded = Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = (($0 / step).rounded() * step) }
        )
        return LabeledContent {
            HStack(spacing: 10) {
                Slider(value: rounded, in: range)
                    .frame(minWidth: 200)
                Text("\(Int(value.wrappedValue.rounded())) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}

// MARK: Activities

struct ActivitiesSettingsView: View {
    @Bindable var settings: SettingsStore
    let nowPlaying: NowPlayingService

    var body: some View {
        Form {
            Section("Live Activities") {
                IconToggle(title: "Now Playing", detail: "Music, podcasts and video from any app", symbol: "music.note", color: .pink, isOn: $settings.nowPlayingEnabled)
                if !nowPlaying.isAvailable {
                    Text("Now Playing isn’t available on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                IconToggle(title: "Timer", detail: "Start one from the pill or the menu bar", symbol: "timer", color: .orange, isOn: $settings.timerEnabled)
                IconToggle(title: "Calls & Microphone", detail: "FaceTime, Zoom, Meet and any app using the mic", symbol: "phone.fill", color: .green, isOn: $settings.callsEnabled)
                IconToggle(title: "AirDrop", detail: "Drag files to the notch to send them", symbol: "dot.radiowaves.up.forward", color: .blue, isOn: $settings.airDropEnabled)
            }

            Section("Alerts") {
                IconToggle(title: "Charging", detail: nil, symbol: "bolt.fill", color: .green, isOn: $settings.chargingAlertsEnabled)
                IconToggle(title: "Low Battery", detail: "At 20% and 10%", symbol: "battery.25percent", color: .red, isOn: $settings.lowBatteryAlertsEnabled)
                IconToggle(title: "Headphones", detail: "When AirPods or other Bluetooth headphones connect", symbol: "airpodspro", color: .gray, isOn: $settings.headphoneAlertsEnabled)
                IconToggle(title: "Volume & Brightness", detail: "Shows the level in the notch when you change it", symbol: "speaker.wave.2.fill", color: .indigo, isOn: $settings.levelsEnabled)
            }

            Section {
                Picker("Keep paused media for", selection: $settings.pausedMediaLinger) {
                    ForEach(SettingsStore.lingerChoices, id: \.self) { seconds in
                        Text(Self.label(for: seconds)).tag(seconds)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private static func label(for seconds: TimeInterval) -> String {
        seconds < 60 ? "\(Int(seconds)) seconds" : (seconds == 60 ? "1 minute" : "\(Int(seconds / 60)) minutes")
    }
}

// MARK: Home

struct HomeSettingsView: View {
    @Bindable var settings: SettingsStore
    let calendar: CalendarService
    let shortcuts: ShortcutsService

    var body: some View {
        Form {
            Section {
                IconToggle(title: "File Tray", detail: "Drop files on the notch to keep them for later", symbol: "tray.full.fill", color: .cyan, isOn: $settings.trayEnabled)
                IconToggle(title: "Clipboard History", detail: "The last 20 texts you copied, in the Tray. Kept in memory only, never saved; skips passwords.", symbol: "doc.on.clipboard.fill", color: .teal, isOn: $settings.clipboardHistoryEnabled)
                    .disabled(!settings.trayEnabled)
                IconToggle(title: "Mirror", detail: "A quick camera preview before calls", symbol: "person.crop.square.fill", color: .purple, isOn: $settings.mirrorEnabled)
            } header: {
                Text("Tabs")
            } footer: {
                Text("Click the notch to open Home. Tray and Mirror appear as tabs next to it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                IconToggle(title: "Calendar", detail: "Your next event, and a heads-up 5 minutes before it", symbol: "calendar", color: .red, isOn: $settings.calendarEnabled)
                if settings.calendarEnabled {
                    LabeledContent("Access") {
                        switch calendar.access {
                        case .granted:
                            Text("Allowed").foregroundStyle(.secondary)
                        case .notAsked:
                            Button("Connect Calendar") { calendar.requestAccess() }
                        case .denied:
                            Button("Open Privacy Settings") { calendar.openPrivacySettings() }
                        }
                    }
                }
            } header: {
                Text("Calendar")
            }

            Section {
                IconToggle(title: "Shortcuts", detail: "Run your favourite shortcuts from Home", symbol: "bolt.fill", color: .blue, isOn: $settings.shortcutsEnabled)
                if settings.shortcutsEnabled {
                    if !shortcuts.isSupported {
                        Text("The Shortcuts app isn't available on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if shortcuts.isLoading && shortcuts.available.isEmpty {
                        ProgressView().controlSize(.small)
                    } else if shortcuts.available.isEmpty {
                        Text("You don't have any shortcuts yet. Make some in the Shortcuts app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(shortcuts.available, id: \.self) { name in
                            let isFavorite = settings.favoriteShortcuts.contains(name)
                            Toggle(name, isOn: Binding(
                                get: { isFavorite },
                                set: { _ in settings.toggleFavorite(name) }
                            ))
                            .disabled(!isFavorite && settings.favoriteShortcuts.count >= SettingsStore.maximumFavoriteShortcuts)
                        }
                    }
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Pick up to \(SettingsStore.maximumFavoriteShortcuts) to show in Home.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { shortcuts.reload() }
    }
}

// MARK: About

struct AboutSettingsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Dynamic Notch")
                .font(.system(size: 22, weight: .semibold))
            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Live activities for your Mac’s notch.")
                .font(.callout)
                .padding(.top, 4)
            if let copyright = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String {
                Text(copyright)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
