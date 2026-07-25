import Foundation

/// Incremental parser for `text/event-stream` bodies. Bytes are fed one at a
/// time (matching the transport's capped byte loop) and complete event data
/// payloads come back once a blank line terminates their frame. Multi-byte
/// UTF-8 is safe because payload bytes are decoded only after the full frame
/// arrived. Comment (`:`) keepalive lines and trailing `\r` are ignored, and
/// multiple `data:` lines in one frame join with `\n` per the SSE spec.
struct LLMServerSentEventParser {
    private var pendingFrameBytes = Data()
    private var carriageReturnPending = false

    /// Appends one byte and returns every event data payload completed by it.
    mutating func append(_ byte: UInt8) -> [String] {
        var completedPayloads: [String] = []
        if byte == UInt8(ascii: "\n") {
            if carriageReturnPending {
                pendingFrameBytes.removeLast()
                carriageReturnPending = false
            }
            pendingFrameBytes.append(byte)
            if pendingFrameBytes.suffix(2) == Data([UInt8(ascii: "\n"), UInt8(ascii: "\n")]) {
                if let payload = Self.payload(fromFrame: pendingFrameBytes) {
                    completedPayloads.append(payload)
                }
                pendingFrameBytes.removeAll(keepingCapacity: true)
            }
            return completedPayloads
        }
        if carriageReturnPending {
            carriageReturnPending = false
        }
        if byte == UInt8(ascii: "\r") {
            carriageReturnPending = true
        }
        pendingFrameBytes.append(byte)
        return completedPayloads
    }

    /// Flushes a trailing frame that ended without its blank-line terminator.
    mutating func finish() -> [String] {
        defer { pendingFrameBytes.removeAll(keepingCapacity: false) }
        guard let payload = Self.payload(fromFrame: pendingFrameBytes) else {
            return []
        }
        return [payload]
    }

    private static func payload(fromFrame frameBytes: Data) -> String? {
        guard !frameBytes.isEmpty,
              let frame = String(data: frameBytes, encoding: .utf8)
        else {
            return nil
        }
        var dataLines: [String] = []
        for line in frame.split(separator: "\n", omittingEmptySubsequences: false) {
            var field = Substring(line)
            if field.hasSuffix("\r") {
                field = field.dropLast()
            }
            guard !field.isEmpty, !field.hasPrefix(":") else { continue }
            guard field.hasPrefix("data:") else { continue }
            var value = field.dropFirst("data:".count)
            if value.hasPrefix(" ") {
                value = value.dropFirst()
            }
            dataLines.append(String(value))
        }
        guard !dataLines.isEmpty else { return nil }
        return dataLines.joined(separator: "\n")
    }
}
