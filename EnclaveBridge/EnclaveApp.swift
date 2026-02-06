//
//  EnclaveApp.swift
//  Enclave Bridge
//
//  Created by Jessica Mulein on 1/24/26.
//

import SwiftUI
import CoreData
import ServiceManagement

// Notifications for showing windows
extension Notification.Name {
    static let showMainWindow = Notification.Name("showMainWindow")
    static let showSettings = Notification.Name("showSettings")
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
    
    // Shared socket server instance for cleanup on termination
    static let socketServer = SocketServer(socketPath: EnclaveApp.socketPath())

    init() {
        EnclaveApp.socketServer.start()
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
                    EnclaveApp.socketServer.stop()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        
        // Settings window
        Settings {
            SettingsView()
        }
    }
}

// MARK: - Settings Window Controller
// This helps manage the settings window from AppDelegate
class SettingsWindowController {
    private static var settingsWindow: NSWindow?
    private static var windowController: NSWindowController?
    
    static func showSettings() {
        // Ensure app is in regular mode first
        NSApp.setActivationPolicy(.regular)
        
        // If we already have a settings window, show it
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create the settings window directly
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Enclave Bridge Settings"
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        
        // Keep strong references
        settingsWindow = window
        windowController = NSWindowController(window: window)
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - App Delegate for Status Bar

import Combine

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    // Strong reference to status item - MUST be retained
    private var statusItem: NSStatusItem!
    private var statusBarMenu: NSMenu!
    private weak var mainWindow: NSWindow?
    
    // Menu items that need dynamic updates
    private var serverStatusMenuItem: NSMenuItem?
    private var connectionsMenuItem: NSMenuItem?
    private var requestsMenuItem: NSMenuItem?
    private var keysMenuItem: NSMenuItem?
    
    // Combine subscriptions for AppState updates
    private var cancellables = Set<AnyCancellable>()
    
    // Window observation timer
    private var windowObservationTimer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up status bar FIRST - this must happen early
        setupStatusBar()
        
        // Subscribe to app state changes for menu updates
        subscribeToAppStateChanges()
        
        // Start with regular activation (show dock icon and window)
        NSApp.setActivationPolicy(.regular)
        
        // Start observing for main window
        startWindowObservation()
        
        print("AppDelegate: applicationDidFinishLaunching completed")
    }
    
