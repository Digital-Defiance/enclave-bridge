// SocketServer.swift
// Enclave Bridge
//
// Handles Unix domain socket server for Secure Enclave bridge protocol

import Foundation

class SocketServer {
    private let socketPath: String
    private var socketFileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "SocketServerQueue")
    private var isRunning = false
    private let protocolHandler = BridgeProtocolHandler()
    
    // Track connection IDs for each file descriptor
    private var connectionIds: [Int32: UUID] = [:]
    private let connectionLock = NSLock()

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func start() {
        queue.async { [weak self] in
            self?.runServer()
        }
    }

    func stop() {
        isRunning = false
        Task { @MainActor in
            AppState.shared.isServerRunning = false
        }
        if socketFileDescriptor != -1 {
            close(socketFileDescriptor)
            unlink(socketPath)
        }
    }

    private func runServer() {
        isRunning = true
        // Remove any existing socket file
        unlink(socketPath)
        // Create socket
        socketFileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFileDescriptor != -1 else {
            print("Failed to create socket")
            return
        }
        // Bind socket
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        strncpy(&addr.sun_path.0, socketPath, socketPath.utf8.count)
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult != -1 else {
            print("Failed to bind socket")
            close(socketFileDescriptor)
            return
        }
        // Listen
        guard listen(socketFileDescriptor, 5) != -1 else {
            print("Failed to listen on socket")
            close(socketFileDescriptor)
            return
        }
        print("Socket server started at \(socketPath)")
        
        // Update app state
        Task { @MainActor in
            AppState.shared.isServerRunning = true
            AppState.shared.socketPath = socketPath
        }
        
        // Accept loop
        while isRunning {
            var clientAddr = sockaddr_un()
            var clientLen: socklen_t = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(socketFileDescriptor, $0, &clientLen)
                }
            }
            if clientFd == -1 {
                continue
            }
            
            // Handle client in a separate queue to allow concurrent connections
            let clientQueue = DispatchQueue(label: "ClientHandler-\(clientFd)")
            clientQueue.async { [weak self] in
                self?.handleClient(clientFd)
            }
        }
        close(socketFileDescriptor)
        unlink(socketPath)
    }

    private func handleClient(_ clientFd: Int32) {
        // Register connection
        let connectionId = registerConnection(clientFd: clientFd)
        
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var dataBuffer = Data()
        
        defer {
            close(clientFd)
            unregisterConnection(clientFd: clientFd, connectionId: connectionId)
        }
        
        while true {
            let bytesRead = read(clientFd, &buffer, bufferSize)
            if bytesRead < 0 {
                perror("Read error")
                break
            } else if bytesRead == 0 {
                // Client closed connection
                break
            }
            dataBuffer.append(Data(buffer[0..<bytesRead]))
            // Try to parse complete JSON objects (framing: one JSON per message)
            while let range = dataBuffer.range(of: Data([0x7d])) { // 0x7d = '}'
                let end = range.upperBound
                let messageData = dataBuffer.subdata(in: 0..<end)
                dataBuffer.removeSubrange(0..<end)
                print("Received: \(messageData as NSData)")
                
                // Update activity
                updateConnectionActivity(connectionId: connectionId)
                
                let response = protocolHandler.handleMessage(messageData)
                let written = response.withUnsafeBytes { write(clientFd, $0.baseAddress, response.count) }
                if written < 0 {
                    perror("Write error")
                    break
                }
            }
        }
    }
    
    // MARK: - Connection Tracking
    
    private func registerConnection(clientFd: Int32) -> UUID {
        let connectionId = UUID()
        connectionLock.lock()
        connectionIds[clientFd] = connectionId
        connectionLock.unlock()
        
        Task { @MainActor in
            AppState.shared.addConnection(id: connectionId, fileDescriptor: clientFd)
        }
        
        return connectionId
    }
    
    private func unregisterConnection(clientFd: Int32, connectionId: UUID) {
        connectionLock.lock()
        connectionIds.removeValue(forKey: clientFd)
        connectionLock.unlock()
        
        Task { @MainActor in
            AppState.shared.removeConnection(fileDescriptor: clientFd)
        }
    }
    
    private func updateConnectionActivity(connectionId: UUID) {
        Task { @MainActor in
            AppState.shared.updateConnectionActivity(id: connectionId)
        }
    }
}
