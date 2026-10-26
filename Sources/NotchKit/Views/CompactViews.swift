import SwiftUI

/// Leading and trailing views either side of the empty middle, like ActivityKit's compact form.
struct CompactView: View {
    let model: IslandModel
    let kind: ActivityKind
    let size: CGSize
    /// Middle width kept clear for the camera in notch style.
    let cameraGap: CGFloat
    @Environment(\.notchScale) private var sizeScale

    var body: some View {
        let scale = CompactScale(height: size.height, size: sizeScale)
        let edge = scale.padding + 2
        // Each side gets the space between the outer edge and the camera, minus a little air.
        let side = max(0, (size.width - cameraGap) / 2 - edge - (cameraGap > 0 ? 4 : 3))
        HStack(spacing: 0) {
            leading(scale)
                .frame(width: side, alignment: .leading)
            Spacer(minLength: 0)
            trailing(scale)
                .frame(width: side, alignment: .trailing)
        }
        .padding(.horizontal, edge)
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func leading(_ scale: CompactScale) -> some View {
        switch kind {
        case .nowPlaying:
            ArtworkView(
                artwork: model.nowPlaying.artwork,
                fallbackIcon: model.nowPlaying.appIcon,
                size: scale.icon,
                cornerRadius: scale.icon * 0.28
            )
            .accessibilityLabel(Text(model.nowPlaying.info?.title ?? ""))
        case .timer:
            Image(systemName: "timer")
                .font(.system(size: scale.fontSize + 1, weight: .semibold))
                .foregroundStyle(NotchColor.orange)
                .accessibilityLabel(Text("Timer"))
        case .call:
            if let session = model.calls.session, !session.isCall {
                AppIconView(icon: model.calls.appIcon, symbol: "mic.fill", tint: NotchColor.orange, size: scale.icon)
                    .accessibilityLabel(Text(session.appName))
            } else {
                Image(systemName: model.calls.session?.usesCamera == true ? "video.fill" : "phone.fill")
                    .font(.system(size: scale.fontSize, weight: .semibold))
                    .foregroundStyle(NotchColor.green)
                    .accessibilityLabel(Text("On Call"))
            }
        }
    }

    @ViewBuilder
    private func trailing(_ scale: CompactScale) -> some View {
        switch kind {
        case .nowPlaying:
            WaveformBars(
                color: NotchColor.accent(model.nowPlaying.accent),
                isPlaying: model.nowPlaying.info?.isPlaying == true
            )
            .frame(width: scale.icon * 0.9, height: scale.icon * 0.78)
        case .timer:
            if let timer = model.timer.timer {
                CountdownText(timer: timer)
                    .font(.system(size: scale.fontSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(NotchColor.orange.opacity(timer.isPaused ? 0.6 : 1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        case .call:
            if let session = model.calls.session {
                Text(session.startDate, style: .timer)
                    .font(.system(size: scale.fontSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(session.isCall ? NotchColor.green : NotchColor.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

/// Content of the detached bubble for the second activity.
struct MinimalView: View {
    let model: IslandModel
    let kind: ActivityKind
    let diameter: CGFloat

    var body: some View {
        let inner = (diameter * 0.64).rounded()
        Group {
            switch kind {
            case .nowPlaying:
                if model.nowPlaying.artwork != nil || model.nowPlaying.appIcon != nil {
                    ArtworkView(artwork: model.nowPlaying.artwork, fallbackIcon: model.nowPlaying.appIcon, size: inner, cornerRadius: inner / 2)
                } else {
                    WaveformBars(color: NotchColor.accent(model.nowPlaying.accent), isPlaying: model.nowPlaying.info?.isPlaying == true)
                        .frame(width: inner * 0.7, height: inner * 0.6)
                }
            case .timer:
                TimerRing(model: model, diameter: inner)
            case .call:
                Image(systemName: model.calls.session?.usesCamera == true ? "video.fill" : "phone.fill")
                    .font(.system(size: diameter * 0.36, weight: .semibold))
                    .foregroundStyle(model.calls.session?.isCall == false ? NotchColor.orange : NotchColor.green)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Orange ring that empties as the timer runs.
private struct TimerRing: View {
    let model: IslandModel
    let diameter: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = model.timer.timer?.progress(at: context.date) ?? 0
            ZStack {
                Circle().stroke(NotchColor.orange.opacity(0.25), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: 1 - progress)
                    .stroke(NotchColor.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "timer")
                    .font(.system(size: diameter * 0.42, weight: .bold))
                    .foregroundStyle(NotchColor.orange)
            }
            .frame(width: diameter, height: diameter)
        }
    }
}

/// Shown while the pointer is over the resting notch: the time on the left of the camera and
/// the battery on the right, so the notch visibly comes alive and invites a click.
struct PeekView: View {
    let model: IslandModel
    let size: CGSize
    let cameraGap: CGFloat
    @Environment(\.notchScale) private var s

    var body: some View {
        let edge = 10 * s
        let side = max(0, (size.width - cameraGap) / 2 - edge - 4)
        HStack(spacing: 0) {
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 13 * s, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .frame(width: side, alignment: .leading)
            Spacer(minLength: 0)
            Group {
                if let battery = model.power.snapshot, battery.hasBattery {
                    HStack(spacing: 4 * s) {
                        Text("\(battery.level)%")
                            .font(.system(size: 12 * s, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(battery.isCharging ? NotchColor.green : NotchColor.secondaryText)
                        BatteryGlyph(
                            level: battery.level,
                            isCharging: battery.isCharging,
                            color: battery.isCharging ? NotchColor.green : (battery.level <= 20 ? NotchColor.red : .white),
                            width: 22 * s
                        )
                    }
                } else {
                    Image(systemName: "capsule.portrait.fill")
                        .font(.system(size: 12 * s, weight: .semibold))
                        .foregroundStyle(NotchColor.secondaryText)
                }
            }
            .frame(width: side, alignment: .trailing)
        }
        .padding(.horizontal, edge)
        .frame(width: size.width, height: size.height)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Click to open"))
    }
}