    private func startWindowObservation() {
        // Poll for the main window since SwiftUI creates it async
        windowObservationTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            // Ensure we're on the main thread for window operations
            DispatchQueue.main.async {
                self.captureMainWindowIfNeeded()
            }
        }
    }
    
    private func captureMainWindowIfNeeded() {
        // Try to find and capture the main window
        for window in NSApp.windows {
            guard isMainContentWindow(window) else { continue }
            
            // Found it - capture and set delegate if not already set
            if self.mainWindow !== window || window.delegate !== self {
                self.mainWindow = window
                window.delegate = self
                print("AppDelegate: Captured main window: \(window)")
            }
        }
    }
    
    private func isMainContentWindow(_ window: NSWindow) -> Bool {
        // Skip windows that can't be the main content window
        guard window.canBecomeMain else { return false }
        guard window.contentView != nil else { return false }
        guard window.styleMask.contains(.titled) else { return false }
        
        // Skip minimized windows - don't re-capture them
        guard !window.isMiniaturized else { return false }
        
        // Skip settings/preferences windows
        let title = window.title.lowercased()
        return !title.contains("settings") && !title.contains("preferences")
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // CRITICAL: Never terminate - we run in status bar
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        windowObservationTimer?.invalidate()
        EnclaveApp.socketServer.stop()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When dock icon clicked, show window - but only if not minimized
        // hasVisibleWindows is false for both hidden AND minimized windows
        // Check if main window is just minimized
        if let window = mainWindow, window.isMiniaturized {
            // Window is minimized to dock - don't auto-restore, let user click it
            return true
        }
        
        if !flag {
            showMainWindow()
        }
        return true
    }
    
    // MARK: - Status Bar Setup
    
    private func setupStatusBar() {
        // Create status bar item with fixed length to ensure visibility
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        guard let button = statusItem.button else {
            print("ERROR: Failed to get status bar button")
            return
        }
        
        // Set up the button
        button.image = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: "Enclave Bridge")
        button.image?.isTemplate = true  // Adapts to menu bar appearance
        
        // Build the menu
        statusBarMenu = NSMenu()
        
        // Header
        let headerItem = NSMenuItem(title: "Enclave Bridge", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        headerItem.attributedTitle = NSAttributedString(
            string: "Enclave Bridge",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        statusBarMenu.addItem(headerItem)
        statusBarMenu.addItem(NSMenuItem.separator())
        
        // Show Window
        let showItem = NSMenuItem(title: "Show Window", action: #selector(showMainWindow), keyEquivalent: "")
        showItem.target = self
        statusBarMenu.addItem(showItem)
        statusBarMenu.addItem(NSMenuItem.separator())
        
        // Status items
        serverStatusMenuItem = NSMenuItem(title: "● Server: Starting...", action: nil, keyEquivalent: "")
        serverStatusMenuItem?.isEnabled = false
        statusBarMenu.addItem(serverStatusMenuItem!)
        
        connectionsMenuItem = NSMenuItem(title: "   Connections: 0", action: nil, keyEquivalent: "")
        connectionsMenuItem?.isEnabled = false
        statusBarMenu.addItem(connectionsMenuItem!)
        
        requestsMenuItem = NSMenuItem(title: "   Requests: 0", action: nil, keyEquivalent: "")
        requestsMenuItem?.isEnabled = false
        statusBarMenu.addItem(requestsMenuItem!)
        
        keysMenuItem = NSMenuItem(title: "   Keys: 0", action: nil, keyEquivalent: "")
        keysMenuItem?.isEnabled = false
        statusBarMenu.addItem(keysMenuItem!)
        
        statusBarMenu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        statusBarMenu.addItem(settingsItem)
        
        statusBarMenu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit Enclave Bridge", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        statusBarMenu.addItem(quitItem)
        
        // Assign menu directly - simpler and more reliable
        statusItem.menu = statusBarMenu
        
        print("AppDelegate: Status bar setup complete")
    }
    
    // MARK: - Window Delegate Methods
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        print("AppDelegate: windowShouldClose called")
        hideToStatusBar()
        return false  // Prevent close, just hide
    }
    
    // Allow normal minimize to dock - don't intercept it
    // If you want minimize to also hide to status bar, the user can just close the window instead
    
    // MARK: - Window Actions
    
    private func hideToStatusBar() {
        print("AppDelegate: Hiding to status bar")
        
        // Hide the main window
        mainWindow?.orderOut(nil)
        
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
    }
    
    @objc func showMainWindow() {
        print("AppDelegate: Showing main window")
        
        // Show dock icon
        NSApp.setActivationPolicy(.regular)
        
        // Activate app
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            
            // Show the main window
            if let window = self.mainWindow {
                if window.isMiniaturized {
                    window.deminiaturize(nil)  // Restore from dock
                } else {
                    window.makeKeyAndOrderFront(nil)
                }
            } else {
                // Try to find a window
                for window in NSApp.windows {
                    guard window.canBecomeMain else { continue }
                    guard window.styleMask.contains(.titled) else { continue }
                    
                    let title = window.title.lowercased()
                    if !title.contains("settings") && !title.contains("preferences") {
                        if window.isMiniaturized {
                            window.deminiaturize(nil)
                        } else {
                            window.makeKeyAndOrderFront(nil)
                        }
                        self.mainWindow = window
                        window.delegate = self
                        break
                    }
                }
            }
        }
    }
    
    @objc func openSettings() {
        print("AppDelegate: Opening settings")
        SettingsWindowController.showSettings()
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - App State Subscription
    
    private func subscribeToAppStateChanges() {
        Task { @MainActor in
            let appState = AppState.shared
            
            appState.$isServerRunning
                .receive(on: DispatchQueue.main)
                .sink { [weak self] isRunning in
                    self?.updateServerStatus(isRunning: isRunning)
                }
                .store(in: &cancellables)
            
            appState.$connections
                .receive(on: DispatchQueue.main)
                .sink { [weak self] connections in
                    self?.connectionsMenuItem?.title = "   Connections: \(connections.count)"
                    self?.updateStatusBarIcon()
                }
                .store(in: &cancellables)
            
            appState.$totalRequestsHandled
                .receive(on: DispatchQueue.main)
                .sink { [weak self] count in
                    self?.requestsMenuItem?.title = "   Requests: \(count)"
                }
                .store(in: &cancellables)
            
            appState.$keys
                .receive(on: DispatchQueue.main)
                .sink { [weak self] keys in
                    self?.keysMenuItem?.title = "   Keys: \(keys.count)"
                }
                .store(in: &cancellables)
        }
    }
    
    private func updateServerStatus(isRunning: Bool) {
        if isRunning {
            serverStatusMenuItem?.title = "● Server: Running"
            serverStatusMenuItem?.attributedTitle = createColoredStatusTitle(
                "● Server: Running",
                statusColor: .systemGreen
            )
        } else {
            serverStatusMenuItem?.title = "● Server: Stopped"
            serverStatusMenuItem?.attributedTitle = createColoredStatusTitle(
                "● Server: Stopped",
                statusColor: .systemRed
            )
        }
        updateStatusBarIcon()
    }
    
    private func createColoredStatusTitle(_ text: String, statusColor: NSColor) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text)
        attributedString.addAttribute(.foregroundColor, value: statusColor, range: NSRange(location: 0, length: 1))
        return attributedString
    }
    
    private func updateStatusBarIcon() {
        guard let button = statusItem.button else { return }
        
        Task { @MainActor in
            let appState = AppState.shared
            let isRunning = appState.isServerRunning
            
            let iconName: String
            if !isRunning {
                iconName = "lock.shield"
            } else {
                iconName = "lock.shield.fill"
            }
            
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Enclave Bridge")
            button.image?.isTemplate = true
        }
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
    @State private var launchAtLogin: Bool = false
    @State private var loginItemStatus: String = "Unknown"
    @State private var loginItemError: String? = nil
    
    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLoginItem(enabled: newValue)
                    }
                
                Text("Status: \(loginItemStatus)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let error = loginItemError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            Section("Socket Path") {
                Text(appState.socketPath)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .onAppear {
            updateLoginItemState()
        }
    }
    
    private func updateLoginItemState() {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            switch status {
            case .enabled:
                loginItemStatus = "Enabled"
                launchAtLogin = true
            case .notRegistered:
                loginItemStatus = "Not Registered"
                launchAtLogin = false
            case .requiresApproval:
                loginItemStatus = "Requires Approval (check System Settings > Login Items)"
                launchAtLogin = false
            case .notFound:
                loginItemStatus = "Not Found"
                launchAtLogin = false
            @unknown default:
                loginItemStatus = "Unknown (\(status.rawValue))"
                launchAtLogin = false
            }
            print("Login item status: \(loginItemStatus)")
        } else {
            loginItemStatus = "Requires macOS 13+"
        }
    }
    
    private func setLoginItem(enabled: Bool) {
        loginItemError = nil
        
        if #available(macOS 13.0, *) {
            do {
                print("Setting login item enabled: \(enabled)")
                if enabled {
                    try SMAppService.mainApp.register()
                    print("Successfully registered login item")
                } else {
                    try SMAppService.mainApp.unregister()
                    print("Successfully unregistered login item")
                }
                // Update status after change
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    updateLoginItemState()
                }
            } catch {
                print("Login item error: \(error)")
                loginItemError = "Failed: \(error.localizedDescription)"
                // Revert toggle state
                DispatchQueue.main.async {
                    updateLoginItemState()
                }
            }
        } else {
            loginItemError = "Requires macOS 13 or later"
        }
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
            
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
            Text("Version \(version) (\(build))")
                .foregroundColor(.secondary)
            
            Text("Secure bridge between Node.js and Apple Silicon Secure Enclave")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Link("GitHub Repository", destination: URL(string: "https://github.com/Digital-Defiance/enclave-bridge")!)
        }
        .padding()
    }
}
