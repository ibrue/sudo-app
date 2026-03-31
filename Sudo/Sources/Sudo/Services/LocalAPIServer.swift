import Foundation
import Network

/// Local HTTP API server for programmatic control of the sudo pad.
///
/// Endpoints:
///   GET  /status          → device status, detected app, connection state
///   GET  /log             → recent action history
///   POST /trigger/:action → trigger an action (approve, reject, action3, action4)
///   GET  /config          → current button mappings and settings
///
/// Authentication: Bearer token via X-API-Key header
/// Default port: 7483 (S-U-D-O on phone keypad... close enough)
final class LocalAPIServer: ObservableObject {
    @Published var isRunning = false
    @Published var requestCount = 0

    private var listener: NWListener?
    private weak var engine: SudoEngine?

    func start(engine: SudoEngine) {
        guard SudoSettings.shared.apiEnabled else { return }
        self.engine = engine

        let port = NWEndpoint.Port(integerLiteral: UInt16(SudoSettings.shared.apiPort))
        do {
            listener = try NWListener(using: .tcp, on: port)
        } catch {
            print("[sudo-api] Failed to create listener: \(error)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[sudo-api] Server listening on port \(SudoSettings.shared.apiPort)")
                DispatchQueue.main.async { self?.isRunning = true }
            case .failed(let error):
                print("[sudo-api] Server failed: \(error)")
                DispatchQueue.main.async { self?.isRunning = false }
            default:
                break
            }
        }

