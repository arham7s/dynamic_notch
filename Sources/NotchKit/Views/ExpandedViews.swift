import SwiftUI

// All sizes below are the Large design; `notchScale` shrinks them for Medium and Small.

// MARK: Now Playing

struct NowPlayingExpandedView: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        let service = model.nowPlaying
        let info = service.info
        let accent = NotchColor.accent(service.accent)
        VStack(spacing: 0) {
            HStack(spacing: 12 * s) {
                Button { service.openSourceApp() } label: {
                    ArtworkView(artwork: service.artwork, fallbackIcon: service.appIcon, size: 56 * s, cornerRadius: 13 * s)
                }
                .buttonStyle(PressableButtonStyle())
                .help(service.appName.map { "Open \($0)" } ?? "")
                .accessibilityLabel(Text(service.appName.map { "Open \($0)" } ?? "Open player"))

                VStack(alignment: .leading, spacing: 2 * s) {
                    Text(info?.title ?? "")
                        .font(.system(size: 15 * s, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(info?.artist.isEmpty == false ? info?.artist ?? "" : service.appName ?? "")
                        .font(.system(size: 13 * s))
                        .foregroundStyle(NotchColor.secondaryText)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

                WaveformBars(color: accent, isPlaying: info?.isPlaying == true)
                    .frame(width: 20 * s, height: 18 * s)
            }

            ProgressRow(service: service)
                .padding(.top, 14 * s)

            HStack(spacing: 30 * s) {
                GlyphButton(symbol: "backward.fill", size: 19 * s, label: "Previous Track") { service.previousTrack() }
                GlyphButton(symbol: info?.isPlaying == true ? "pause.fill" : "play.fill", size: 27 * s, label: info?.isPlaying == true ? "Pause" : "Play") {
                    service.togglePlayPause()
                }
                GlyphButton(symbol: "forward.fill", size: 19 * s, label: "Next Track") { service.nextTrack() }
            }
            .padding(.top, 4 * s)
        }
        .padding(.horizontal, 22 * s)
        .frame(maxHeight: .infinity)
    }
}

private struct ProgressRow: View {
    let service: NowPlayingService
    @State private var scrubProgress: Double?
    @Environment(\.notchScale) private var s

    var body: some View {
        let info = service.info
        // Only ticks while playing; a paused track has nothing to update.
        TimelineView(.animation(minimumInterval: 0.5, paused: info?.isPlaying != true)) { context in
            let duration = info?.duration
            let live = info?.elapsed(at: context.date)
            let elapsed = scrubProgress.flatMap { progress in duration.map { $0 * progress } } ?? live ?? 0
            let progress = scrubProgress ?? info?.progress(at: context.date)
            HStack(spacing: 10 * s) {
                Text(TimeFormatting.clock(elapsed))
                    .frame(width: 40 * s, alignment: .leading)
                ScrubBar(progress: progress ?? 0, isEnabled: duration != nil) { value, ended in
                    scrubProgress = ended ? nil : value
                    if ended, let duration {
                        service.seek(to: value * duration)
                    }
                }
                Text(duration.map { TimeFormatting.remaining(elapsed: elapsed, duration: $0) } ?? "--:--")
                    .frame(width: 44 * s, alignment: .trailing)
            }
            .font(.system(size: 11 * s, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(NotchColor.secondaryText)
        }
    }
}

private struct ScrubBar: View {
    var progress: Double
    var isEnabled: Bool
    var onScrub: (Double, Bool) -> Void
    @State private var isDragging = false
    @Environment(\.notchScale) private var s

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(Color.white).frame(width: width * min(max(progress, 0), 1))
            }
            .frame(height: (isDragging ? 8 : 5) * s)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        isDragging = true
                        onScrub(min(max(value.location.x / width, 0), 1), false)
                    }
                    .onEnded { value in
                        guard isEnabled else { return }
                        isDragging = false
                        onScrub(min(max(value.location.x / width, 0), 1), true)
                    }
            )
            .animation(.spring(duration: 0.25, bounce: 0.3), value: isDragging)
        }
        .frame(height: 14 * s)
        .accessibilityElement()
        .accessibilityLabel(Text("Playback position"))
        .accessibilityValue(Text("\(Int(progress * 100)) percent"))
    }
}

// MARK: Timer

struct TimerExpandedView: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        let timer = model.timer.timer
        let isPaused = timer?.isPaused == true
        HStack(spacing: 12 * s) {
            CircleButton(
                symbol: isPaused ? "play.fill" : "pause.fill",
                size: 48 * s,
                foreground: NotchColor.orange,
                background: NotchColor.orange.opacity(0.25),
                label: isPaused ? "Resume Timer" : "Pause Timer"
            ) { model.timer.togglePause() }
            CircleButton(symbol: "xmark", size: 48 * s, label: "Cancel Timer") { model.cancelTimer() }
            Spacer(minLength: 8 * s)
            VStack(alignment: .trailing, spacing: -4 * s) {
                Group {
                    if let focus = model.timer.focus {
                        Text("\(FocusCycle.title(focus.phase)) · \(focus.completed) done")
                    } else {
                        Text("Timer")
                    }
                }
                    .font(.system(size: 13 * s, weight: .semibold))
                    .foregroundStyle(model.timer.focus?.isBreak == true ? NotchColor.green : NotchColor.orange)
                if let timer {
                    CountdownText(timer: timer)
                        .font(.system(size: 42 * s, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(NotchColor.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .padding(.horizontal, 20 * s)
    }
}

// MARK: Call

struct CallExpandedView: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        if let session = model.calls.session {
            let tint = session.isCall ? NotchColor.green : NotchColor.orange
            HStack(spacing: 12 * s) {
                AppIconView(icon: model.calls.appIcon, symbol: session.isCall ? "phone.fill" : "mic.fill", tint: tint, size: 46 * s)
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text(session.appName)
                        .font(.system(size: 15 * s, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 6 * s) {
                        Text(session.isCall ? "On Call" : "Using Microphone")
                        Text(session.startDate, style: .timer)
                            .monospacedDigit()
                    }
                    .font(.system(size: 13 * s))
                    .foregroundStyle(NotchColor.secondaryText)
                    .lineLimit(1)
                }
                Spacer(minLength: 8 * s)
                HStack(spacing: 6 * s) {
                    if session.usesCamera {
                        Image(systemName: "video.fill").foregroundStyle(NotchColor.green)
                    }
                    Image(systemName: "mic.fill").foregroundStyle(NotchColor.orange)
                }
                .font(.system(size: 12 * s, weight: .semibold))
                .accessibilityElement()
                .accessibilityLabel(Text(session.usesCamera ? "Camera and microphone in use" : "Microphone in use"))
                CircleButton(symbol: "arrow.up.forward", size: 44 * s, foreground: .white, background: tint, label: "Show \(session.appName)") {
                    model.calls.showApp()
                    model.collapse()
                }
            }
            .padding(.horizontal, 20 * s)
        }
    }
}
