//
//  EnclaveApp.swift
//  Enclave Bridge
//
//  Created by Jessica Mulein on 1/24/26.
//

import SwiftUI
import CoreData

// Notification for showing main window
extension Notification.Name {
    static let showMainWindow = Notification.Name("showMainWindow")
}

@main
struct EnclaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let persistenceController = PersistenceController.shared
    
    // Start the socket server at $HOME/.enclave/enclave-bridge.sock
    static func socketPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = home + "/.enclave"
        let path = dir + "/enclave-bridge.sock"
        // Ensure directory exists
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
        return path
    }
    
    let socketServer = SocketServer(socketPath: EnclaveApp.socketPath())

    init() {
        socketServer.start()
        // Update app state
        Task { @MainActor in
            AppState.shared.isServerRunning = true
            AppState.shared.socketPath = EnclaveApp.socketPath()
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
        .handlesExternalEvents(matching: Set(["main", ""]))
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Enclave Bridge") {
                    socketServer.stop()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        
        // Settings window (optional)
        Settings {
            SettingsView()
        }
    }
}

// MARK: - App Delegate for Status Bar

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var mainWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        
        // Don't terminate when last window closes
        NSApp.setActivationPolicy(.regular)
        
        // Observe window creation to capture main window reference
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.captureMainWindow()
        }
    }
    
    func captureMainWindow() {
        // Find the main content window (not status bar, not settings)
        for window in NSApp.windows {
            if window.canBecomeMain && window.contentView != nil {
                self.mainWindow = window
                
                // Set up delegate to intercept close
                window.delegate = self
                print("Captured main window: \(window)")
                break
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in status bar when window is closed
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Reopen main window when clicking dock icon
        if !flag {
            showMainWindow()
        }
        return true
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: "Enclave Bridge")
            button.action = #selector(statusBarButtonClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Build menu
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Show Enclave Bridge", action: #selector(showMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        let statusItem = NSMenuItem(title: "Server: Running", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        
        let connectionsItem = NSMenuItem(title: "Connections: 0", action: nil, keyEquivalent: "")
        connectionsItem.isEnabled = false
        menu.addItem(connectionsItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        
        self.statusItem?.menu = menu
    }
    
    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        // Show menu on right click, show window on left click
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp {
            statusItem?.menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
        } else {
            showMainWindow()
        }
    }
    
    @objc func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        
        // If we have a captured main window, show it
        if let window = mainWindow {
            window.setIsVisible(true)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            return
        }
        
        // Try to find any suitable window
        for window in NSApp.windows {
            guard window.canBecomeMain || window.canBecomeKey else { continue }
            guard window.contentView != nil else { continue }
            
            window.setIsVisible(true)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            mainWindow = window
            window.delegate = self
            return
        }
        
        // No window found - this shouldn't happen with our hide-on-close approach
        print("No window available to show")
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Window Delegate to intercept close

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide the window instead of closing it
        sender.orderOut(nil)
        return false  // Prevent actual close
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @StateObject private var appState = AppState.shared
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 250)
    }
}

struct GeneralSettingsView: View {
    @StateObject private var appState = AppState.shared
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
            }
            
            Section("Socket Path") {
                Text(appState.socketPath)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding()
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            
            Text("Enclave Bridge")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 1.0.0")
                .foregroundColor(.secondary)
            
            Text("Secure bridge between Node.js and Apple Silicon Secure Enclave")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Link("GitHub Repository", destination: URL(string: "https://github.com/Digital-Defiance/enclave")!)
        }
        .padding()
    }
}
