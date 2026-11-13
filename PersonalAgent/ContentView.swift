import SwiftUI

struct ContentView: View {
    @StateObject private var client = ChatClient()
    @State private var inputText: String = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                ScrollView {
                    Text(client.responseText.isEmpty ? "Response will appear here..." : client.responseText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .foregroundColor(client.responseText.isEmpty ? .gray : .primary)
                }
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                // Status banner (e.g. "Working on: ...")
                if let status = client.statusMessage {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(status).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }

                // Confirmation card for write actions
                if let pending = client.pendingActionSummary {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Confirm action", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundColor(.orange)
                        Text(pending)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button(role: .cancel) { client.cancelAction() } label: {
                                Text("Cancel").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button { client.confirmAction() } label: {
                                Text("Confirm").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.5), lineWidth: 1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                if let error = client.errorMessage {
                    Text(error).foregroundColor(.red).font(.caption).padding(.horizontal)
                }

                HStack {
                    TextField("Ask something...", text: $inputText)
                        .textFieldStyle(.roundedBorder)
                    Button(action: sendMessage) {
                        if client.isStreaming {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.up.circle.fill").font(.title2)
                        }
                    }
                    .disabled(inputText.isEmpty || client.isStreaming)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Personal Agent")
        }
    }

    private func sendMessage() {
        let message = inputText
        inputText = ""
        client.sendMessage(message)
    }
}

#Preview {
    ContentView()
}
