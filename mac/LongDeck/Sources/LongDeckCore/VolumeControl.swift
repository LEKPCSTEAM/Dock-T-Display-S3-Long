import AudioToolbox
import CoreAudio
import Dispatch

@MainActor public protocol VolumeControl: AnyObject {
    func read() -> VolumeState
    func setLevel(_ level: Int) throws
    func setMuted(_ muted: Bool) throws
}

public extension VolumeControl {
    func toggleMute() throws {
        let state = read()
        guard state.available else { throw VolumeError.unavailable }
        try setMuted(!state.muted)
    }

    func setLevelUnmuting(_ level: Int) throws {
        try setLevel(level)
        if level > 0, read().muted { try setMuted(false) }
    }
}

@MainActor public final class CoreAudioVolume: VolumeControl {
    public var onChange: (() -> Void)?

    private static let volumeSelector = AudioObjectPropertySelector(0x766D7663)
    private var started = false
    private var listenedDevice = AudioObjectID(kAudioObjectUnknown)
    private var deviceBlock: AudioObjectPropertyListenerBlock?
    private var propertyBlock: AudioObjectPropertyListenerBlock?

    public init() {}

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static var defaultDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultDevice() -> AudioObjectID? {
        var address = defaultDeviceAddress
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    public static func defaultOutputName() -> String? {
        guard let device = defaultDevice() else { return nil }
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name)
        return status == noErr ? name?.takeRetainedValue() as String? : nil
    }

    private func settable(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = Self.address(selector)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private func get<T: BitwiseCopyable>(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout T) -> Bool {
        var address = Self.address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
    }

    private func set<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, _ value: T) throws {
        guard let device = Self.defaultDevice(), settable(device, selector) else { throw VolumeError.unavailable }
        var address = Self.address(selector)
        var value = value
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value)
        if status != noErr { throw VolumeError.status(status) }
    }

    public func read() -> VolumeState {
        guard let device = Self.defaultDevice(), settable(device, Self.volumeSelector) else { return .unavailable }
        var scalar = Float32(0)
        guard get(device, Self.volumeSelector, &scalar) else { return .unavailable }
        var mute = UInt32(0)
        let muted = settable(device, kAudioDevicePropertyMute)
            && get(device, kAudioDevicePropertyMute, &mute) && mute != 0
        return VolumeState(level: Int((scalar * 100).rounded()), muted: muted, available: true)
    }

    public func setLevel(_ level: Int) throws {
        try set(Self.volumeSelector, Float32(max(0, min(100, level))) / 100)
    }

    public func setMuted(_ muted: Bool) throws {
        try set(kAudioDevicePropertyMute, UInt32(muted ? 1 : 0))
    }

    public func start() {
        guard !started else { return }
        started = true
        propertyBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        deviceBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.moveListeners()
                self?.onChange?()
            }
        }
        var address = Self.defaultDeviceAddress
        if let deviceBlock {
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, deviceBlock)
        }
        moveListeners()
    }

    private func moveListeners() {
        let selectors = [Self.volumeSelector, kAudioDevicePropertyMute]
        if listenedDevice != kAudioObjectUnknown, let propertyBlock {
            for selector in selectors {
                var address = Self.address(selector)
                AudioObjectRemovePropertyListenerBlock(listenedDevice, &address, DispatchQueue.main, propertyBlock)
            }
        }
        listenedDevice = Self.defaultDevice() ?? AudioObjectID(kAudioObjectUnknown)
        guard listenedDevice != kAudioObjectUnknown, let propertyBlock else { return }
        for selector in selectors {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(listenedDevice, &address, DispatchQueue.main, propertyBlock)
        }
    }
}
