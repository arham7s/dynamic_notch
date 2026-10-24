import AppKit
import Observation

/// The menu bar item: quick timers, Settings and Quit.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: IslandModel
    private let openSettings: () -> Void
    private var item: NSStatusItem?

    init(model: IslandModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        super.init()
        update()
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = model.settings.showMenuBarIcon
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.update()
                self?.observe()
            }
        }
    }

    private func update() {
        if model.settings.showMenuBarIcon {
            guard item == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let image = NSImage(systemSymbolName: "capsule.inset.filled", accessibilityDescription: "Dynamic Notch")
            image?.isTemplate = true
            item.button?.image = image
            item.button?.toolTip = "Dynamic Notch"
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            self.item = item
        } else if let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let timer = model.timer.timer, model.timer.isActive {
            let remaining = TimeFormatting.clock(timer.remaining(at: Date()), roundingUp: true)
            let name = model.timer.focus.map { FocusCycle.title($0.phase) } ?? "Timer"
            let status = NSMenuItem(title: timer.isPaused ? "\(name) paused · \(remaining)" : "\(name) · \(remaining) left", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(action(timer.isPaused ? "Resume Timer" : "Pause Timer") { [weak self] in self?.model.timer.togglePause() })
            menu.addItem(action("Cancel Timer") { [weak self] in self?.model.cancelTimer() })
        } else {
            let start = NSMenuItem(title: "Start Timer", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for preset in TimerService.menuPresets {
                submenu.addItem(action(TimeFormatting.presetLabel(seconds: preset)) { [weak self] in
                    self?.model.startTimer(preset)
                })
            }
            start.submenu = submenu
            start.isEnabled = model.settings.timerEnabled
            menu.addItem(start)
            let focus = action("Start Focus (25 min)") { [weak self] in self?.model.startFocus() }
            focus.isEnabled = model.settings.timerEnabled
            menu.addItem(focus)
        }
        menu.addItem(action("Open Notch") { [weak self] in self?.model.expand(.home) })

        menu.addItem(.separator())
        let settings = action("Settings…") { [weak self] in self?.openSettings() }
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(action("About Dynamic Notch") {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        })
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Dynamic Notch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func action(_ title: String, handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: handler)
        return item
    }
}

/// Menu item that runs a closure, so menus don't need a selector per action.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // Menu actions are delivered on the main thread.
    @objc private func run() {
        let handler = handler
        MainActor.assumeIsolated { handler() }
    }
}
