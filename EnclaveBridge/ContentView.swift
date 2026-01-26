//
//  ContentView.swift
//  Enclave Bridge
//
//  Created by Jessica Mulein on 1/24/26.
//

import SwiftUI

enum NavigationItem: Hashable {
    case dashboard
    case connections
    case keys
}

struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @State private var selectedItem: NavigationItem? = .dashboard
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(selection: $selectedItem) {
                Section("Status") {
                    HStack {
                        Circle()
                            .fill(appState.isServerRunning ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(appState.isServerRunning ? "Server Running" : "Server Stopped")
                    }
                    if !appState.socketPath.isEmpty {
                        Text(appState.socketPath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .contextMenu {
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(appState.socketPath, forType: .string)
                                }) {
                                    Label("Copy Socket Path", systemImage: "doc.on.doc")
                                }
                            }
                            .help("Right-click to copy")
                    }
                }
                
                Section("Navigation") {
                    NavigationLink(value: NavigationItem.dashboard) {
                        Label("Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent")
                    }
                    
                    NavigationLink(value: NavigationItem.connections) {
                        Label("Connections", systemImage: "network")
                            .badge(appState.connections.count)
                    }
                    
                    NavigationLink(value: NavigationItem.keys) {
                        Label("Keys", systemImage: "key.fill")
                            .badge(appState.keys.count)
                    }
                }
                
                Section("Statistics") {
                    LabeledContent("Total Requests", value: "\(appState.totalRequestsHandled)")
                }
            }
            .listStyle(SidebarListStyle())
            .navigationTitle("Enclave Bridge")
        } detail: {
            switch selectedItem {
            case .dashboard, .none:
                DashboardView()
            case .connections:
                ConnectionsView()
            case .keys:
                KeysView()
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

struct DashboardView: View {
    @StateObject private var appState = AppState.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
            
            Text("Enclave Bridge")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Secure Enclave ↔ Node.js Bridge")
                .font(.title3)
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.horizontal, 40)
            
            VStack(alignment: .leading, spacing: 12) {
                StatusRow(
                    icon: "server.rack",
                    label: "Server",
                    value: appState.isServerRunning ? "Running" : "Stopped",
                    color: appState.isServerRunning ? .green : .red
                )
                StatusRow(
                    icon: "network",
                    label: "Active Connections",
                    value: "\(appState.connections.count)",
                    color: appState.connections.isEmpty ? .secondary : .blue
                )
                StatusRow(
                    icon: "key.fill",
                    label: "Keys Loaded",
                    value: "\(appState.keys.count)",
                    color: .orange
                )
                StatusRow(
                    icon: "arrow.left.arrow.right",
                    label: "Total Requests",
                    value: "\(appState.totalRequestsHandled)",
                    color: .purple
                )
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 400)
        .navigationTitle("Dashboard")
    }
}

struct StatusRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

struct ConnectionsView: View {
    @StateObject private var appState = AppState.shared
    
    var body: some View {
        Group {
            if appState.connections.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Active Connections")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Clients will appear here when connected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(appState.connections) { connection in
                    ConnectionRow(connection: connection)
                }
            }
        }
        .navigationTitle("Active Connections")
    }
}

struct ConnectionRow: View {
    let connection: ClientConnection
    
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Client \(connection.id.uuidString.prefix(8))...")
                    .fontWeight(.medium)
                Spacer()
                Text("\(connection.requestCount) requests")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Connected: \(dateFormatter.string(from: connection.connectedAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Last activity: \(dateFormatter.string(from: connection.lastActivity))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct KeysView: View {
    @StateObject private var appState = AppState.shared
    
    var body: some View {
        Group {
            if appState.keys.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "key.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Keys Available")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Keys will be generated on first use")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(appState.keys) { key in
                    KeyRow(keyInfo: key)
                }
            }
        }
        .navigationTitle("Cryptographic Keys")
        .toolbar {
            ToolbarItem {
                Button(action: { appState.refreshKeys() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

struct KeyRow: View {
    let keyInfo: KeyInfo
    
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: keyInfo.isSecureEnclave ? "cpu" : "key.fill")
                    .foregroundColor(keyInfo.isSecureEnclave ? .blue : .orange)
                Text(keyInfo.type.rawValue)
                    .fontWeight(.semibold)
                Spacer()
                if keyInfo.isSecureEnclave {
                    Label("Hardware", systemImage: "checkmark.shield.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            HStack {
                Text("Fingerprint:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(keyInfo.publicKeyFingerprint)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)
            }
            
            Text("Created: \(dateFormatter.string(from: keyInfo.createdAt))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
}