        listener?.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async { self.isRunning = false }
        print("[sudo-api] Server stopped")
    }

    func restart(engine: SudoEngine) {
        stop()
        start(engine: engine)
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else {
                connection.cancel()
                return
            }

            let request = String(data: data, encoding: .utf8) ?? ""
            let response = self.routeRequest(request)

            DispatchQueue.main.async { self.requestCount += 1 }

            let httpResponse = "HTTP/1.1 \(response.status)\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n\(response.body)"
            connection.send(content: httpResponse.data(using: .utf8), completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        }
    }

    private struct HTTPResponse {
        let status: String
        let body: String

        static func ok(_ json: String) -> HTTPResponse { HTTPResponse(status: "200 OK", body: json) }
        static func error(_ code: Int, _ message: String) -> HTTPResponse {
            HTTPResponse(status: "\(code) Error", body: "{\"error\":\"\(message)\"}")
        }
    }

    private func routeRequest(_ raw: String) -> HTTPResponse {
        let lines = raw.split(separator: "\r\n", maxSplits: 1)
        guard let firstLine = lines.first else { return .error(400, "Bad request") }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return .error(400, "Bad request") }

        let method = String(parts[0])
        let path = String(parts[1])

        // Auth check
        let apiKey = SudoSettings.shared.apiKey
        if !raw.contains("X-API-Key: \(apiKey)") && !path.contains("apikey=\(apiKey)") {
            return .error(401, "Unauthorized — set X-API-Key header or ?apikey= param")
        }

        // CORS preflight
        if method == "OPTIONS" {
            return HTTPResponse(status: "204 No Content", body: "")
        }

        // Route
        if method == "GET" && path.hasPrefix("/status") {
            return handleStatus()
        } else if method == "GET" && path.hasPrefix("/log") {
            return handleLog()
        } else if method == "GET" && path.hasPrefix("/config") {
            return handleConfig()
        } else if method == "POST" && path.hasPrefix("/trigger/") {
            let action = String(path.dropFirst("/trigger/".count)).split(separator: "?").first.map(String.init) ?? ""
            return handleTrigger(action: action)
        } else if method == "POST" && path.hasPrefix("/mcp/request-approval") {
            return handleMCPRequestApproval(raw)
        } else if method == "GET" && path.hasPrefix("/mcp/status") {
            return handleMCPStatus()
        } else if method == "GET" && path.hasPrefix("/debug/ax-tree") {
            return handleAXTree(path: path)
        } else if method == "GET" && path.hasPrefix("/debug/ax-search") {
            return handleAXSearch(path: path)
        } else if method == "GET" && path.hasPrefix("/debug/pipeline-test") {
            return handlePipelineTest(path: path)
        } else {
            return .error(404, "Not found. Endpoints: GET /status, GET /log, POST /trigger/:action, GET /config, POST /mcp/request-approval, GET /mcp/status, GET /debug/ax-tree, GET /debug/ax-search, GET /debug/pipeline-test")
        }
    }

    // MARK: - Endpoint handlers

    private func handleStatus() -> HTTPResponse {
        guard let engine = engine else { return .error(500, "Engine not available") }
        let json = """
        {
          "connected": \(engine.isConnected),
          "processing": \(engine.isProcessing),
          "detected_app": "\(engine.detectedApp)",
          "last_action": "\(engine.lastAction)",
          "last_method": "\(engine.lastMethod)",
          "version": "\(OTAUpdater.currentVersion)"
        }
        """
        return .ok(json)
    }

    private func handleLog() -> HTTPResponse {
        guard let engine = engine else { return .error(500, "Engine not available") }
        let entries = engine.actionLog.prefix(20).map { entry in
            """
            {"time":"\(entry.timeString)","action":"\(entry.action)","app":"\(entry.app)","method":"\(entry.method)","success":\(entry.succeeded)}
            """
        }
        return .ok("[\(entries.joined(separator: ","))]")
    }

    private func handleConfig() -> HTTPResponse {
        let buttons = PadAction.allCases.map { action in
            let terms = SudoSettings.shared.searchTerms(for: action).map { "\"\($0)\"" }.joined(separator: ",")
            return """
            {"key":"F\(action.fKeyNumber)","name":"\(action.displayName)","search_terms":[\(terms)]}
            """
        }
        return .ok("{\"buttons\":[\(buttons.joined(separator: ","))]}")
    }

    private func handleTrigger(action actionName: String) -> HTTPResponse {
        guard let engine = engine else { return .error(500, "Engine not available") }
        guard let action = PadAction.allCases.first(where: { $0.rawValue == actionName }) else {
            return .error(400, "Unknown action '\(actionName)'. Valid: approve, reject, action3, action4")
        }

        engine.triggerAction(action)
        return .ok("{\"triggered\":\"\(action.rawValue)\",\"display_name\":\"\(action.displayName)\"}")
    }

    // MARK: - MCP Endpoints

    private func handleMCPRequestApproval(_ raw: String) -> HTTPResponse {
        guard let engine = engine else { return .error(500, "Engine not available") }

        // Parse JSON body from the raw HTTP request
        let prompt: String
        let timeout: TimeInterval

        if let bodyStart = raw.range(of: "\r\n\r\n") {
            let bodyString = String(raw[bodyStart.upperBound...])
            if let bodyData = bodyString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                prompt = json["prompt"] as? String ?? "approval requested"
                timeout = json["timeout"] as? TimeInterval ?? 30
            } else {
                prompt = "approval requested"
                timeout = 30
            }
        } else {
            prompt = "approval requested"
            timeout = 30
        }

        // This blocks until the user presses approve/reject or timeout
        let result = engine.waitForMCPApproval(prompt: prompt, timeout: timeout)

        let action = result.approved ? "approve" : "reject"
        return .ok("{\"approved\":\(result.approved),\"action\":\"\(action)\",\"time_ms\":\(result.timeMs)}")
    }

    // MARK: - Debug Endpoints

    private func handleAXTree(path: String) -> HTTPResponse {
        let inspector = AXInspector()

        // Parse optional pid from query string
        if let pidStr = parseQueryParam(path: path, key: "pid"),
           let pid = Int32(pidStr) {
            let node = inspector.dumpTree(pid: pid)
            return .ok(node.asJSON)
        }

        // Default: frontmost app
        guard let result = inspector.dumpFrontmostTree() else {
            return .error(500, "No frontmost app found")
        }

        let wrapper = """
        {"app":"\(result.appName)","pid":\(result.pid),"tree":\(result.node.asJSON)}
        """
        return .ok(wrapper)
    }

    private func handleAXSearch(path: String) -> HTTPResponse {
        let termsStr = parseQueryParam(path: path, key: "terms") ?? "Allow,Approve,Yes"
        let terms = termsStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        guard let front = NSWorkspace.shared.frontmostApplication else {
            return .error(500, "No frontmost app")
        }

        let inspector = AXInspector()
        let results = inspector.searchElements(pid: front.processIdentifier, terms: terms)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(results) else {
            return .error(500, "Failed to encode results")
        }

        let json = String(data: data, encoding: .utf8) ?? "[]"
        let wrapper = """
        {"app":"\(front.localizedName ?? "unknown")","pid":\(front.processIdentifier),"terms":"\(termsStr)","results":\(json)}
        """
        return .ok(wrapper)
    }

    private func handlePipelineTest(path: String) -> HTTPResponse {
        let actionName = parseQueryParam(path: path, key: "action") ?? "approve"
        guard let action = PadAction.allCases.first(where: { $0.rawValue == actionName }) else {
            return .error(400, "Unknown action '\(actionName)'. Valid: approve, reject, action3, action4")
        }

        let inspector = AXInspector()
        guard let result = inspector.runPipelineTest(action: action) else {
            return .error(500, "No frontmost app")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(result),
              let json = String(data: data, encoding: .utf8) else {
            return .error(500, "Failed to encode result")
        }
        return .ok(json)
    }

    private func parseQueryParam(path: String, key: String) -> String? {
        guard let queryStart = path.firstIndex(of: "?") else { return nil }
        let query = String(path[path.index(after: queryStart)...])
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 && parts[0] == key {
                return String(parts[1]).removingPercentEncoding
            }
        }
        return nil
    }

    private func handleMCPStatus() -> HTTPResponse {
        guard let engine = engine else { return .error(500, "Engine not available") }
        let hasPending = engine.pendingMCPRequest != nil
        return .ok("{\"accepting_requests\":true,\"has_pending_request\":\(hasPending)}")
    }
}

// MARK: - Webhook support

/// Fires webhooks to a user-configured URL on each button press.
final class WebhookManager {
    static let shared = WebhookManager()

    func fire(action: PadAction, app: String, method: String, success: Bool) {
        let url = SudoSettings.shared.webhookURL
        guard !url.isEmpty, let endpoint = URL(string: url) else { return }

        let payload: [String: Any] = [
            "event": "action",
            "action": action.rawValue,
            "display_name": action.displayName,
            "app": app,
            "method": method,
            "success": success,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SudoSettings.shared.apiKey, forHTTPHeaderField: "X-API-Key")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("[sudo-webhook] Failed: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse {
                print("[sudo-webhook] \(http.statusCode) → \(url)")
            }
        }.resume()
    }
}
