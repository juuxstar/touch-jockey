import AVFoundation
import CoreAudio
import Foundation

/// Audio output devices: listing them, and joining speakers and headphones into one device.
///
/// One `AVAudioEngine` drives one output device. To play the mix on the speakers and a cue
/// mix on headphones from the same engine (so both stay sample-locked), the two devices are
/// joined into a private **aggregate device**: speakers first (they keep the clock), then
/// headphones with drift correction. The engine then has, say, four channels: 1–2 speakers,
/// 3–4 headphones. A private aggregate is invisible to other apps and vanishes when we quit.
///
/// A device with four or more outputs (a DJ controller, an audio interface) can also carry
/// the headphones on its own channels 3–4, with no aggregate.
public enum AudioOutputs {
    public struct Device: Identifiable, Hashable {
        public let id: AudioDeviceID
        public let uid: String
        public let name: String
        public let channels: Int
    }

    static let aggregateUIDPrefix = "dev.touchjockey.outputs"

    /// Every device with outputs, except our own aggregates.
    public static func devices() -> [Device] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            let ch = outputChannels(id)
            guard ch > 0, let uid = string(id, kAudioDevicePropertyDeviceUID), !uid.hasPrefix(aggregateUIDPrefix),
                  !uid.hasPrefix("CADefaultDeviceAggregate") else { return nil }
            return Device(id: id, uid: uid, name: string(id, kAudioObjectPropertyName) ?? uid, channels: ch)
        }
    }

    /// The system's default output device.
    public static func defaultOutput() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    public static func device(uid: String) -> Device? { devices().first { $0.uid == uid } }

    public static func outputChannels(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let v = value else { return nil }
        return v.takeRetainedValue() as String
    }

    /// Joins speakers and headphones into a private aggregate device. The speakers keep the clock;
    /// the headphones are drift-corrected to it.
    public static func makeAggregate(speakers: Device, headphones: Device) -> AudioDeviceID? {
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Touch Jockey outputs",
            kAudioAggregateDeviceUIDKey: "\(aggregateUIDPrefix).\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceMainSubDeviceKey: speakers.uid,
            kAudioAggregateDeviceSubDeviceListKey: [[String: Any]]([
                [kAudioSubDeviceUIDKey: speakers.uid, kAudioSubDeviceDriftCompensationKey: 0],
                [kAudioSubDeviceUIDKey: headphones.uid, kAudioSubDeviceDriftCompensationKey: 1],
            ]),
        ]
        var id = AudioDeviceID(0)
        guard AudioHardwareCreateAggregateDevice(desc as CFDictionary, &id) == noErr, id != 0 else { return nil }
        // A new aggregate takes a moment to publish its streams.
        for _ in 0..<50 where outputChannels(id) < speakers.channels + headphones.channels {
            Thread.sleep(forTimeInterval: 0.02)
        }
        return id
    }

    public static func destroyAggregate(_ id: AudioDeviceID) {
        AudioHardwareDestroyAggregateDevice(id)
    }
}
