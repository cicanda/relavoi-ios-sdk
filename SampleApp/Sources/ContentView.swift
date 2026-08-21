import SwiftUI
import RelavoiSDK

struct ContentView: View {
    // Bolt Nigeria test tenant — live backend. Paste the test key/secret here
    // before running (shared out-of-band; NOT committed to git). The tenant ID is
    // not a secret. See README.md.
    private let apiKey = "PASTE_YOUR_API_KEY"
    private let apiSecret = "PASTE_YOUR_API_SECRET"
    private let tenantId = "f656ac1b-3b5d-4af0-8ff1-c4cbc1076144"

    @StateObject private var logStore = LogStore()

    @State private var agentPhone = "+2347067379297"
    @State private var customerPhone = "+2348162662319"
    @State private var userPhone = "+2347067379297"

    @State private var currentSessionId: String?
    @State private var didInit = false
    @State private var eventsListenerAttached = false

    var body: some View {
        VStack(spacing: 8) {
            Text("Relavoi iOS SDK — Test Harness").font(.headline)

            labeledField("Agent phone", text: $agentPhone)
            labeledField("Customer phone", text: $customerPhone)
            labeledField("User phone (verify/presence)", text: $userPhone)

            ScrollView {
                VStack(spacing: 6) {
                    button("Initialize SDK") { initializeSDK() }
                    button("Create Session") { createSession() }
                    button("Get Session") { getSession() }
                    button("Initiate Call (native dialer)") { initiateCall() }
                    button("Verify Call") { verifyCall() }
                    button("Connect Events (WebSocket)") { connectEvents() }
                    button("Update Presence") { updatePresence() }
                    button("End Session") { endSession() }
                    button("List Sessions") { listSessions() }
                    button("Clear Log") { logStore.clear() }
                }
            }
            .frame(maxHeight: 300)

            Text("── SDK log ──").font(.caption).foregroundColor(.secondary)
            SDKLogView(store: logStore)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .cornerRadius(6)
        }
        .padding()
    }

    // ─── UI helpers ─────────────────────────────────────────────────────────

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .keyboardType(.phonePad)
        }
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func requireInit() -> Bool {
        if !didInit { logStore.log("Tap 'Initialize SDK' first"); return false }
        return true
    }

    // ─── SDK actions ────────────────────────────────────────────────────────

    private func initializeSDK() {
        guard !didInit else { logStore.log("SDK already initialized"); return }
        Relavoi.initialize(
            apiKey: apiKey,
            apiSecret: apiSecret,
            tenantId: tenantId,
            config: RelavoiConfig(
                baseURL: URL(string: "https://api.relavoi.com/v1")!,
                enableLogging: true
            )
        )
        didInit = true
        logStore.log("SDK initialized → https://api.relavoi.com/v1 (tenant \(tenantId))")
    }

    private func createSession() {
        guard requireInit() else { return }
        Task {
            do {
                logStore.log("Creating session (\(agentPhone) → \(customerPhone))…")
                let s = try await Relavoi.shared.sessions.create(
                    agentPhone: agentPhone,
                    customerPhone: customerPhone,
                    metadata: ["orderId": "SDK-TEST-001", "type": "delivery"]
                )
                currentSessionId = s.id
                logStore.log("Session created: \(s.id)")
                logStore.log("  proxy=\(s.proxyNumber) state=\(s.state.rawValue) dir=\(s.directionMode.rawValue)")
            } catch {
                logStore.log("ERROR create: \(error)")
            }
        }
    }

    private func getSession() {
        guard requireInit() else { return }
        guard let id = currentSessionId else { logStore.log("No session — Create Session first"); return }
        Task {
            do {
                let s = try await Relavoi.shared.sessions.get(id)
                logStore.log("Session \(id): state=\(s.state.rawValue) proxy=\(s.proxyNumber) calls=\(s.callCount ?? 0)")
            } catch {
                logStore.log("ERROR get: \(error)")
            }
        }
    }

    private func initiateCall() {
        guard requireInit() else { return }
        guard let id = currentSessionId else { logStore.log("No session — Create Session first"); return }
        Task {
            do {
                try await Relavoi.shared.sessions.initiateCall(sessionId: id)
                logStore.log("initiateCall(\(id)) → native dialer opened with proxy number")
            } catch {
                logStore.log("ERROR initiateCall: \(error)")
            }
        }
    }

    private func verifyCall() {
        guard requireInit() else { return }
        Task {
            logStore.log("callActive=\(Relavoi.shared.verification.isCallActive)")
            do {
                let r = try await Relavoi.shared.verification.verify(userPhone: userPhone)
                logStore.log("verified=\(r.verified) context=\(r.context ?? "—") session=\(r.sessionId ?? "—")")
            } catch {
                logStore.log("ERROR verify: \(error)")
            }
        }
    }

    private func connectEvents() {
        guard requireInit() else { return }
        let store = logStore
        Task {
            if !eventsListenerAttached {
                Relavoi.shared.events.addListener("sample") { event in
                    store.log("EVENT \(Self.describe(event))")
                }
                eventsListenerAttached = true
                store.log("Event listener attached")
            }
            await Relavoi.shared.events.connect()
            let connected = await Relavoi.shared.events.isConnected
            store.log("events.connect() called — connected=\(connected)")
        }
    }

    private func updatePresence() {
        guard requireInit() else { return }
        // Presence is automatic once a user phone is set (SDK observes app lifecycle).
        Relavoi.shared.presence.setUserPhone(userPhone)
        logStore.log("Presence user set to \(userPhone) — SDK auto-reports online/background/offline")
    }

    private func endSession() {
        guard requireInit() else { return }
        guard let id = currentSessionId else { logStore.log("No session — Create Session first"); return }
        Task {
            do {
                let s = try await Relavoi.shared.sessions.end(id)
                logStore.log("Session ended: \(s.id) → \(s.state.rawValue)")
                currentSessionId = nil
            } catch {
                logStore.log("ERROR end: \(error)")
            }
        }
    }

    private func listSessions() {
        guard requireInit() else { return }
        Task {
            do {
                let resp = try await Relavoi.shared.sessions.list()
                logStore.log("Sessions: \(resp.pagination.count) returned")
                for s in resp.data {
                    logStore.log("  \(s.id.prefix(8))… \(s.state.rawValue) proxy=\(s.proxyNumber)")
                }
            } catch {
                logStore.log("ERROR list: \(error)")
            }
        }
    }

    // ─── Event formatting ─────────────────────────────────────────────────────

    private static func describe(_ e: RelavoiEvent) -> String {
        switch e {
        case let .sessionCreated(sessionId, proxyNumber, _): return "session.created \(sessionId) proxy=\(proxyNumber)"
        case let .sessionActivated(sessionId, _): return "session.activated \(sessionId)"
        case let .sessionExpired(sessionId, _): return "session.expired \(sessionId)"
        case let .callIncoming(sessionId, callerNumber, _): return "call.incoming \(sessionId) caller=\(callerNumber)"
        case let .callAnswered(sessionId, _): return "call.answered \(sessionId)"
        case let .callEnded(sessionId, durationSeconds, _): return "call.ended \(sessionId) dur=\(durationSeconds)s"
        case let .smsReceived(sessionId, _): return "sms.received \(sessionId)"
        case let .unknown(type, _): return "unknown type=\(type)"
        }
    }
}
