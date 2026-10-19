import Accelerate
import AudioToolbox
import CoreAudio
import Foundation
import KotobaCore
import Synchronization

/// Mic input from one device through the HAL output unit (AUHAL) with output disabled, as Apple's
/// TN2091 describes (`HALCaptureHardware.openInput`). AVAudioEngine's input node records through an
/// aggregate of the system default input and output on macOS 26+: a mic other than the default does
/// not stay selected, and a Bluetooth default is opened (dropped to the call profile) even when kotoba
/// records from another mic (crash of 2026-10-16). The unit is initialized while idle and runs only
/// between `start` and `stop`, so the mic is on only while recording.
final class HALInput: CaptureInput {
    /// A format that is not safe to record throws `InputFormatPolicy.Rejection` instead.
    enum Failure: Error {
        /// The HAL output unit is not installed (it ships with macOS, so this should not happen).
        case noComponent
        /// The unit was created without an error but no instance came back.
        case noInstance
        case audioUnit(step: String, status: OSStatus)
    }

    /// The device's sample rate; the ring receives mono Float32 samples at this rate.
    let sampleRate: Double
    private let unit: AudioUnit
    private let renderer: Renderer
    /// Kept so the ring outlives the unit's callbacks, which reach it unowned through the renderer.
    private let ring: SampleRing
    private let device: AudioObjectID
    private let listener: AudioObjectPropertyListenerBlock
    private static let watchedProperties = [kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyDeviceIsAlive]

    /// `onChange` runs on the main queue when the device's sample rate changes or the device dies.
    init(device: AudioObjectID, ring: SampleRing, onChange: @escaping @Sendable () -> Void) throws {
        unit = try Self.makeUnit()
        self.ring = ring
        self.device = device
        do {
            (sampleRate, renderer) = try Self.configure(unit, device: device, ring: ring)
        } catch {
            AudioComponentInstanceDispose(unit)
            throw error
        }
        listener = { _, _ in onChange() }
        for selector in Self.watchedProperties {
            var address = PropertyAddress(selector)
            let status = AudioObjectAddPropertyListenerBlock(device, &address, .main, listener)
            if status != noErr {
                Log.audio.error("Cannot watch the mic for route changes (\(selector)): \(status)")
            }
        }
    }

    deinit {
        for selector in Self.watchedProperties {
            var address = PropertyAddress(selector)
            let status = AudioObjectRemovePropertyListenerBlock(device, &address, .main, listener)
            if status != noErr {
                Log.audio.error("Cannot stop watching the mic (\(selector)): \(status)")
            }
        }
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        // Disposing ends the callbacks, so the renderer outlives every call into it.
        AudioComponentInstanceDispose(unit)
    }

    func start() throws {
        try Self.check("start", AudioOutputUnitStart(unit))
    }

    func stop() {
        AudioOutputUnitStop(unit)
    }

    private static func makeUnit() throws -> AudioUnit {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else { throw Failure.noComponent }
        var instance: AudioComponentInstance?
        try check("create", AudioComponentInstanceNew(component, &instance))
        guard let instance else { throw Failure.noInstance }
        return instance
    }

    /// Input on `device`, Float32 at the device rate (one or two channels, mixed to mono by the
    /// renderer), into a renderer that feeds `ring`; then initialized, so `start` only starts IO.
    private static func configure(
        _ unit: AudioUnit,
        device: AudioObjectID,
        ring: SampleRing
    ) throws -> (sampleRate: Double, renderer: Renderer) {
        // Input is element 1 and output element 0. IO must be enabled before the device is set.
        try set(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, UInt32(1))
        try set(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, UInt32(0))
        try set(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, device)
        // The device format is on the input scope of element 1, the client format on its output scope.
        let hardware: AudioStreamBasicDescription = try get(
            unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1)
        if let rejection = InputFormatPolicy.rejection(
            sampleRate: hardware.mSampleRate,
            channelCount: hardware.mChannelsPerFrame,
            deviceSampleRate: AudioDevices.nominalSampleRate(of: device)
        ) {
            throw rejection
        }
        // The unit converts sample format and channel count, not sample rate, so the client takes the
        // device rate. Without a channel map the unit passes device channels 1:1 from the first
        // (TN2091), so the client takes up to two and the renderer mixes them: a two-channel
        // receiver can carry its mic on either side.
        let channels = min(hardware.mChannelsPerFrame, 2)
        let client = AudioStreamBasicDescription(
            mSampleRate: hardware.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        try set(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, client)
        // The IO size can grow at any time (another app asks for larger buffers), up to the device's
        // maximum; a smaller buffer would fail every cycle and lose all audio.
        let maximumFrames = try largestBufferFrameSize(of: device)
        try set(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, maximumFrames)
        let renderer = Renderer(
            unit: unit, ring: ring, sampleRate: hardware.mSampleRate, channels: Int(channels), capacity: maximumFrames)
        let callback = AURenderCallbackStruct(
            inputProc: renderInput,
            inputProcRefCon: Unmanaged.passUnretained(renderer).toOpaque()
        )
        try set(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, callback)
        try check("initialize", AudioUnitInitialize(unit))
        return (hardware.mSampleRate, renderer)
    }

    private static func largestBufferFrameSize(of device: AudioObjectID) throws -> UInt32 {
        var range = AudioValueRange()
        var size = UInt32(MemoryLayout<AudioValueRange>.size)
        var address = PropertyAddress(kAudioDevicePropertyBufferFrameSizeRange)
        try check("read buffer size range", AudioObjectGetPropertyData(device, &address, 0, nil, &size, &range))
        return UInt32(range.mMaximum)
    }

    private static func check(_ step: String, _ status: OSStatus) throws {
        guard status == noErr else { throw Failure.audioUnit(step: step, status: status) }
    }

    private static func set<Value: BitwiseCopyable>(
        _ unit: AudioUnit,
        _ property: AudioUnitPropertyID,
        _ scope: AudioUnitScope,
        _ element: AudioUnitElement,
        _ value: Value
    ) throws {
        var value = value
        let status = AudioUnitSetProperty(unit, property, scope, element, &value, UInt32(MemoryLayout<Value>.size))
        try check("set property \(property)", status)
    }

    private static func get<Value: BitwiseCopyable>(
        _ unit: AudioUnit,
        _ property: AudioUnitPropertyID,
        _ scope: AudioUnitScope,
        _ element: AudioUnitElement
    ) throws -> Value {
        let value = UnsafeMutablePointer<Value>.allocate(capacity: 1)
        defer { value.deallocate() }
        var size = UInt32(MemoryLayout<Value>.size)
        try check("get property \(property)", AudioUnitGetProperty(unit, property, scope, element, value, &size))
        return value.pointee
    }
}

/// A mic whose format was read twice in the middle of a change (`InputRecovery.waitForDevice`). Reports once, on the
/// main queue, the next change of its rate, its life, its input channels or its input streams' format, so the end of
/// the change builds the input again; a change comes as a burst of these, and the build that the first one starts
/// watches again if it is still too early. Its listeners are removed when this is released: at the next input build.
final class SettlingInput {
    private let targets: [(object: AudioObjectID, address: AudioObjectPropertyAddress)]
    private let listener: AudioObjectPropertyListenerBlock

