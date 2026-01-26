// ECIESKeyManager.swift
// Handles secp256k1 key generation, storage, and public key export for ECIES protocol
// Uses CryptoSwift for secp256k1 (or replace with your preferred library)

import Foundation // Data, FileManager, NSError, URL
import Security   // SecRandomCopyBytes, kSecRandomDefault, errSecSuccess
import P256K      // P256K1 types
import Darwin     // chmod

// NOTE: You must add https://github.com/GigaBitcoin/secp256k1.swift as a SwiftPM dependency to your project.

class ECIESKeyManager {
    static let keyTag = "com.enclave.ecieskey"
    static let privKeyFile = (FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".enclave/ecies-privkey.bin")).path

    // Returns the secp256k1 public key (uncompressed, 65 bytes, 0x04 prefix)
    static func getOrCreateSecp256k1PublicKey() throws -> Data {
        let privKey = try getOrCreateSecp256k1PrivateKeyObject()
        let pubKey = privKey.publicKey
        return pubKey.dataRepresentation // 65 bytes, 0x04 prefix
    }

    // Returns the secp256k1 private key (32 bytes)
    static func getOrCreateSecp256k1PrivateKey() throws -> Data {
        let fm = FileManager.default
        if fm.fileExists(atPath: privKeyFile) {
            return try Data(contentsOf: URL(fileURLWithPath: privKeyFile))
        }
        // Generate new 32-byte random private key
        var priv = Data(count: 32)
        let result = priv.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        if result != errSecSuccess {
            throw NSError(domain: "ECIESKeyManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to generate random secp256k1 private key"]) 
        }
        try priv.write(to: URL(fileURLWithPath: privKeyFile), options: .atomic)
        // (Optional) Zero out file permissions for security
        chmod(privKeyFile, 0o600)
        return priv
    }

    // Returns the secp256k1 private key as a P256K.KeyAgreement.PrivateKey object
    static func getOrCreateSecp256k1PrivateKeyObject() throws -> P256K.KeyAgreement.PrivateKey {
        let privData = try getOrCreateSecp256k1PrivateKey()
        guard privData.count == 32 else {
            throw NSError(domain: "ECIESKeyManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "Private key data is not 32 bytes"])
        }
        return try P256K.KeyAgreement.PrivateKey(dataRepresentation: [UInt8](privData))
    }
}
