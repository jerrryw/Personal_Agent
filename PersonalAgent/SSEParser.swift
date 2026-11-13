import Foundation

/// One event decoded from the agent server's `/chat/stream` SSE response.
enum SSEEvent {
    case token(String)
    case status(String?)
    case confirm(tool: String?, arguments: [String: Any], summary: String?)
    case error(String?)
    case done
}

/// Incremental parser for the server-sent event stream.
/// Feed it raw bytes as they arrive; it buffers partial events across chunks
/// and returns every complete event (terminated by a blank line) in order.
struct SSEParser {
    private var buffer = Data()

    mutating func feed(_ data: Data) -> [SSEEvent] {
        buffer.append(data)
        var events: [SSEEvent] = []

        while let range = buffer.range(of: Data("\n\n".utf8)) {
            let eventData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)

            guard let eventString = String(data: eventData, encoding: .utf8),
                  eventString.hasPrefix("data: ") else { continue }
            let payload = String(eventString.dropFirst(6))

            if payload == "[DONE]" {
                events.append(.done)
                continue
            }

            guard let jsonData = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let type = json["type"] as? String else { continue }

            switch type {
            case "token":
                if let content = json["content"] as? String { events.append(.token(content)) }
            case "status":
                events.append(.status(json["content"] as? String))
            case "confirm":
                events.append(.confirm(
                    tool: json["tool"] as? String,
                    arguments: json["arguments"] as? [String: Any] ?? [:],
                    summary: json["summary"] as? String
                ))
            case "error":
                events.append(.error(json["content"] as? String))
            default:
                break
            }
        }
        return events
    }

    mutating func reset() {
        buffer = Data()
    }
}