    init(device: AudioObjectID, onChange: @escaping @Sendable () -> Void) {
        let streams = ((try? AudioHardwareDevice(id: device).streams) ?? []).filter { (try? $0.direction) == .input }
        targets =
            [
                (device, PropertyAddress(kAudioDevicePropertyNominalSampleRate)),
                (device, PropertyAddress(kAudioDevicePropertyDeviceIsAlive)),
                (
                    device,
                    PropertyAddress(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput)
                ),
            ]
            + streams.flatMap { stream in
                [kAudioStreamPropertyVirtualFormat, kAudioStreamPropertyPhysicalFormat].map {
                    (stream.id, PropertyAddress($0))
                }
            }
        let pending = Mutex<(@Sendable () -> Void)?>(onChange)
        listener = { _, _ in pending.withLock { $0.take() }?() }
        for target in targets {
            var address = target.address
            let status = AudioObjectAddPropertyListenerBlock(target.object, &address, .main, listener)
            if status != noErr {
                Log.audio.error("Cannot watch the mic's change (\(target.address.mSelector)): \(status)")
            }
        }
    }

    deinit {
        // A listener that was not added, or a device that went away, returns an error here, which is ignored.
        for target in targets {
            var address = target.address
            AudioObjectRemovePropertyListenerBlock(target.object, &address, .main, listener)
        }
    }
}

/// The state the input callback uses: the unit to render from, preallocated buffers and the ring.
/// Only the real-time IO thread touches the buffers.
private final class Renderer {
    let unit: AudioUnit
    /// Unowned, so the IO thread does no retain or release: the `HALInput` that owns this renderer holds
    /// the ring too, and its deinit disposes the unit (ending the callbacks) first.
    unowned(unsafe) let ring: SampleRing
    let capacity: UInt32
    let buffers: UnsafeMutableAudioBufferListPointer
    /// The first channel's buffer, which also takes the mono mix, and the second channel's, if any.
    /// Plain pointers, not an array, so the IO thread touches no reference-counted storage.
    let first: UnsafeMutablePointer<Float>
    let second: UnsafeMutablePointer<Float>?
    let ticksPerFrame: Double

    init(unit: AudioUnit, ring: SampleRing, sampleRate: Double, channels count: Int, capacity: UInt32) {
        self.unit = unit
        self.ring = ring
        self.capacity = capacity
        first = .allocate(capacity: Int(capacity))
        second = count > 1 ? .allocate(capacity: Int(capacity)) : nil
        buffers = AudioBufferList.allocate(maximumBuffers: count > 1 ? 2 : 1)
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        ticksPerFrame = 1e9 / sampleRate * Double(timebase.denom) / Double(timebase.numer)
    }

    deinit {
        first.deallocate()
        second?.deallocate()
        buffers.unsafeMutablePointer.deallocate()
    }

    /// Runs on the real-time IO thread: render, mix, publish, signal. No allocation, no lock, no
    /// log, no Objective-C call, no reference counting.
    func render(
        _ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        _ timestamp: UnsafePointer<AudioTimeStamp>,
        _ bus: UInt32,
        _ frames: UInt32
    ) -> OSStatus {
        guard frames <= capacity else { return kAudioUnitErr_TooManyFramesToProcess }
        buffers[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: frames * 4, mData: first)
        if let second {
            buffers[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: frames * 4, mData: second)
        }
        let status = AudioUnitRender(unit, flags, timestamp, bus, frames, buffers.unsafeMutablePointer)
        guard status == noErr else { return status }
        if let second {
            var half: Float = 0.5
            vDSP_vasm(first, 1, second, 1, &half, first, 1, vDSP_Length(frames))
        }
        let start = timestamp.pointee.mHostTime
        let end = start + UInt64(Double(frames) * ticksPerFrame)
        ring.push(first, count: Int(frames), startHostTime: start, endHostTime: end)
        return noErr
    }
}

/// A C function, so it captures nothing; the renderer comes in through the reference constant,
/// borrowed without a retain (the `HALInput` that owns it outlives every callback).
private let renderInput: AURenderCallback = { refCon, flags, timestamp, bus, frames, _ in
    Unmanaged<Renderer>.fromOpaque(refCon)._withUnsafeGuaranteedRef { $0.render(flags, timestamp, bus, frames) }
}
