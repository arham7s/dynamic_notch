import SwiftUI
import UniformTypeIdentifiers

// The Home, Tray and Mirror tabs share one fixed-size nook (IslandMetrics.Nook): wide and short,
// widgets side by side. In notch style the tab header sits in the strip beside the camera.

// MARK: Container

struct NookContainer<Content: View>: View {
    let model: IslandModel
    let tab: HomeTab
    /// Width of the camera in the middle of the strip (notch style), 0 otherwise.
    let cameraGap: CGFloat
    /// Height of the strip beside the camera (notch style), 0 for the floating pill.
    let stripHeight: CGFloat
    @ViewBuilder var content: Content
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(spacing: 0) {
            if stripHeight > 0 {
                HStack(spacing: 0) {
                    NookTabs(model: model, selected: tab)
                    Spacer(minLength: cameraGap + 12 * s)
                    NookStatus(model: model)
                }
                .frame(height: stripHeight)
                .padding(.bottom, IslandMetrics.notchContentGap)
            } else {
                HStack(spacing: 0) {
                    NookTabs(model: model, selected: tab)
                    Spacer(minLength: 8 * s)
                    NookStatus(model: model)
                }
                .frame(height: IslandMetrics.Nook.header * s)
                .padding(.bottom, IslandMetrics.Nook.headerGap * s)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 20 * s)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Home / Tray / Mirror. The selected tab shows its name; the others are just icons.
private struct NookTabs: View {
    let model: IslandModel
    let selected: HomeTab
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 4 * s) {
            ForEach(model.homeTabs, id: \.self) { tab in
                let isSelected = tab == selected
                Button {
                    model.showTab(tab)
                } label: {
                    HStack(spacing: 4 * s) {
                        Image(systemName: Self.symbol(tab))
                            .font(.system(size: 11 * s, weight: .semibold))
                        if isSelected {
                            Text(Self.title(tab))
                                .font(.system(size: 11 * s, weight: .semibold))
                        }
                        if tab == .tray, !model.tray.items.isEmpty {
                            Text("\(model.tray.items.count)")
                                .font(.system(size: 9 * s, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(isSelected ? .black : .white)
                                .padding(.horizontal, 4 * s)
                                .background(Capsule().fill(isSelected ? Color.white : NotchColor.buttonFill))
                        }
                    }
                    .foregroundStyle(isSelected ? .white : NotchColor.secondaryText)
                    .padding(.horizontal, 8 * s)
                    .frame(height: 22 * s)
                    .background(Capsule().fill(isSelected ? NotchColor.buttonFill : Color.clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .fixedSize()
                .help(Text(Self.title(tab)))
                .accessibilityLabel(Text(Self.title(tab)))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    static func title(_ tab: HomeTab) -> LocalizedStringKey {
        switch tab {
        case .home: "Home"
        case .tray: "Tray"
        case .mirror: "Mirror"
        }
    }

    static func symbol(_ tab: HomeTab) -> String {
        switch tab {
        case .home: "house.fill"
        case .tray: "tray.full.fill"
        case .mirror: "person.crop.square.fill"
        }
    }
}

/// Battery and Settings, on the right of the strip.
private struct NookStatus: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 8 * s) {
            if let battery = model.power.snapshot, battery.hasBattery {
                HStack(spacing: 4 * s) {
                    Text("\(battery.level)%")
                        .font(.system(size: 11 * s, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(NotchColor.secondaryText)
                    BatteryGlyph(level: battery.level, isCharging: battery.isCharging, color: Self.batteryColor(battery), width: 22 * s)
                }
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Battery \(battery.level) percent"))
            }
            Button {
                model.collapse()
                model.onOpenSettings?()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12 * s, weight: .semibold))
                    .foregroundStyle(NotchColor.secondaryText)
                    .frame(width: 22 * s, height: 22 * s)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("Settings"))
            .help("Settings")
        }
    }

    static func batteryColor(_ battery: PowerSnapshot) -> Color {
        if battery.isLowPowerMode { return NotchColor.yellow }
        if battery.isCharging || battery.isOnAC { return NotchColor.green }
        return battery.level <= 20 ? NotchColor.red : .white
    }
}

// MARK: Home

/// Media card on the left; calendar, timers and shortcuts beside it.
struct HomeBody: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        let content = model.homeContent
        HStack(alignment: .top, spacing: 14 * s) {
            if content.hasMedia {
                MediaCard(service: model.nowPlaying)
                    .frame(width: IslandMetrics.Nook.mediaCardWidth * s)
                    .frame(maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: IslandMetrics.Nook.rowGap * s) {
                if content.hasEvent {
                    CalendarRow(model: model, calendar: model.calendar)
                        .frame(height: IslandMetrics.Nook.row * s)
                }
                if content.hasTimer {
                    TimerPresetsRow(model: model)
                        .frame(height: IslandMetrics.Nook.row * s)
                }
                if content.hasShortcuts {
                    ShortcutsRow(model: model)
                        .frame(height: IslandMetrics.Nook.row * s)
                }
                if content.rowCount == 0 && !content.hasMedia {
                    Text("Nothing live right now")
                        .font(.system(size: 13 * s, weight: .medium))
                        .foregroundStyle(NotchColor.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.bottom, 2 * s)
    }
}

/// Artwork, title and transport controls in a small card.
private struct MediaCard: View {
    let service: NowPlayingService
    @Environment(\.notchScale) private var s

    var body: some View {
        let info = service.info
        VStack(alignment: .leading, spacing: 8 * s) {
            HStack(spacing: 10 * s) {
                Button { service.openSourceApp() } label: {
                    ArtworkView(artwork: service.artwork, fallbackIcon: service.appIcon, size: 46 * s, cornerRadius: 10 * s)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text("Open player"))
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text(info?.title ?? "")
                        .font(.system(size: 13 * s, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(info?.artist.isEmpty == false ? info?.artist ?? "" : service.appName ?? "")
                        .font(.system(size: 11 * s))
                        .foregroundStyle(NotchColor.secondaryText)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            MiniProgress(service: service)
                .frame(height: 3 * s)
            HStack(spacing: 18 * s) {
                GlyphButton(symbol: "backward.fill", size: 13 * s, label: "Previous Track") { service.previousTrack() }
                GlyphButton(symbol: info?.isPlaying == true ? "pause.fill" : "play.fill", size: 18 * s, label: info?.isPlaying == true ? "Pause" : "Play") {
                    service.togglePlayPause()
                }
                GlyphButton(symbol: "forward.fill", size: 13 * s, label: "Next Track") { service.nextTrack() }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(10 * s)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16 * s, style: .continuous).fill(Color.white.opacity(0.07)))
    }
}

private struct MiniProgress: View {
    let service: NowPlayingService

    var body: some View {
        let info = service.info
        TimelineView(.animation(minimumInterval: 1, paused: info?.isPlaying != true)) { context in
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule().fill(Color.white.opacity(0.85))
                        .frame(width: geometry.size.width * (info?.progress(at: context.date) ?? 0))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The next event, or a button to connect the calendar the first time.
private struct CalendarRow: View {
    let model: IslandModel
    let calendar: CalendarService
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 8 * s) {
            Image(systemName: "calendar")
                .font(.system(size: 12 * s, weight: .semibold))
                .foregroundStyle(NotchColor.red)
                .frame(width: 16 * s)
            if calendar.access == .notAsked {
                Text("Your next event")
                    .font(.system(size: 12 * s, weight: .medium))
                    .foregroundStyle(NotchColor.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 6 * s)
                Button("Connect") { calendar.requestAccess() }
                    .buttonStyle(ChipButtonStyle(tint: NotchColor.red, scale: s))
                    .fixedSize()
            } else if let event = calendar.nextEvent {
                Button { calendar.openCalendarApp() } label: {
                    HStack(spacing: 7 * s) {
                        Circle()
                            .fill(NotchColor.accent(event.color))
                            .frame(width: 6 * s, height: 6 * s)
                        Text(event.title)
                            .font(.system(size: 12 * s, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 6 * s)
                        TimelineView(.everyMinute) { context in
                            Text(CalendarRules.relativeLabel(for: event, at: context.date))
                                .font(.system(size: 11 * s, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(event.isHappening(at: context.date) ? NotchColor.green : NotchColor.secondaryText)
                                .fixedSize()
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text("Next event, \(event.title)"))
                if let url = event.meetingURL {
                    TimelineView(.everyMinute) { context in
                        if CalendarRules.canJoin(event, at: context.date) {
                            Button("Join") { model.joinMeeting(url) }
                                .buttonStyle(ChipButtonStyle(tint: NotchColor.green, scale: s))
                                .frame(width: 52 * s)
                                .help(url.host ?? "")
                                .accessibilityLabel(Text("Join \(event.title)"))
                        }
                    }
                    .fixedSize()
                }
            }
        }
    }
}

/// Timer icon followed by preset chips, on one line.
private struct TimerPresetsRow: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 6 * s) {
            Image(systemName: "timer")
                .font(.system(size: 12 * s, weight: .semibold))
                .foregroundStyle(NotchColor.orange)
                .frame(width: 16 * s)
                .accessibilityLabel(Text("Timer"))
            ForEach(TimerService.presets, id: \.self) { preset in
                Button(TimeFormatting.presetLabel(seconds: preset)) {
                    model.startTimer(preset)
                }
                .buttonStyle(ChipButtonStyle(scale: s))
                .accessibilityLabel(Text("Start \(TimeFormatting.spoken(preset)) timer"))
            }
            Button {
                model.startFocus()
            } label: {
                HStack(spacing: 3 * s) {
                    Image(systemName: FocusCycle.symbol(.focus))
                        .font(.system(size: 10 * s, weight: .semibold))
                    Text("Focus")
                }
            }
            .buttonStyle(ChipButtonStyle(tint: NotchColor.green, scale: s))
            .help("25 min focus, 5 min break, repeating")
            .accessibilityLabel(Text("Start focus session"))
        }
    }
}

private struct ShortcutsRow: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 6 * s) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 12 * s, weight: .semibold))
                .foregroundStyle(NotchColor.blue)
                .frame(width: 16 * s)
                .accessibilityHidden(true)
            ForEach(model.favoriteShortcuts, id: \.self) { name in
                let isRunning = model.shortcuts.running.contains(name)
                Button {
                    model.shortcuts.run(name)
                } label: {
                    HStack(spacing: 5 * s) {
                        if isRunning {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text(name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .buttonStyle(ChipButtonStyle(tint: NotchColor.blue, scale: s))
                .disabled(isRunning)
                .accessibilityLabel(Text("Run shortcut \(name)"))
            }
        }
    }
}

// MARK: Tray

/// Files dropped on the notch, and (when turned on) recent copied text. Files: drag them out,
/// double-click to open, right-click for more. Clips: click to copy again.
struct TrayBody: View {
    let model: IslandModel
    @State private var showsClips = false
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(alignment: .center, spacing: 8 * s) {
            Group {
                if showsClips {
                    ClipboardBody(model: model)
                } else {
                    FilesBody(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 6 * s) {
                modeButton(clips: false, symbol: "tray.full.fill", label: "Files")
                modeButton(clips: true, symbol: "doc.on.clipboard.fill", label: "Clipboard")
                Spacer(minLength: 0)
                Button {
                    if showsClips { model.clipboard.removeAll() } else { model.tray.removeAll() }
                } label: {
                    Image(systemName: "xmark.bin.fill")
                        .font(.system(size: 12 * s, weight: .semibold))
                        .foregroundStyle(NotchColor.secondaryText)
                        .frame(width: 28 * s, height: 28 * s)
                        .background(Circle().fill(NotchColor.buttonFill))
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(showsClips ? model.clipboard.clips.isEmpty : model.tray.items.isEmpty)
                .opacity((showsClips ? model.clipboard.clips.isEmpty : model.tray.items.isEmpty) ? 0.4 : 1)
                .help(showsClips ? "Clear clipboard history" : "Clear the tray")
                .accessibilityLabel(Text(showsClips ? "Clear clipboard history" : "Clear the tray"))
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.bottom, 2 * s)
    }

    private func modeButton(clips: Bool, symbol: String, label: LocalizedStringKey) -> some View {
        let isSelected = showsClips == clips
        return Button {
            showsClips = clips
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11 * s, weight: .semibold))
                .foregroundStyle(isSelected ? .white : NotchColor.secondaryText)
                .frame(width: 28 * s, height: 28 * s)
                .background(Circle().fill(isSelected ? NotchColor.buttonFill : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .help(Text(label))
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A dashed placeholder with a message, used by empty Tray views.
private struct TrayPlaceholder<Accessory: View>: View {
    let symbol: String
    let message: LocalizedStringKey
    @ViewBuilder var accessory: Accessory
    @Environment(\.notchScale) private var s

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            VStack(spacing: 6 * s) {
                Image(systemName: symbol)
                    .font(.system(size: 20 * s, weight: .semibold))
                Text(message)
                    .font(.system(size: 12 * s, weight: .medium))
                    .multilineTextAlignment(.center)
                accessory
            }
            .foregroundStyle(NotchColor.secondaryText)
            .padding(.horizontal, 12 * s)
        }
    }
}

private struct FilesBody: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        let items = model.tray.items
        if items.isEmpty {
            TrayPlaceholder(symbol: "tray.and.arrow.down.fill", message: "Drag files onto the notch to keep them here") {
                EmptyView()
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6 * s) {
                    ForEach(items) { item in
                        TrayItemView(model: model, item: item)
                    }
                }
            }
        }
    }
}

private struct ClipboardBody: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        let clips = model.clipboard.clips
        if !model.settings.clipboardHistoryEnabled {
            TrayPlaceholder(symbol: "doc.on.clipboard", message: "Keep the last 20 texts you copy. Memory only, skips passwords.") {
                Button("Turn On") { model.settings.clipboardHistoryEnabled = true }
                    .buttonStyle(ChipButtonStyle(tint: .white, scale: s))
                    .fixedSize()
            }
        } else if clips.isEmpty {
            TrayPlaceholder(symbol: "doc.on.clipboard", message: "Copy some text and it shows up here") {
                EmptyView()
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6 * s) {
                    ForEach(clips) { clip in
                        ClipCard(model: model, clip: clip)
                    }
                }
            }
        }
    }
}

private struct ClipCard: View {
    let model: IslandModel
    let clip: ClipboardHistory.Clip
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    var body: some View {
        let copied = model.clipboard.lastCopiedID == clip.id
        VStack(alignment: .leading, spacing: 4 * s) {
            Text(clip.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 11 * s, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(4)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(spacing: 4 * s) {
                if copied {
                    Image(systemName: "checkmark")
                    Text("Copied")
                } else {
                    Text(clip.date, style: .relative)
                }
            }
            .font(.system(size: 9 * s, weight: .semibold))
            .foregroundStyle(copied ? NotchColor.green : NotchColor.secondaryText)
            .lineLimit(1)
        }
        .padding(8 * s)
        .frame(width: 150 * s)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).fill(Color.white.opacity(isHovering ? 0.14 : 0.07)))
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button { model.clipboard.remove(clip.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14 * s))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(white: 0.35))
                }
                .buttonStyle(PressableButtonStyle())
                .padding(3 * s)
                .accessibilityLabel(Text("Remove clip"))
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { model.copyClip(clip) }
        .contextMenu {
            Button("Copy") { model.copyClip(clip) }
            Divider()
            Button("Remove") { model.clipboard.remove(clip.id) }
        }
        .help("Click to copy")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Copies this text"))
    }
}

private struct TrayItemView: View {
    let model: IslandModel
    let item: TrayStore.Item
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(spacing: 5 * s) {
            Image(nsImage: model.tray.icon(for: item))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 52 * s, height: 52 * s)
            Text(item.name)
                .font(.system(size: 10 * s, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 70 * s)
        }
        .padding(6 * s)
        .background(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).fill(Color.white.opacity(isHovering ? 0.12 : 0)))
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button { model.tray.remove(item.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14 * s))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(white: 0.35))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text("Remove \(item.name)"))
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        // Double-click opens, like Finder.
        .onTapGesture(count: 2) { model.tray.open(item) }
        .onDrag {
            model.isDraggingFromTray = true
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Open") { model.tray.open(item) }
            Button("Show in Finder") { model.tray.revealInFinder(item) }
            Button("Send with AirDrop") { model.airDrop([item.url]) }
            Divider()
            Button("Remove from Tray") { model.tray.remove(item.id) }
        }
        .help(item.name)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(item.name))
    }
}

// MARK: Mirror

/// A quick look at your camera before a call.
struct MirrorBody: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 16 * s) {
            ZStack {
                RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                if model.camera.state == .granted {
                    CameraPreview()
                        .clipShape(RoundedRectangle(cornerRadius: 16 * s, style: .continuous))
                } else {
                    Image(systemName: "person.crop.square.fill")
                        .font(.system(size: 28 * s, weight: .medium))
                        .foregroundStyle(NotchColor.secondaryText)
                }
            }
            // 16:9, the shape of a video call.
            .aspectRatio(16 / 9, contentMode: .fit)
            VStack(alignment: .leading, spacing: 8 * s) {
                Text(Self.message(model.camera.state))
                    .font(.system(size: 12 * s, weight: .medium))
                    .foregroundStyle(NotchColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                switch model.camera.state {
                case .notAsked:
                    Button("Turn On Camera") { model.camera.request() }
                        .buttonStyle(ChipButtonStyle(tint: .white, scale: s))
                        .fixedSize()
                case .denied:
                    Button("Open Settings") { model.camera.openPrivacySettings() }
                        .buttonStyle(ChipButtonStyle(tint: .white, scale: s))
                        .fixedSize()
                case .granted, .noCamera:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 2 * s)
    }

    private static func message(_ state: CameraAccess.State) -> LocalizedStringKey {
        switch state {
        case .granted: "Check how you look before a call. The camera turns off when you close this."
        case .notAsked: "Check how you look before a call."
        case .denied: "Camera access is off for Dynamic Notch."
        case .noCamera: "No camera found."
        }
    }
}
