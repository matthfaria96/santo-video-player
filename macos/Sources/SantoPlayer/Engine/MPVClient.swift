import Foundation
import Libmpv

enum MPVError: LocalizedError {
    case create
    case initialize(Int32)

    var errorDescription: String? {
        switch self {
        case .create: return String(localized: "Não foi possível iniciar o mpv.")
        case .initialize(let code):
            return String(localized: "Falha ao iniciar o mpv (\(String(cString: mpv_error_string(code)))).")
        }
    }
}

/// Values delivered by observed properties.
enum MPVValue {
    case none
    case flag(Bool)
    case double(Double)
    case int(Int64)
    case string(String)
}

/// Weak hop for mpv's wakeup callback, which runs on mpv's thread and may
/// fire while the client is being released.
private final class WakeBox {
    weak var client: MPVClient?
}

/// Thin Swift wrapper over an mpv handle. Events are drained on the main queue.
final class MPVClient {
    let handle: OpaquePointer
    private let wakeBox: Unmanaged<WakeBox>
    /// Called on the main queue for every observed property change.
    var onProperty: ((String, MPVValue) -> Void)?
    /// Called on the main queue for lifecycle events (file loaded, end of file…).
    var onEvent: ((mpv_event_id, mpv_end_file_reason?) -> Void)?

    init(options: [String: String]) throws {
        guard let handle = mpv_create() else { throw MPVError.create }
        self.handle = handle
        wakeBox = Unmanaged.passRetained(WakeBox())
        for (key, value) in options { mpv_set_option_string(handle, key, value) }
        let status = mpv_initialize(handle)
        guard status >= 0 else {
            mpv_terminate_destroy(handle)
            wakeBox.release()
            throw MPVError.initialize(status)
        }
        wakeBox.takeUnretainedValue().client = self
        mpv_set_wakeup_callback(handle, { context in
            guard let context else { return }
            let box = Unmanaged<WakeBox>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { [weak box] in box?.client?.drainEvents() }
        }, wakeBox.toOpaque())
    }

    deinit {
        mpv_set_wakeup_callback(handle, nil, nil)
        mpv_terminate_destroy(handle)
        // Released last: a callback already in flight only touches the box.
        let box = wakeBox
        DispatchQueue.main.async { box.release() }
    }

    // MARK: Commands and properties

    func command(_ args: String...) { command(args) }

    func command(_ args: [String]) {
        var cStrings: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        defer { cStrings.forEach { free($0) } }
        cStrings.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) {
                _ = mpv_command(handle, $0)
            }
        }
    }

    func set(_ name: String, _ value: String) { mpv_set_property_string(handle, name, value) }

    func set(_ name: String, _ value: Double) {
        var v = value
        mpv_set_property(handle, name, MPV_FORMAT_DOUBLE, &v)
    }

    func set(_ name: String, _ value: Bool) {
        var v: Int32 = value ? 1 : 0
        mpv_set_property(handle, name, MPV_FORMAT_FLAG, &v)
    }

    func double(_ name: String) -> Double? {
        var v = 0.0
        return mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &v) >= 0 ? v : nil
    }

    func int(_ name: String) -> Int64? {
        var v: Int64 = 0
        return mpv_get_property(handle, name, MPV_FORMAT_INT64, &v) >= 0 ? v : nil
    }

    func string(_ name: String) -> String? {
        guard let c = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(c) }
        return String(cString: c)
    }

    func observe(_ name: String, _ format: mpv_format) {
        mpv_observe_property(handle, 0, name, format)
    }

    // MARK: Events

    private func drainEvents() {
        while let event = mpv_wait_event(handle, 0), event.pointee.event_id != MPV_EVENT_NONE {
            let id = event.pointee.event_id
            switch id {
            case MPV_EVENT_PROPERTY_CHANGE:
                if let data = event.pointee.data {
                    let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
                    onProperty?(String(cString: property.name), Self.value(of: property))
                }
            case MPV_EVENT_END_FILE:
                let reason = event.pointee.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee.reason
                onEvent?(id, reason)
            case MPV_EVENT_SHUTDOWN:
                return
            default:
                onEvent?(id, nil)
            }
        }
    }

    private static func value(of property: mpv_event_property) -> MPVValue {
        guard let data = property.data else { return .none }
        switch property.format {
        case MPV_FORMAT_FLAG: return .flag(data.assumingMemoryBound(to: Int32.self).pointee != 0)
        case MPV_FORMAT_DOUBLE: return .double(data.assumingMemoryBound(to: Double.self).pointee)
        case MPV_FORMAT_INT64: return .int(data.assumingMemoryBound(to: Int64.self).pointee)
        case MPV_FORMAT_STRING:
            guard let c = data.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee else { return .none }
            return .string(String(cString: c))
        default: return .none
        }
    }
}
