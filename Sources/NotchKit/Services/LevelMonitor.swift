import AppKit
import AudioToolbox
import CoreAudio

/// Reports volume and brightness changes so the notch can show them. Event-driven: Core Audio
/// listeners for volume, a DisplayServices callback for the built-in display's brightness.
@MainActor
public final class LevelMonitor {
    public var onChange: ((IslandAlert.LevelKind, Double, Bool) -> Void)?

    private var device: AudioDeviceID = 0
    private var deviceListener: AudioHW.Listener?
    private var volumeListeners: [AudioHW.Listener] = []
    private var lastVolume: (value: Double, muted: Bool)?
    private var lastBrightness: Double?
    private var brightnessRegistered = false
    private var isRunning = false

    /// Brightness keys move about 6 %; automatic brightness drifts in much smaller steps.
    nonisolated static let brightnessStep = 0.03

    public init() {}

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        deviceListener = AudioHW.listen(AudioHW.system, AudioHW.address(kAudioHardwarePropertyDefaultOutputDevice)) { [weak self] in
            self?.attachToOutput()
        }
        attachToOutput()
        registerBrightness()
    }

    public func stop() {
        isRunning = false
        deviceListener?.remove()
        deviceListener = nil
        volumeListeners.forEach { $0.remove() }
        volumeListeners.removeAll()
    }

    // MARK: Volume

    private func attachToOutput() {
        volumeListeners.forEach { $0.remove() }
        volumeListeners.removeAll()
        device = AudioHW.defaultOutputDevice()
        // Switching devices isn't a volume change; start fresh from the new device's level.
        lastVolume = readVolume()
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            let address = AudioHW.address(selector, scope: kAudioDevicePropertyScopeOutput)
            if let listener = AudioHW.listen(device, address, handler: { [weak self] in self?.volumeChanged() }) {
                volumeListeners.append(listener)
            }
        }
    }

    private func readVolume() -> (value: Double, muted: Bool)? {
        let volumeAddress = AudioHW.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        let muteAddress = AudioHW.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        let volume: Float32 = AudioHW.value(device, volumeAddress, default: -1)
        guard volume >= 0 else { return nil }
        let muted: UInt32 = AudioHW.value(device, muteAddress, default: 0)
        return (Double(volume), muted != 0)
    }

    private func volumeChanged() {
        guard let reading = readVolume() else { return }
        defer { lastVolume = reading }
        guard let last = lastVolume, abs(last.value - reading.value) > 0.001 || last.muted != reading.muted else { return }
        onChange?(.volume, reading.value, reading.muted)
    }

    // MARK: Brightness

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias RegisterBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutableRawPointer?, CFNotificationCallback) -> Int32

    private static let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)

    private static var builtInDisplay: CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    private func registerBrightness() {
        guard !brightnessRegistered,
              let library = Self.displayServices,
              let getSymbol = dlsym(library, "DisplayServicesGetBrightness"),
              let registerSymbol = dlsym(library, "DisplayServicesRegisterForBrightnessChangeNotifications"),
              let display = Self.builtInDisplay
        else { return }
        let get = unsafeBitCast(getSymbol, to: GetBrightness.self)
        var value: Float = 0
        if get(display, &value) == 0 {
            lastBrightness = Double(value)
        }
        let register = unsafeBitCast(registerSymbol, to: RegisterBrightness.self)
        LevelMonitor.current = self
        if register(display, nil, brightnessCallback) == 0 {
            brightnessRegistered = true
        }
    }

    /// The monitor that receives brightness callbacks; there is one per app.
    fileprivate static weak var current: LevelMonitor?

    /// Brightness at the start of the current burst of callbacks. A key press may arrive as a
    /// short animated burst, so the change is measured across the burst, not per callback.
    private var burstAnchor: Double?
    private var burstStart = Date.distantPast
    private var lastCallback = Date.distantPast
    /// A key press finishes its animation well inside this. Automatic brightness can send
    /// callbacks nonstop for minutes, so a burst is re-anchored after this long; otherwise its
    /// slow drift adds up past `brightnessStep` and the indicator never goes away.
    nonisolated static let maximumBurst: TimeInterval = 0.8

    func brightnessChanged(to value: Double, at now: Date = Date()) {
        guard isRunning else { return }
        if now.timeIntervalSince(lastCallback) > 0.5 || now.timeIntervalSince(burstStart) > Self.maximumBurst {
            burstAnchor = lastBrightness
            burstStart = now
        }
        lastCallback = now
        lastBrightness = value
        guard let anchor = burstAnchor, LevelMonitor.isUserBrightnessChange(from: anchor, to: value) else { return }
        onChange?(.brightness, value, false)
    }

    /// Key presses jump; automatic brightness creeps.
    nonisolated static func isUserBrightnessChange(from old: Double, to new: Double) -> Bool {
        abs(new - old) >= brightnessStep || (new <= 0.001 && old > 0.001) || (new >= 0.999 && old < 0.999)
    }
}


/// DisplayServices calls this when the built-in display's brightness changes. A plain global
/// function, so nothing about the caller's actor or thread is assumed.
private func brightnessCallback(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    let raw = (userInfo as NSDictionary?)?["value"]
    guard let value = (raw as? NSNumber)?.doubleValue ?? (raw as? String).flatMap(Double.init) else { return }
    DispatchQueue.main.async {
        MainActor.assumeIsolated { LevelMonitor.current?.brightnessChanged(to: value) }
    }
}
