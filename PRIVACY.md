# Privacy Policy

**Last Updated:** January 25, 2026

## Overview

Enclave Bridge is designed with privacy as a core principle. This application does not collect, store, or retain any user data.

## What We Do Not Do

- **No Data Collection** - We do not collect any personal information, usage data, or analytics
- **No Data Storage** - We do not store any data on your device or servers
- **No Data Retention** - We do not retain any information about your usage or operations
- **No Network Communication** - The application does not transmit data to any external servers or services
- **No Third-Party Integration** - We do not integrate with third-party analytics, advertising, or tracking services

## How the Application Works

Enclave Bridge operates entirely on your local machine:

1. **Local Socket Communication** - All communication between Node.js applications and the macOS app occurs through an encrypted Unix socket file on your device
2. **End-to-End Encryption** - All messages are encrypted using ECIES (secp256k1) encryption at the application level
3. **Secure Enclave Integration** - Cryptographic operations are performed using Apple's Secure Enclave, where private keys never leave the hardware
4. **No Persistence** - All operations occur in memory during the session; no data is written to disk except for the application's code and configuration files

## What Data Stays Private

All of the following remain on your device and are never transmitted:

- Cryptographic keys (stored in Secure Enclave)
- Public keys used for encryption
- Data being signed or decrypted
- Application state and connection information
- All encrypted and decrypted messages

## Security Model

- **Hardware-Backed Security** - Private keys are generated and stored exclusively in Apple's Secure Enclave
- **Ephemeral Keys** - Each ECIES message uses a fresh ephemeral keypair
- **Local Processing** - All cryptographic operations occur locally on your device
- **Zero Trust Architecture** - All communication is encrypted, even over the local socket

## System Permissions

The application may request the following system permissions:

- **Microphone/Camera** - Not used by this application
- **File Access** - Limited to application-specific directories
- **Network** - The application does not establish network connections

## User Responsibilities

While Enclave Bridge does not collect or transmit data, users should:

- Keep the application and macOS updated
- Protect access to your device and the Unix socket
- Use strong authentication mechanisms in applications that use this bridge
- Review your Node.js application's privacy practices

## Changes to This Policy

We may update this privacy policy from time to time. Any changes will be posted on this page with an updated "Last Updated" date.

## Questions or Concerns

If you have any questions about this privacy policy or the privacy practices of Enclave Bridge, please open an issue on our [GitHub repository](https://github.com/Digital-Defiance/enclave-bridge).

---

**For technical details about the ECIES protocol and data handling**, see [ENCLAVE_BRIDGE_SPEC.md](ENCLAVE_BRIDGE_SPEC.md).
