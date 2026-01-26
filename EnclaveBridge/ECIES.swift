// ECIES.swift
// Enclave Bridge
//
// Implements ECIES (secp256k1 + AES-256-GCM) compatible with node-ecies-lib

import Foundation
import CryptoKit
import P256K


// Real secp256k1 keypair using secp256k1.swift (KeyAgreement API for ECDH)
struct Secp256k1KeyPair {
    let privateKey: P256K.KeyAgreement.PrivateKey
    let publicKey: Data  // uncompressed, 0x04 prefix, 65 bytes
}


class ECIES {
    // Generate ephemeral secp256k1 keypair using secp256k1.swift (KeyAgreement API)
    static func generateEphemeralKeyPair() -> Secp256k1KeyPair {
        let priv = try! P256K.KeyAgreement.PrivateKey()
        let pub = priv.publicKey.dataRepresentation // 65 bytes, 0x04 prefix
        return Secp256k1KeyPair(privateKey: priv, publicKey: pub)
    }

    // Compute ECDH shared secret using secp256k1.swift
    // Accepts: privateKey as P256K.KeyAgreement.PrivateKey, peerPublicKey as Data (compressed or uncompressed)
    // Returns: 32-byte x-coordinate of the shared point (matching node-ecies-lib behavior)
    static func computeSharedSecret(privateKey: P256K.KeyAgreement.PrivateKey, peerPublicKey: Data) -> Data {
        // Accepts: privateKey (P256K.KeyAgreement.PrivateKey), peerPublicKey (33 or 65 bytes)
        let pubKey: P256K.KeyAgreement.PublicKey?
        if peerPublicKey.count == 33 && (peerPublicKey[0] == 0x02 || peerPublicKey[0] == 0x03) {
            pubKey = try? P256K.KeyAgreement.PublicKey(dataRepresentation: peerPublicKey, format: .compressed)
        } else if peerPublicKey.count == 65 && peerPublicKey[0] == 0x04 {
            pubKey = try? P256K.KeyAgreement.PublicKey(dataRepresentation: peerPublicKey, format: .uncompressed)
        } else {
            return Data() // Invalid format
        }
        guard let peerPub = pubKey else { return Data() }
        guard let sharedSecret = try? privateKey.sharedSecretFromKeyAgreement(with: peerPub) else { return Data() }
        // The library returns 33 bytes (compressed point with 02/03 prefix)
        // node-ecies-lib uses only the x-coordinate (32 bytes, strips the prefix)
        let secretBytes = Data(sharedSecret.bytes)
        if secretBytes.count == 33 && (secretBytes[0] == 0x02 || secretBytes[0] == 0x03) {
            return secretBytes.dropFirst() // Return just the 32-byte x-coordinate
        }
        return secretBytes
    }

    // Derive symmetric key using HKDF-SHA256
    static func deriveSymmetricKey(sharedSecret: Data) -> CryptoKit.SymmetricKey {
        let info = "ecies-v2-key-derivation".data(using: .utf8)!
        return CryptoKit.HKDF<CryptoKit.SHA256>.deriveKey(inputKeyMaterial: CryptoKit.SymmetricKey(data: sharedSecret), salt: Data(), info: info, outputByteCount: 32)
    }

    // Encrypt data using AES-256-GCM
    static func encrypt(plaintext: Data, symmetricKey: SymmetricKey, iv: Data, aad: Data) -> (ciphertext: Data, tag: Data)? {
        guard let sealedBox = try? AES.GCM.seal(plaintext, using: symmetricKey, nonce: AES.GCM.Nonce(data: iv), authenticating: aad) else {
            return nil
        }
        return (sealedBox.ciphertext, sealedBox.tag)
    }

    // Decrypt data using AES-256-GCM
    static func decrypt(ciphertext: Data, tag: Data, symmetricKey: SymmetricKey, iv: Data, aad: Data) -> Data? {
        let sealedBox = try? AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: ciphertext, tag: tag)
        return sealedBox.flatMap { try? AES.GCM.open($0, using: symmetricKey, authenticating: aad) }
    }
}
