import Foundation
import Network

/// Serves the web surface over HTTP and talks to connected surfaces over a WebSocket.
///
/// HTTP (default port 8080) serves static files from a folder. The WebSocket
/// (HTTP port + 1) carries small JSON messages both ways. Browsers can't send raw
/// UDP, so continuous lane values use the WebSocket too; each message carries only
/// the latest value, so a late one is simply superseded.
public final class ControlServer {
    public typealias ClientID = Int

    public let httpPort: UInt16
    public var wsPort: UInt16 { httpPort + 1 }
    private let root: URL
    private let queue = DispatchQueue(label: "tj.control")
    private var http: NWListener?
    private var ws: NWListener?
    private var clients: [ClientID: NWConnection] = [:]
    private var nextID = 1

    /// Called on the main queue with each JSON message from a surface.
    public var onMessage: ((ClientID, [String: Any]) -> Void)?
    /// Called on the main queue when the set of connected surfaces changes.
    public var onClientsChanged: ((Int) -> Void)?

    public init(root: URL, httpPort: UInt16 = 8080) {
        self.root = root
        self.httpPort = httpPort
    }

    public func start() throws {
        let h = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: httpPort)!)
        h.newConnectionHandler = { [weak self] c in self?.serveHTTP(c) }
        h.start(queue: queue)
        http = h

        let params = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        params.allowLocalEndpointReuse = true
        let w = try NWListener(using: params, on: NWEndpoint.Port(rawValue: wsPort)!)
        w.newConnectionHandler = { [weak self] c in self?.accept(c) }
        w.start(queue: queue)
        ws = w
    }

    // MARK: WebSocket

    private func accept(_ c: NWConnection) {
        let id = nextID; nextID += 1
        clients[id] = c
        c.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.drop(id)
            default: break
            }
        }
        c.start(queue: queue)
        receive(id, c)
        notifyClients()
    }

    private func receive(_ id: ClientID, _ c: NWConnection) {
        c.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                DispatchQueue.main.async { self.onMessage?(id, obj) }
            }
            if error != nil { self.drop(id); return }
            self.receive(id, c)
        }
    }

    private func drop(_ id: ClientID) {
        guard let c = clients.removeValue(forKey: id) else { return }
        c.cancel()
        notifyClients()
        DispatchQueue.main.async { self.onMessage?(id, ["t": "disconnect"]) }
    }

    private func notifyClients() {
        let n = clients.count
        DispatchQueue.main.async { self.onClientsChanged?(n) }
    }

    /// Sends a JSON message to every connected surface.
    public func broadcast(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        queue.async {
            let meta = NWProtocolWebSocket.Metadata(opcode: .text)
            let ctx = NWConnection.ContentContext(identifier: "msg", metadata: [meta])
            for c in self.clients.values {
                c.send(content: data, contentContext: ctx, isComplete: true, completion: .idempotent)
            }
        }
    }

    // MARK: HTTP (static files only)

    private func serveHTTP(_ c: NWConnection) {
        c.start(queue: queue)
        c.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { c.cancel(); return }
            let parts = request.split(separator: " ", maxSplits: 2)
            var path = parts.count > 1 ? String(parts[1]) : "/"
            if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
            if path == "/" { path = "/index.html" }
            let name = path.split(separator: "/").last.map(String.init) ?? ""
            // Only plain file names from the surface folder; no paths.
            let file = self.root.appendingPathComponent(name)
            let body: Data, status: String, type: String
            if !name.isEmpty, !name.hasPrefix("."), let d = try? Data(contentsOf: file) {
                body = d; status = "200 OK"; type = Self.contentType(name)
            } else {
                body = Data("not found".utf8); status = "404 Not Found"; type = "text/plain"
            }
            var head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\n"
            head += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
            c.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
        }
    }

    static func contentType(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "json": return "application/json"
        case "webmanifest": return "application/manifest+json"
        default: return "application/octet-stream"
        }
    }

    // MARK: Address

    /// The Mac's LAN IPv4 address, for the connect URL.
    public static func lanAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var fallback: String?
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = p.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let addr = String(cString: host)
            if name == "en0" { return addr }
            fallback = fallback ?? addr
        }
        return fallback
    }
}
