import Foundation
import Network

/// Discovers a ScreenshotMatcher host on the local WiFi network via
/// Bonjour/mDNS instead of raw UDP broadcast.
///
/// The Python server registers itself as a Bonjour service of type
/// `_shotmatcher._tcp` (via the `zeroconf` package) advertising its
/// HTTP upload port. The phone browses for that service type using
/// `NWBrowser` and resolves the first result to an IP + port.
///
/// This replaces an earlier UDP-broadcast-based implementation, which
/// turned out to be unreliable on this network's Fritz!Powerline WiFi
/// extender setup: a directed broadcast computed from a wrong assumed
/// subnet mask (/24 instead of the network's actual /16) never reached the
/// Mac. Bonjour/mDNS is the platform-native mechanism for this kind of
/// local service discovery and is handled by the OS network stack rather
/// than hand-rolled broadcast logic, so it isn't subject to that class of
/// bug and tends to traverse extenders/mesh setups more reliably.
enum ConnectionState: Equatable {
    case searching
    case connected
    case notFound
    case failed(String)
}

@MainActor
final class DiscoveryService: ObservableObject {
    @Published private(set) var hostAddress: String?
    @Published private(set) var hostPort: UInt16?
    @Published private(set) var hostName: String?
    @Published private(set) var connectionState: ConnectionState = .notFound
    @Published private(set) var logLines: [String] = []

    private static let serviceType = "_shotmatcher._tcp"
    private static let maxLogLines = 200

    private var browser: NWBrowser?
    private var resolveConnection: NWConnection?
    private var timeoutTask: Task<Void, Never>?

    func startDiscovery() {
        stopDiscovery()
        hostAddress = nil
        hostPort = nil
        hostName = nil
        connectionState = .searching
        log("Searching for host…")

        let params = NWParameters()
        params.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: params)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.log("browser state: \(state)")
                if case .failed(let error) = state {
                    self?.connectionState = .failed(error.localizedDescription)
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self, let first = results.first else { return }
                self.log("found service: \(first.endpoint)")
                if case let .service(name, _, _, _) = first.endpoint {
                    self.hostName = name
                }
                self.resolve(first.endpoint)
            }
        }
        browser.start(queue: .main)
        self.browser = browser

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.hostAddress == nil {
                self.connectionState = .notFound
                self.log("Timed out, no host found")
            }
        }
    }

    func stopDiscovery() {
        timeoutTask?.cancel()
        timeoutTask = nil
        resolveConnection?.cancel()
        resolveConnection = nil
        browser?.cancel()
        browser = nil
    }

    /// Bypasses discovery entirely — used as a manual fallback if Bonjour
    /// doesn't work on a given network either.
    func connectManually(host: String, port: UInt16) {
        stopDiscovery()
        hostAddress = host
        hostPort = port
        hostName = host
        connectionState = .connected
        log("Connected to \(host):\(port) (manual)")
    }

    /// Resolves a Bonjour endpoint to a concrete IP + port by opening a
    /// connection to it and reading back the resolved path.
    private func resolve(_ endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        resolveConnection = connection

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    if let remote = connection.currentPath?.remoteEndpoint,
                       case let .hostPort(host, port) = remote {
                        self.applyResolved(host: host, port: port.rawValue)
                    }
                    connection.cancel()
                case .failed(let error):
                    self.log("resolve failed: \(error)")
                    self.connectionState = .failed(error.localizedDescription)
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }

    private func applyResolved(host: NWEndpoint.Host, port: UInt16) {
        let address: String
        switch host {
        case .ipv4(let ipv4):
            let bytes = ipv4.rawValue
            address = bytes.map { String($0) }.joined(separator: ".")
        default:
            address = "\(host)".components(separatedBy: "%").first ?? "\(host)"
        }

        hostAddress = address
        hostPort = port
        connectionState = .connected
        log("Resolved to \(address):\(port)")
    }

    private func log(_ message: String) {
        print("[Discovery] \(message)")
        logLines.append(message)
        if logLines.count > Self.maxLogLines {
            logLines.removeFirst(logLines.count - Self.maxLogLines)
        }
    }
}
