import Foundation
import Testing
@testable import PersonalAgent

/// Builds one SSE frame the way the server sends it: `data: <payload>\n\n`.
private func frame(_ payload: String) -> Data {
    Data("data: \(payload)\n\n".utf8)
}

// MARK: - SSEParser

@MainActor
struct SSEParserTests {

    @Test("1. A single token event is decoded")
    func parsesTokenEvent() {
        var parser = SSEParser()
        let events = parser.feed(frame(#"{"type":"token","content":"Hello"}"#))

        #expect(events.count == 1)
        guard case .token(let text) = events.first else {
            Issue.record("Expected a token event, got \(events)"); return
        }
        #expect(text == "Hello")
    }

    @Test("2. An event split across two network chunks is buffered until complete")
    func buffersPartialEvents() {
        var parser = SSEParser()
        let full = frame(#"{"type":"token","content":"split"}"#)
        let cut = full.count / 2

        let first = parser.feed(full.prefix(cut))
        #expect(first.isEmpty)

        let second = parser.feed(full.suffix(from: cut))
        guard case .token(let text) = second.first else {
            Issue.record("Expected a token event after the second chunk, got \(second)"); return
        }
        #expect(text == "split")
    }

    @Test("3. Several events in one chunk come back in order")
    func parsesMultipleEventsInOrder() {
        var parser = SSEParser()
        var chunk = Data()
        chunk.append(frame(#"{"type":"status","content":"Working on: search"}"#))
        chunk.append(frame(#"{"type":"token","content":"A"}"#))
        chunk.append(frame(#"{"type":"token","content":"B"}"#))

        let events = parser.feed(chunk)
        #expect(events.count == 3)

        guard events.count == 3,
              case .status(let status) = events[0],
              case .token(let a) = events[1],
              case .token(let b) = events[2] else {
            Issue.record("Unexpected events: \(events)"); return
        }
        #expect(status == "Working on: search")
        #expect(a + b == "AB")
    }

    @Test("4. The [DONE] sentinel becomes a .done event")
    func parsesDoneSentinel() {
        var parser = SSEParser()
        let events = parser.feed(frame("[DONE]"))

        guard case .done = events.first else {
            Issue.record("Expected .done, got \(events)"); return
        }
    }

    @Test("5. A confirm event carries tool, arguments and summary")
    func parsesConfirmEvent() {
        var parser = SSEParser()
        let json = #"{"type":"confirm","tool":"create_event","arguments":{"title":"Dentist","day":"Friday"},"summary":"Add 'Dentist' on Friday"}"#
        let events = parser.feed(frame(json))

        guard case .confirm(let tool, let arguments, let summary) = events.first else {
            Issue.record("Expected a confirm event, got \(events)"); return
        }
        #expect(tool == "create_event")
        #expect(arguments["title"] as? String == "Dentist")
        #expect(arguments["day"] as? String == "Friday")
        #expect(summary == "Add 'Dentist' on Friday")
    }

    @Test("6. Comments, malformed JSON and unknown event types are skipped")
    func ignoresInvalidInput() {
        var parser = SSEParser()
        var chunk = Data()
        chunk.append(Data(": keep-alive\n\n".utf8))                 // SSE comment
        chunk.append(frame("{not json"))                            // malformed
        chunk.append(frame(#"{"type":"heartbeat"}"#))               // unknown type
        chunk.append(frame(#"{"content":"no type field"}"#))        // missing type
        chunk.append(frame(#"{"type":"token","content":"ok"}"#))    // the only valid one

        let events = parser.feed(chunk)
        #expect(events.count == 1)
        guard case .token(let text) = events.first else {
            Issue.record("Expected only the valid token event, got \(events)"); return
        }
        #expect(text == "ok")
    }
}

// MARK: - ChatClient state handling

@MainActor
struct ChatClientStateTests {

    @Test("7. Token events append to the response and clear the status line")
    func tokensAccumulateAndClearStatus() {
        let client = ChatClient()
        client.handle(.status("Working on: calendar"))
        #expect(client.statusMessage == "Working on: calendar")

        client.handle(.token("Hello, "))
        client.handle(.token("Jerry"))

        #expect(client.responseText == "Hello, Jerry")
        #expect(client.statusMessage == nil)
    }

    @Test("8. A confirm event shows the confirmation card and stops streaming")
    func confirmEventShowsPendingAction() {
        let client = ChatClient()
        client.isStreaming = true
        client.handle(.status("Planning"))

        client.handle(.confirm(tool: "send_email",
                               arguments: ["to": "ben@example.com"],
                               summary: "Send an email to Ben"))

        #expect(client.pendingActionSummary == "Send an email to Ben")
        #expect(client.isStreaming == false)
        #expect(client.statusMessage == nil)
    }

    @Test("9. Cancelling a pending action clears it and changes nothing")
    func cancelActionClearsPending() {
        let client = ChatClient()
        client.handle(.confirm(tool: "delete_note", arguments: [:], summary: "Delete note 'Groceries'"))
        #expect(client.pendingActionSummary != nil)

        client.cancelAction()

        #expect(client.pendingActionSummary == nil)
        #expect(client.responseText == "Okay, cancelled — nothing was changed.")
    }

    @Test("10. Error and done events end the stream")
    func errorAndDoneStopStreaming() {
        let client = ChatClient()

        client.isStreaming = true
        client.handle(.error("Model unavailable"))
        #expect(client.errorMessage == "Model unavailable")
        #expect(client.isStreaming == false)

        client.isStreaming = true
        client.handle(.status("Finishing"))
        client.handle(.done)
        #expect(client.isStreaming == false)
        #expect(client.statusMessage == nil)
    }
}
