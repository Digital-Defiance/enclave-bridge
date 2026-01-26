// AppState.swift
// Enclave Bridge
//
// Observable state for the app - tracks connections and keys

import Foundation
import Combine
import CryptoKit

/// Represents an active client connection
struct ClientConnection: Identifiable, Equatable {
    let id: UUID
    let connectedAt: Date
    let fileDescriptor: Int32
    var lastActivity: Date
    var requestCount: Int
    
    static func == (lhs: ClientConnection, rhs: ClientConnection) -> Bool {
        lhs.id == rhs.id
    }
}

/// Represents a cryptographic key (metadata only, not the actual key)
struct KeyInfo: Identifiable {
    let id: String  // Fingerprint or identifier
    let type: KeyType
    let createdAt: Date
    let publicKeyFingerprint: String
    let isSecureEnclave: Bool
    
    enum KeyType: String {
        case secp256k1 = "secp256k1"
        case secureEnclave = "Secure Enclave (P-256)"
    }
}

/// Central app state - published to SwiftUI views
@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var connections: [ClientConnection] = []
    @Published var keys: [KeyInfo] = []
    @Published var isServerRunning: Bool = false
    @Published var socketPath: String = ""
    @Published var totalRequestsHandled: Int = 0
    
    private init() {
        loadKeys()
    }
    
    // MARK: - Connection Management
    
    func addConnection(id: UUID, fileDescriptor: Int32) {
        let connection = ClientConnection(
            id: id,
            connectedAt: Date(),
            fileDescriptor: fileDescriptor,
            lastActivity: Date(),
            requestCount: 0
        )
        connections.append(connection)
        objectWillChange.send()
    }
    
    func removeConnection(id: UUID) {
        connections.removeAll { $0.id == id }
        objectWillChange.send()
    }
    
    func removeConnection(fileDescriptor: Int32) {
        connections.removeAll { $0.fileDescriptor == fileDescriptor }
        objectWillChange.send()
    }
    
    func updateConnectionActivity(id: UUID) {
        if let index = connections.firstIndex(where: { $0.id == id }) {
            connections[index].lastActivity = Date()
            connections[index].requestCount += 1
            totalRequestsHandled += 1
            objectWillChange.send()
        }
    }
    
    // MARK: - Key Management
    
    func loadKeys() {
        var loadedKeys: [KeyInfo] = []
        
        // Load secp256k1 ECIES key info
        if let pubKeyData = try? ECIESKeyManager.getOrCreateSecp256k1PublicKey() {
            let fingerprint = computeFingerprint(pubKeyData)
            let keyInfo = KeyInfo(
                id: "ecies-secp256k1",
                type: .secp256k1,
                createdAt: getKeyCreationDate(for: "ecies") ?? Date(),
                publicKeyFingerprint: fingerprint,
                isSecureEnclave: false
            )
            loadedKeys.append(keyInfo)
        }
        
        // Load Secure Enclave key info
        if let pubKeyData = try? SecureEnclaveKeyManager.getPublicKeyData() {
            let fingerprint = computeFingerprint(pubKeyData)
            let keyInfo = KeyInfo(
                id: "secure-enclave-p256",
                type: .secureEnclave,
                createdAt: getKeyCreationDate(for: "enclave") ?? Date(),
                publicKeyFingerprint: fingerprint,
                isSecureEnclave: true
            )
            loadedKeys.append(keyInfo)
        }
        
        keys = loadedKeys
    }
    
    func refreshKeys() {
        loadKeys()
    }
    
    // MARK: - Helpers
    
    private func computeFingerprint(_ data: Data) -> String {
        // SHA-256 fingerprint, show first 8 bytes as hex
        let hash = SHA256.hash(data: data)
        let fingerprint = hash.prefix(8).map { String(format: "%02x", $0) }.joined(separator: ":")
        return fingerprint.uppercased()
    }
    
    private func getKeyCreationDate(for keyType: String) -> Date? {
        // Try to get file modification date for the key file
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let keyPath: String
        switch keyType {
        case "ecies":
            keyPath = home + "/.enclave/ecies-privkey.bin"
        default:
            return nil
        }
        
        if let attrs = try? FileManager.default.attributesOfItem(atPath: keyPath),
           let creationDate = attrs[.creationDate] as? Date {
            return creationDate
        }
        return nil
    }
}
