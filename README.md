# Personal Agent — iOS Client

A SwiftUI iPhone app for talking to a self-hosted LLM agent that runs on your Mac.
Responses stream in token by token, the app shows what the agent is working on,
and any action that would **change something** (a write action) has to be approved
on the phone before the server runs it.

> This repository contains the **iOS client only**. The agent server (model, tools,
> and the `/chat/stream` and `/execute` endpoints) runs separately on your Mac.
> The protocol the app expects is documented [below](#server-protocol).

## Features

- **Streaming responses** over Server-Sent Events (SSE)
- **Live status line** showing the agent's current step (e.g. "Working on: …")
- **Human-in-the-loop confirmation** for write actions: the agent proposes, you tap
  **Confirm** or **Cancel**, and nothing changes unless you confirm
- **Error reporting** for connection failures and server-side errors
- Plain SwiftUI + `URLSession`, with no third-party dependencies

## Requirements

| | |
|---|---|
| Xcode | 26.6 or later |
| iOS | 26.5 or later (iPhone and iPad) |
| Server | An agent server on the same local network that implements the [protocol](#server-protocol) |

## Getting started

1. Clone the repo and open `PersonalAgent.xcodeproj` in Xcode.
2. Find your Mac's local IP address:
   ```sh
   ipconfig getifaddr en0
   ```
3. Set it in `PersonalAgent/ChatClient.swift`:
   ```swift
   let SERVER_BASE_URL = "http://<your-mac-ip>:8000"
   ```
4. Start your agent server on the Mac, listening on `0.0.0.0:8000`.
5. In **Signing & Capabilities**, choose your own development team. Then build and
   run on a simulator or on an iPhone connected to the same Wi-Fi network.

## Project structure

```
PersonalAgent/
├── PersonalAgentApp.swift   # App entry point
├── ContentView.swift        # Chat screen: response, status line, confirmation card, input
├── ChatClient.swift         # Networking + UI state (ObservableObject)
├── SSEParser.swift          # Incremental SSE parser → typed SSEEvent values
├── Info.plist               # Allows plain HTTP to the local server
└── Assets.xcassets
PersonalAgentTests/
└── PersonalAgentTests.swift # Unit tests (Swift Testing)
```

### How it works

```
ContentView ──sendMessage──▶ ChatClient ──POST /chat/stream──▶ agent server
     ▲                          │  ▲                                │
     │  @Published state        │  └──── SSE bytes ◀────────────────┘
     └──────────────────────────┘        │
                                 SSEParser.feed(_:) → [SSEEvent]
                                         │
                                 ChatClient.handle(_:)
```

When a `confirm` event arrives, `ChatClient` holds the proposed tool call and the UI
shows the confirmation card. **Confirm** sends `POST /execute` and **Cancel** discards
the proposed call.

## Server protocol

### `POST /chat/stream`

Request:

```json
{ "message": "What's on my calendar tomorrow?", "max_tokens": 512 }
```

The response is `text/event-stream`. Each event is one line, `data: <payload>`,
followed by a blank line:

| Payload | Meaning |
|---|---|
| `{"type":"token","content":"Hel"}` | Append text to the response |
| `{"type":"status","content":"Working on: calendar"}` | Show a progress line |
| `{"type":"confirm","tool":"create_event","arguments":{...},"summary":"Add 'Dentist' on Friday"}` | Ask the user to approve a write action; the stream stops here |
| `{"type":"error","content":"..."}` | Show an error and stop |
| `[DONE]` | End of stream |

Unknown event types and malformed lines are ignored.

### `POST /execute`

Sent only after the user taps **Confirm**:

```json
{ "tool": "create_event", "arguments": { "title": "Dentist", "day": "Friday" } }
```

Response:

```json
{ "result": "Added 'Dentist' to your calendar on Friday." }
```

## Running tests

In Xcode, press **⌘U**. To run from the command line:

```sh
xcodebuild test \
  -project PersonalAgent.xcodeproj \
  -scheme PersonalAgent \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

The 10 unit tests cover:

- **SSE parsing:** single events, events split across network chunks, several events
  in one chunk, the `[DONE]` sentinel, confirm payloads, and skipping malformed or
  unknown input.
- **Client state:** tokens accumulating into the response, the confirmation card
  appearing, cancelling a pending action, and error and done events ending the stream.

No network access is needed to run the tests.

## Security notes

This app is meant for personal use on a trusted home network:

- Traffic is **plain HTTP**. `NSAllowsArbitraryLoads` is enabled in `Info.plist`.
- The server has **no authentication**. Anyone on the same network can reach it.

Before using it on any other network, put the server behind HTTPS (for example
Tailscale or a reverse proxy), add a token, and replace `NSAllowsArbitraryLoads`
with an `NSExceptionDomains` entry for that one host.

## Roadmap

- [ ] Conversation history (currently each message replaces the last response)
- [ ] Server URL configurable in-app instead of hardcoded
- [ ] Auth token + HTTPS
- [ ] Surface `/execute` HTTP errors instead of showing "Done."
- [ ] App icon

## License

No license has been chosen yet. All rights reserved by the author until one is added.
