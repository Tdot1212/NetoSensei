import SwiftUI

struct UniFiClientsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var console = ""
    @State private var site = ""
    @State private var key = ""
    @State private var consoles: [UniFiClients.Choice] = []
    @State private var sites: [UniFiClients.Choice] = []
    @State private var clients: [UniFiClients.Client] = []
    @State private var total: Int?
    @State private var offset = 0
    @State private var error: String?
    @State private var operation: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SecureField("UniFi API key", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Find my consoles") { findChoices(findSites: false) }.disabled(key.isEmpty)
                    if !consoles.isEmpty {
                        Picker("Console", selection: $console) {
                            Text("Select").tag("")
                            ForEach(consoles) { Text($0.title).tag($0.id) }
                        }
                        Button("Find sites") { findChoices(findSites: true) }.disabled(console.isEmpty)
                    }
                    if !sites.isEmpty {
                        Picker("Site", selection: $site) {
                            Text("Select").tag("")
                            ForEach(sites) { Text($0.title).tag($0.id) }
                        }
                    }
                    DisclosureGroup("Enter IDs manually") {
                        TextField("Console ID", text: $console)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Site UUID", text: $site)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    if operation != nil {
                        ProgressView("Reading the UniFi client list…")
                    } else {
                        Button(total == nil ? "Read connected clients" : "Refresh client list") { load(reset: true) }
                            .disabled(console.isEmpty || site.isEmpty || key.isEmpty)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text("UniFi Connector")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Use a UniFi console with Connector support. Requests go directly to Ubiquiti. The key stays in this screen for this session.")
                        Link("UniFi API setup", destination: URL(string: "https://help.ui.com/hc/en-us/articles/30076656117655-Getting-Started-with-the-Official-UniFi-API")!)
                    }
                }
                .disabled(operation != nil)
                if let total {
                    Section {
                        ForEach(clients) { client in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(client.displayName).font(.headline)
                                Text([client.connection, client.ipAddress, client.macAddress].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if offset < total {
                            Button("Load more clients") { load(reset: false) }
                                .disabled(operation != nil)
                        }
                    } header: {
                        Text("Showing \(clients.count) · \(total) reported by UniFi")
                    } footer: {
                        Text("This site can include wired, Wi-Fi and VPN clients. Use UniFi’s own controls to manage access.")
                    }
                }
            }
            .navigationTitle("UniFi Clients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: console) { _, _ in
                sites = []
                site = ""
                clearResults()
            }
            .onChange(of: site) { _, _ in clearResults() }
            .onChange(of: key) { _, _ in
                consoles = []
                sites = []
                clearResults()
            }
            .onDisappear { operation?.cancel(); key = "" }
        }
    }

    private func clearResults() {
        clients = []
        total = nil
        offset = 0
        error = nil
    }

    private func findChoices(findSites: Bool) {
        guard operation == nil else { return }
        error = nil
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                if findSites {
                    sites = try await UniFiClients.sites(console: console, key: key)
                    if sites.count == 1 { site = sites[0].id }
                    if sites.isEmpty { error = "UniFi reports no sites for this console." }
                } else {
                    consoles = try await UniFiClients.consoles(key: key)
                    if consoles.count == 1 { console = consoles[0].id }
                    if consoles.isEmpty { error = "UniFi reports no consoles for this key." }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = (error as? UniFiClients.Failure)?.errorDescription ?? "Couldn’t read the UniFi setup. Check your connection and try again."
            }
        }
    }

    private func load(reset: Bool) {
        guard operation == nil else { return }
        if reset { clearResults() }
        error = nil
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                let page = try await UniFiClients.fetch(console: console, site: site, key: key, offset: offset)
                guard !Task.isCancelled else { return }
                var seen = Set(clients.map(\.id))
                clients += page.data.filter { seen.insert($0.id).inserted }
                offset = page.offset + page.count
                total = page.totalCount
            } catch {
                guard !Task.isCancelled else { return }
                self.error = (error as? UniFiClients.Failure)?.errorDescription ?? "Couldn’t reach UniFi Connector. Check your connection and try again."
            }
        }
    }
}
