import Foundation
import Combine

// Change this to your Mac's IP address (from `ipconfig getifaddr en0`)
let SERVER_BASE_URL = "http://192.168.1.12:8000"

@MainActor
class ChatClient: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published var responseText: String = ""
    @Published var statusMessage: String? = nil
    @Published var pendingActionSummary: String? = nil   // set when a write action awaits confirmation
    @Published var isStreaming: Bool = false
    @Published var errorMessage: String? = nil

    // Details of the action awaiting confirmation
    private var pendingTool: String?
    private var pendingArguments: [String: Any]?

    private var session: URLSession!
    private var parser = SSEParser()

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func sendMessage(_ message: String) {
        responseText = ""
        statusMessage = nil
        pendingActionSummary = nil
        pendingTool = nil
        pendingArguments = nil
        errorMessage = nil
        isStreaming = true
        parser.reset()

        guard let url = URL(string: "\(SERVER_BASE_URL)/chat/stream") else {
            errorMessage = "Invalid server URL"; isStreaming = false; return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let body = ["message": message, "max_tokens": 512] as [String: Any]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session.dataTask(with: request).resume()
    }

    // User tapped Confirm on a proposed write action
    func confirmAction() {
        guard let tool = pendingTool else { return }
        let arguments = pendingArguments ?? [:]
        let summary = pendingActionSummary ?? "the action"
        pendingActionSummary = nil
        isStreaming = true
        Task { await postExecute(tool: tool, arguments: arguments, summary: summary) }
    }

    // User tapped Cancel
    func cancelAction() {
        pendingActionSummary = nil
        pendingTool = nil
        pendingArguments = nil
        responseText = "Okay, cancelled — nothing was changed."
    }

    private func postExecute(tool: String, arguments: [String: Any], summary: String) async {
        guard let url = URL(string: "\(SERVER_BASE_URL)/execute") else {
            errorMessage = "Invalid server URL"; isStreaming = false; return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["tool": tool, "arguments": arguments]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? String {
                responseText = result
            } else {
                responseText = "Done."
            }
        } catch {
            errorMessage = "Execute failed: \(error.localizedDescription)"
        }
        isStreaming = false
        pendingTool = nil
        pendingArguments = nil
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task { @MainActor in
            self.processBuffer(data)
        }
    }

    private func processBuffer(_ data: Data) {
        for event in parser.feed(data) {
            handle(event)
        }
    }

    /// Applies one stream event to the published UI state.
    func handle(_ event: SSEEvent) {
        switch event {
        case .done:
            isStreaming = false
            statusMessage = nil
        case .token(let content):
            if statusMessage != nil { statusMessage = nil }
            responseText += content
        case .status(let content):
            statusMessage = content
        case .confirm(let tool, let arguments, let summary):
            statusMessage = nil
            pendingTool = tool
            pendingArguments = arguments
            pendingActionSummary = summary
            isStreaming = false
        case .error(let content):
            errorMessage = content
            isStreaming = false
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            self.isStreaming = false
            self.statusMessage = nil
            if let error = error {
                self.errorMessage = "Connection error: \(error.localizedDescription)"
            }
        }
    }
}
