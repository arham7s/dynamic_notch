import SwiftUI

/// Everything inside the island window.
struct IslandRootView: View {
    let model: IslandModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let presentation = model.presentation
        let layout = model.layout
        let liquid = model.settings.liquidAnimations && !reduceMotion

        ZStack(alignment: .topLeading) {
            KeyframeAnimator(initialValue: 0.0, trigger: presentation.topology) { pulse in
                IslandSurface(layout: layout, pulse: pulse, liquid: liquid)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1, duration: 0.08)
                    SpringKeyframe(0, duration: 0.6, spring: .smooth)
                }
            }
            .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)

            IslandContentLayer(model: model, presentation: presentation, layout: layout)
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height, alignment: .topLeading)
        .animation(Motion.shape(to: presentation, reduceMotion: reduceMotion), value: presentation)
        .animation(Motion.settings, value: model.settings.appearance)
        .animation(reduceMotion ? nil : Motion.hover, value: model.isHoveringPill)
        .environment(\.colorScheme, .dark)
    }
}

/// Content clipped to the animating pill and bubble.
struct IslandContentLayer: View {
    let model: IslandModel
    let presentation: IslandPresentation
    let layout: IslandLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            pill
            bubble
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height, alignment: .topLeading)
    }

    private var pillShape: IslandShape {
        IslandShape(topRadius: layout.topRadius, bottomRadius: layout.bottomRadius, flare: layout.flare)
    }

    private var pill: some View {
        ZStack(alignment: .topLeading) {
            if presentation.isVisible || (presentation == .hidden(peek: true) && layout.content.width > 0) {
                NotchContent(model: model, presentation: presentation, size: layout.content.size, cameraGap: layout.cameraGap, stripHeight: layout.stripHeight)
                    .environment(\.notchScale, layout.contentScale)
                    .frame(width: layout.content.width, height: layout.content.height)
                    .offset(x: layout.content.minX - layout.pill.minX, y: layout.content.minY - layout.pill.minY)
                    .id(ContentKey(presentation))
                    .transition(.islandContent)
            }
        }
        .frame(width: max(layout.pill.width, 1), height: max(layout.pill.height, 1), alignment: .topLeading)
        .clipShape(pillShape)
        .overlay {
            pillShape
                .stroke(Color.white.opacity(0.07 * layout.stroke), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .contentShape(pillShape)
        .onTapGesture { model.tapPill() }
        .contextMenu { IslandContextMenu(model: model, presentation: presentation) }
        .position(x: layout.pill.midX, y: layout.pill.midY)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Dynamic Notch"))
    }

    private var hasBubble: Bool {
        if case .compact(_, .some) = presentation { return true }
        return false
    }

    private var bubble: some View {
        ZStack {
            if case .compact(_, let secondary?) = presentation {
                MinimalView(model: model, kind: secondary, diameter: layout.bubble.height)
                    .id(secondary)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .frame(width: max(layout.bubble.width, 1), height: max(layout.bubble.height, 1))
        .clipShape(Circle())
        .contentShape(Circle())
        .onTapGesture { model.tapBubble() }
        // When tucked away the bubble is a point inside the shape; it must not steal clicks.
        .allowsHitTesting(hasBubble)
        .position(x: layout.bubble.midX, y: layout.bubble.midY)
    }
}

/// Identity of the content, so SwiftUI swaps views (with a transition) only when the content
/// really changes, not when a value inside it updates.
private struct ContentKey: Hashable {
    let value: String

    init(_ presentation: IslandPresentation) {
        value = switch presentation {
        case .hidden(let peek): peek ? "peek" : "hidden"
        case .idle: "idle"
        case .compact(let primary, _): "compact.\(primary.rawValue)"
        case .expanded(let kind): "expanded.\(kind.rawValue)"
        case .home: "home"
        case .tray: "tray"
        case .mirror: "mirror"
        case .alert(let alert): "alert.\(alert.kind)"
        case .drop: "drop"
        }
    }
}

struct NotchContent: View {
    let model: IslandModel
    let presentation: IslandPresentation
    let size: CGSize
    /// Width in the middle reserved for the camera.
    let cameraGap: CGFloat
    /// Notch style Home tabs: height of the strip beside the camera.
    var stripHeight: CGFloat = 0

    var body: some View {
        switch presentation {
        case .hidden(peek: true):
            PeekView(model: model, size: size, cameraGap: cameraGap)
        case .hidden, .idle:
            Color.clear
        case .compact(let primary, _):
            CompactView(model: model, kind: primary, size: size, cameraGap: cameraGap)
        case .expanded(.nowPlaying):
            NowPlayingExpandedView(model: model)
        case .expanded(.timer):
            TimerExpandedView(model: model)
        case .expanded(.call):
            CallExpandedView(model: model)
        case .home:
            NookContainer(model: model, tab: .home, cameraGap: cameraGap, stripHeight: stripHeight) { HomeBody(model: model) }
        case .tray:
            NookContainer(model: model, tab: .tray, cameraGap: cameraGap, stripHeight: stripHeight) { TrayBody(model: model) }
        case .mirror:
            NookContainer(model: model, tab: .mirror, cameraGap: cameraGap, stripHeight: stripHeight) { MirrorBody(model: model) }
        case .alert(let alert):
            AlertView(model: model, alert: alert, cameraGap: cameraGap)
        case .drop(let targeted):
            DropView(model: model, isTargeted: targeted)
        }
    }
}

struct IslandContextMenu: View {
    let model: IslandModel
    let presentation: IslandPresentation

    var body: some View {
        if model.timer.isActive, let timer = model.timer.timer {
            Button(timer.isPaused ? "Resume Timer" : "Pause Timer") { model.timer.togglePause() }
            Button("Cancel Timer") { model.cancelTimer() }
            Divider()
        }
        if let info = model.nowPlaying.info, info.hasContent {
            Button(info.isPlaying ? "Pause" : "Play") { model.nowPlaying.togglePlayPause() }
            Button("Next Track") { model.nowPlaying.nextTrack() }
            Divider()
        }
        if let session = model.calls.session {
            Button("Show \(session.appName)") { model.calls.showApp() }
            Divider()
        }
        Button("Settings…") { model.onOpenSettings?() }
        Button("Quit Dynamic Notch") { NSApp.terminate(nil) }
    }
}
