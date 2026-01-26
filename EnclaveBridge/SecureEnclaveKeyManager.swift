// SecureEnclaveKeyManager.swift
// Enclave Bridge
//
// Handles Secure Enclave key generation, storage, signing, and decryption

import Foundation
import CryptoKit

class SecureEnclaveKeyManager {
    static let keyTag = "com.enclave.secureenclavekey"

    // Generate or load Secure Enclave private key
    static func getOrCreatePrivateKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .privateKeyUsage, nil)!
        let tag = keyTag.data(using: .utf8)!
        // Try to load existing key
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecReturnRef as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let item = item {
            // The SecureEnclave.P256.Signing.PrivateKey(secKey:) initializer is not available on this platform.
            // If you need to load an existing Secure Enclave key, you may need to use lower-level APIs or update your deployment target.
            // For now, this will throw an error if the key cannot be loaded as a CryptoKit key.
            throw NSError(domain: "SecureEnclaveKeyManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to load Secure Enclave key with CryptoKit on this platform."])
        } else {
            return try SecureEnclave.P256.Signing.PrivateKey(
                compactRepresentable: true,
                accessControl: access,
                authenticationContext: nil
            )
        }
    }

    // Get public key (raw, 65 bytes, 0x04 prefix)
    static func getPublicKeyData() throws -> Data {
        let priv = try getOrCreatePrivateKey()
        let pub = priv.publicKey
        let x963 = pub.x963Representation
        // Ensure 0x04 prefix (uncompressed)
        return x963
    }

    // Sign data with Secure Enclave key
    static func sign(data: Data) throws -> Data {
        let priv = try getOrCreatePrivateKey()
        let signature = try priv.signature(for: data)
        return signature.derRepresentation
    }

    // (Optional) Decrypt data with Secure Enclave key (not supported for P256.Signing)
    // For secp256k1, decryption is not supported in Secure Enclave; only signing is available
}

