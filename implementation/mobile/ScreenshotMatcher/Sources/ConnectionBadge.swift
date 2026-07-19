import SwiftUI

/// Compact "connected to <host>" pill by default; tapping it opens a sheet
/// with the full discovery log and a manual-connect option, so day-to-day
/// use only shows the one piece of info that matters (which PC you're
/// talking to) while diagnostics stay a tap away.
struct ConnectionBadge: View {
    @ObservedObject var discovery: DiscoveryService
    @Binding var algorithmRawValue: String
    @State private var showDetails = false

    var body: some View {
        Button {
            showDetails = true
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                Text(compactLabel)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                if discovery.connectionState == .searching {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .sheet(isPresented: $showDetails) {
            ConnectionDetailsView(discovery: discovery, algorithmRawValue: $algorithmRawValue)
                .presentationDetents([.medium, .large])
        }
    }

    private var dotColor: Color {
        switch discovery.connectionState {
        case .connected: return .green
        case .searching: return .yellow
        case .notFound: return .red
        case .failed: return .red
        }
    }

    private var compactLabel: String {
        switch discovery.connectionState {
        case .connected: return discovery.hostName ?? discovery.hostAddress ?? "Connected"
        case .searching: return "Searching…"
        case .notFound: return "No host found"
        case .failed: return "Connection failed"
        }
    }
}

private struct ConnectionDetailsView: View {
    @ObservedObject var discovery: DiscoveryService
    @Binding var algorithmRawValue: String
    @Environment(\.dismiss) private var dismiss
    @State private var showManualConnect = false

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    LabeledContent("State", value: stateDescription)
                    if let hostName = discovery.hostName {
                        LabeledContent("Host", value: hostName)
                    }
                    if let address = discovery.hostAddress, let port = discovery.hostPort {
                        LabeledContent("Address", value: "\(address):\(port)")
                    }
                }

                Section("Matching") {
                    Picker("Algorithm", selection: $algorithmRawValue) {
                        ForEach(MatchingAlgorithm.allCases) { algorithm in
                            Text(algorithm.displayName).tag(algorithm.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Log") {
                    if discovery.logLines.isEmpty {
                        Text("No activity yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(discovery.logLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("Search again") {
                        discovery.startDiscovery()
                    }
                    Button("Connect manually…") {
                        showManualConnect = true
                    }
                }
            }
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showManualConnect) {
                ManualConnectView(discovery: discovery)
                    .presentationDetents([.medium])
            }
        }
    }

    private var stateDescription: String {
        switch discovery.connectionState {
        case .connected: return "Connected"
        case .searching: return "Searching"
        case .notFound: return "No host found"
        case .failed(let message): return "Failed: \(message)"
        }
    }
}

private struct ManualConnectView: View {
    @ObservedObject var discovery: DiscoveryService
    @Environment(\.dismiss) private var dismiss
    @State private var host: String = ""
    @State private var port: String = "8000"

    var body: some View {
        NavigationStack {
            Form {
                Section("Host") {
                    TextField("IP address, e.g. 192.168.2.83", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Connect Manually")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        guard let portNumber = UInt16(port), !host.isEmpty else { return }
                        discovery.connectManually(host: host, port: portNumber)
                        dismiss()
                    }
                    .disabled(host.isEmpty || UInt16(port) == nil)
                }
            }
        }
    }
}
