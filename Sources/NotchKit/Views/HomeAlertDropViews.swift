import SwiftUI
import UniformTypeIdentifiers

// MARK: Alerts

struct AlertView: View {
    let model: IslandModel
    let alert: IslandAlert
    /// Middle width kept clear for the camera in notch style.
    var cameraGap: CGFloat = 0
    @Environment(\.notchScale) private var s

    var body: some View {
        switch alert {
        case .charging(let level, let isCharging):
            let lowPower = model.power.snapshot?.isLowPowerMode == true
            let tint = lowPower ? NotchColor.yellow : NotchColor.green
            AlertRow(cameraGap: cameraGap) {
                Text(isCharging ? "Charging" : "Connected")
            } trailing: {
                BatteryLabel(level: level, isCharging: true, tint: tint)
            }
            .accessibilityElement(children: .combine)
        case .lowBattery(let level):
            AlertRow(cameraGap: cameraGap) {
                Text("Low Battery")
            } trailing: {
                BatteryLabel(level: level, isCharging: false, tint: NotchColor.red)
            }
            .accessibilityElement(children: .combine)
        case .headphones(let name, let symbol):
            AlertRow(cameraGap: cameraGap) {
                HStack(spacing: 6 * s) {
                    Image(systemName: symbol)
                        .font(.system(size: 15 * s, weight: .medium))
                    Text(name)
                        .font(.system(size: 13 * s, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } trailing: {
                Text("Connected")
                    .foregroundStyle(NotchColor.green)
            }
            .accessibilityElement(children: .combine)
        case .timerFinished:
            TimerFinishedView(model: model)
        case .welcome:
            AlertRow(cameraGap: cameraGap) {
                Text("Dynamic Notch")
            } trailing: {
                Text("Ready")
                    .foregroundStyle(NotchColor.green)
            }
            .accessibilityElement(children: .combine)
        case .level(let kind, let value, let muted):
            AlertRow(cameraGap: cameraGap) {
                Image(systemName: Self.levelSymbol(kind, value: value, muted: muted))
                    .font(.system(size: 15 * s, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 24 * s, alignment: .leading)
            } trailing: {
                LevelBar(value: muted ? 0 : value)
                    .frame(width: 64 * s, height: 6 * s)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(kind == .volume ? "Volume" : "Brightness"))
            .accessibilityValue(Text(muted ? "Muted" : "\(Int((value * 100).rounded())) percent"))
        case .upcomingEvent(let title, let minutes, let meetingURL):
            AlertRow(cameraGap: cameraGap) {
                HStack(spacing: 6 * s) {
                    Image(systemName: "calendar")
                        .foregroundStyle(NotchColor.red)
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } trailing: {
                if let meetingURL {
                    HStack(spacing: 6 * s) {
                        Text(minutes <= 0 ? "Now" : "\(minutes) min")
                            .foregroundStyle(NotchColor.red)
                            .fixedSize()
                        Button("Join") { model.joinMeeting(meetingURL) }
                            .buttonStyle(ChipButtonStyle(tint: NotchColor.green, scale: s))
                            .frame(width: 52 * s)
                            .accessibilityLabel(Text("Join \(title)"))
                    }
                } else {
                    Text(minutes <= 0 ? "Starting now" : "In \(minutes) min")
                        .foregroundStyle(NotchColor.red)
                }
            }
            .accessibilityElement(children: meetingURL == nil ? .combine : .contain)
        case .focusPhase(let phase, let completed):
            let tint = phase == .focus ? NotchColor.orange : NotchColor.green
            AlertRow(cameraGap: cameraGap) {
                HStack(spacing: 6 * s) {
                    Image(systemName: FocusCycle.symbol(phase))
                        .foregroundStyle(tint)
                    Text(FocusCycle.title(phase))
                        .lineLimit(1)
                }
            } trailing: {
                Text(phase == .focus ? "Session \(completed + 1)" : "\(Int(FocusCycle.duration(of: phase) / 60)) min")
                    .foregroundStyle(tint)
            }
            .accessibilityElement(children: .combine)
        case .shortcut(let name, let succeeded):
            AlertRow(cameraGap: cameraGap) {
                HStack(spacing: 6 * s) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(NotchColor.blue)
                    Text(name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } trailing: {
                Text(succeeded ? "Done" : "Failed")
                    .foregroundStyle(succeeded ? NotchColor.green : NotchColor.red)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private static func levelSymbol(_ kind: IslandAlert.LevelKind, value: Double, muted: Bool) -> String {
        switch kind {
        case .brightness:
            return value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            if muted || value <= 0.001 { return "speaker.slash.fill" }
            if value < 0.34 { return "speaker.wave.1.fill" }
            if value < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    }
}

/// Leading content left of the camera, trailing content right of it.
private struct AlertRow<Leading: View, Trailing: View>: View {
    var cameraGap: CGFloat
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.notchScale) private var s

    var body: some View {
        GeometryReader { geometry in
            let edge: CGFloat = (cameraGap > 0 ? 14 : 20) * s
            let side = max(0, (geometry.size.width - cameraGap) / 2 - edge - (cameraGap > 0 ? 6 : 4))
            HStack(spacing: 0) {
                leading
                    .frame(width: side, alignment: .leading)
                Spacer(minLength: 0)
                trailing
                    .frame(width: side, alignment: .trailing)
            }
            .padding(.horizontal, edge)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .font(.system(size: 14 * s, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
    }
}

private struct BatteryLabel: View {
    var level: Int
    var isCharging: Bool
    var tint: Color
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 6 * s) {
            Text("\(level)%")
                .monospacedDigit()
                .foregroundStyle(tint)
            BatteryGlyph(level: level, isCharging: isCharging, color: tint, width: 27 * s)
        }
    }
}

private struct TimerFinishedView: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 12 * s) {
            Image(systemName: "bell.fill")
                .font(.system(size: 24 * s, weight: .semibold))
                .foregroundStyle(NotchColor.orange)
                .phaseAnimator([0.0, -16, 14, -10, 8, 0, 0, 0]) { bell, angle in
                    bell.rotationEffect(.degrees(angle), anchor: .top)
                } animation: { _ in
                    .easeInOut(duration: 0.11)
                }
                .frame(width: 44 * s)
            VStack(alignment: .leading, spacing: 0) {
                Text("Timer")
                    .font(.system(size: 13 * s, weight: .semibold))
                    .foregroundStyle(NotchColor.orange)
                Text("Done")
                    .font(.system(size: 26 * s, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 8 * s)
            CircleButton(symbol: "arrow.counterclockwise", size: 48 * s, label: "Repeat Timer") { model.repeatTimer() }
            CircleButton(symbol: "xmark", size: 48 * s, foreground: .black, background: NotchColor.orange, label: "Stop Timer") {
                model.stopTimerAlarm()
            }
        }
        .padding(.horizontal, 20 * s)
    }
}

// MARK: Drop

struct DropView: View {
    let model: IslandModel
    let isTargeted: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 10 * s) {
            if model.settings.trayEnabled {
                zone(.tray, title: "Tray", targetedTitle: "Keep in Tray", symbol: "tray.and.arrow.down.fill", tint: .white)
            }
            if model.settings.airDropEnabled {
                zone(.airDrop, title: "AirDrop", targetedTitle: "Send with AirDrop", symbol: "dot.radiowaves.up.forward", tint: NotchColor.blue)
            }
        }
        .padding(12 * s)
    }

    private func zone(_ zone: IslandModel.DropZone, title: LocalizedStringKey, targetedTitle: LocalizedStringKey, symbol: String, tint: Color) -> some View {
        let targeted = model.targetedZone == zone
        return ZStack {
            RoundedRectangle(cornerRadius: 22 * s, style: .continuous)
                .fill(tint.opacity(targeted ? 0.16 : 0.05))
            RoundedRectangle(cornerRadius: 22 * s, style: .continuous)
                .strokeBorder(tint.opacity(targeted ? 0.9 : 0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            VStack(spacing: 8 * s) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(targeted ? 0.3 : 0.15))
                        .frame(width: 40 * s, height: 40 * s)
                    Image(systemName: symbol)
                        .font(.system(size: 17 * s, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .scaleEffect(targeted ? 1.1 : 1)
                Text(targeted ? targetedTitle : title)
                    .font(.system(size: 12 * s, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.4), value: targeted)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: Binding(
            get: { model.targetedZone == zone },
            set: { model.setTargeted(zone, $0) }
        )) { providers in
            loadURLs(from: providers, into: zone)
            return true
        }
        .accessibilityElement(children: .combine)
    }

    private func loadURLs(from providers: [NSItemProvider], into zone: IslandModel.DropZone) {
        let group = DispatchGroup()
        let collector = URLCollector()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { collector.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated {
                switch zone {
                case .tray: model.addToTray(collector.urls)
                case .airDrop: model.airDrop(collector.urls)
                }
            }
        }
    }
}

/// Collects URLs from item-provider callbacks, which arrive on background threads.
private final class URLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// Thin level meter for volume and brightness.
private struct LevelBar: View {
    var value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule()
                    .fill(Color.white)
                    .frame(width: geometry.size.width * min(max(value, 0), 1))
            }
        }
        .animation(.spring(duration: 0.2, bounce: 0), value: value)
    }
}
