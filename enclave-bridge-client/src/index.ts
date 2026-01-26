/**
 * Enclave Bridge Client - TypeScript client for Apple Secure Enclave bridge
 *
 * This client communicates with the Enclave Bridge macOS app via Unix domain socket,
 * providing access to:
 * - Secure Enclave P-256 key operations (signing)
 * - secp256k1 key operations (ECIES decryption)
 * - Key management
 *
 * Protocol Format:
 * - Request: COMMAND:base64_payload (or just COMMAND for no payload)
 * - Response: OK:base64_result or ERROR:message
 */

import { Socket, createConnection } from 'node:net';
import { EventEmitter } from 'node:events';

// Re-export types and utilities
export * from './types.js';
export * from './ecies.js';

import type {
  EnclaveBridgeClientOptions,
  ConnectionState,
  PublicKeyInfo,
  SignatureResult,
  DecryptionResult,
  KeyGenerationResult,
  BridgeResponse,
} from './types.js';

/**
 * Default socket path for Enclave Bridges
 */
export const DEFAULT_SOCKET_PATH = '/tmp/enclave-bridge.sock';

/**
 * Default connection timeout in milliseconds
 */
export const DEFAULT_TIMEOUT = 30000;

/**
 * Enclave Bridge Client
 *
 * Provides a complete TypeScript API mirroring the Swift Enclave Bridge protocol.
 *
 * @example
 * ```typescript
 * import { EnclaveBridgeClient } from '@digitaldefiance/enclave-bridge-client';
 *
 * const client = new EnclaveBridgeClient();
 * await client.connect();
 *
 * // Get the secp256k1 public key for ECIES
 * const publicKey = await client.getPublicKey();
 * console.log('Public Key:', publicKey.base64);
 *
 * // Decrypt ECIES-encrypted data
 * const plaintext = await client.decrypt(encryptedBuffer);
 *
 * // Sign with Secure Enclave
 * const signature = await client.enclaveSign(dataBuffer);
 *
 * await client.disconnect();
 * ```
 */
export class EnclaveBridgeClient extends EventEmitter {
  private socket: Socket | null = null;
  private socketPath: string;
  private timeout: number;
  private responseBuffer = '';
  private pendingRequest: {
    resolve: (value: string) => void;
    reject: (error: Error) => void;
    timer: NodeJS.Timeout;
  } | null = null;

  private _connectionState: ConnectionState = 'disconnected';

  /**
   * Creates a new Enclave Bridge client
   *
   * @param options - Client configuration options
   */
  constructor(options: EnclaveBridgeClientOptions = {}) {
    super();
    this.socketPath = options.socketPath ?? DEFAULT_SOCKET_PATH;
    this.timeout = options.timeout ?? DEFAULT_TIMEOUT;
  }

  /**
   * Current connection state
   */
  get connectionState(): ConnectionState {
    return this._connectionState;
  }

  /**
   * Whether the client is currently connected
   */
  get isConnected(): boolean {
    return this._connectionState === 'connected';
  }

  /**
   * Connect to the Enclave socket server
   *
   * @returns Promise that resolves when connected
   * @throws Error if connection fails
   */
  async connect(): Promise<void> {
    if (this.socket) {
      throw new Error('Already connected');
    }

    this._connectionState = 'connecting';
    this.emit('stateChange', this._connectionState);

    return new Promise((resolve, reject) => {
      const connectionTimer = setTimeout(() => {
        this.socket?.destroy();
        this.socket = null;
        this._connectionState = 'disconnected';
        this.emit('stateChange', this._connectionState);
        reject(new Error(`Connection timeout after ${this.timeout}ms`));
      }, this.timeout);

      this.socket = createConnection(this.socketPath, () => {
        clearTimeout(connectionTimer);
        this._connectionState = 'connected';
        this.emit('stateChange', this._connectionState);
        this.emit('connect');
        resolve();
      });

      this.socket.setEncoding('utf8');

      this.socket.on('data', (data: string) => {
        this.handleData(data);
      });

      this.socket.on('error', (err) => {
        clearTimeout(connectionTimer);
        this._connectionState = 'error';
        this.emit('stateChange', this._connectionState);
        this.emit('error', err);

        if (this.pendingRequest) {
          this.pendingRequest.reject(err);
          clearTimeout(this.pendingRequest.timer);
          this.pendingRequest = null;
        }

        reject(err);
      });

      this.socket.on('close', () => {
        this.socket = null;
        this._connectionState = 'disconnected';
        this.emit('stateChange', this._connectionState);
        this.emit('disconnect');

        if (this.pendingRequest) {
          this.pendingRequest.reject(new Error('Connection closed'));
          clearTimeout(this.pendingRequest.timer);
          this.pendingRequest = null;
        }
      });
    });
  }

  /**
   * Disconnect from the EnclaveBridge socket server
   */
  async disconnect(): Promise<void> {
    if (!this.socket) {
      return;
    }

    return new Promise((resolve) => {
      this.socket!.once('close', () => {
        resolve();
      });
      this.socket!.end();
    });
  }

  /**
   * Handle incoming data from the socket
   */
  private handleData(data: string): void {
    this.responseBuffer += data;

    // Check if we have a complete response (newline terminated)
    const newlineIndex = this.responseBuffer.indexOf('\n');
    if (newlineIndex !== -1) {
      const response = this.responseBuffer.substring(0, newlineIndex);
      this.responseBuffer = this.responseBuffer.substring(newlineIndex + 1);

      if (this.pendingRequest) {
        clearTimeout(this.pendingRequest.timer);
        this.pendingRequest.resolve(response);
        this.pendingRequest = null;
      }
    }
  }

  /**
   * Send a command to the bridge and wait for response
   *
   * @param command - The command to send
   * @param payload - Optional payload (will be base64 encoded)
   * @returns Promise resolving to the response string
   */
  private async sendCommand(command: string, payload?: Buffer | string): Promise<string> {
    if (!this.socket || !this.isConnected) {
      throw new Error('Not connected to EnclaveBridge');
    }

    if (this.pendingRequest) {
      throw new Error('Another request is pending');
    }

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pendingRequest = null;
        reject(new Error(`Request timeout after ${this.timeout}ms`));
      }, this.timeout);

      this.pendingRequest = { resolve, reject, timer };

      let message: string;
      if (payload) {
        const base64Payload =
          typeof payload === 'string' ? Buffer.from(payload).toString('base64') : payload.toString('base64');
        message = `${command}:${base64Payload}\n`;
      } else {
        message = `${command}\n`;
      }

      this.socket!.write(message);
    });
  }

  /**
   * Parse the bridge response
   *
   * @param response - Raw response string
   * @returns Parsed response object
   */
  private parseResponse(response: string): BridgeResponse {
    const colonIndex = response.indexOf(':');
    if (colonIndex === -1) {
      return { success: false, error: `Invalid response format: ${response}` };
    }

    const status = response.substring(0, colonIndex);
    const data = response.substring(colonIndex + 1);

    if (status === 'OK') {
      return { success: true, data };
    } else if (status === 'ERROR') {
      return { success: false, error: data };
    } else {
      return { success: false, error: `Unknown response status: ${status}` };
    }
  }

  // ============================================================================
  // Public Key Operations
  // ============================================================================

  /**
   * Get the secp256k1 public key used for ECIES operations
   *
   * This key is used for ECIES encryption/decryption and is persisted
   * in the macOS Keychain.
   *
   * @returns Promise resolving to the public key info
   */
  async getPublicKey(): Promise<PublicKeyInfo> {
    const response = await this.sendCommand('GET_PUBLIC_KEY');
    const parsed = this.parseResponse(response);

    if (!parsed.success) {
      throw new Error(`Failed to get public key: ${parsed.error}`);
    }

    const base64Key = parsed.data!;
    const buffer = Buffer.from(base64Key, 'base64');

    return {
      base64: base64Key,
      buffer,
      hex: buffer.toString('hex'),
      compressed: buffer.length === 33,
    };
  }

  /**
   * Get the Secure Enclave P-256 public key
   *
   * This key is stored in the Apple Secure Enclave and can only be
   * used for signing operations. The private key never leaves the
   * Secure Enclave.
   *
   * @returns Promise resolving to the Secure Enclave public key info
   */
  async getEnclavePublicKey(): Promise<PublicKeyInfo> {
    const response = await this.sendCommand('GET_ENCLAVE_PUBLIC_KEY');
    const parsed = this.parseResponse(response);

    if (!parsed.success) {
      throw new Error(`Failed to get Enclave public key: ${parsed.error}`);
    }

    const base64Key = parsed.data!;
    const buffer = Buffer.from(base64Key, 'base64');

    return {
      base64: base64Key,
      buffer,
      hex: buffer.toString('hex'),
      compressed: buffer.length === 33, // P-256 keys are typically uncompressed (65 bytes)
    };
  }

  /**
   * Set the peer's public key for ECDH operations
   *
   * This stores the peer's secp256k1 public key for deriving shared secrets.
   *
   * @param publicKey - The peer's public key (base64, hex, or Buffer)
   */
  async setPeerPublicKey(publicKey: string | Buffer): Promise<void> {
    let keyBuffer: Buffer;

    if (Buffer.isBuffer(publicKey)) {
      keyBuffer = publicKey;
    } else if (typeof publicKey === 'string') {
      // Try to detect format
      if (publicKey.length === 66 || publicKey.length === 130) {
        // Likely hex (33 or 65 bytes)
        keyBuffer = Buffer.from(publicKey, 'hex');
      } else {
        // Assume base64
        keyBuffer = Buffer.from(publicKey, 'base64');
      }
    } else {
      throw new Error('Public key must be a string or Buffer');
    }

    const response = await this.sendCommand('SET_PEER_PUBLIC_KEY', keyBuffer);
    const parsed = this.parseResponse(response);

    if (!parsed.success) {
      throw new Error(`Failed to set peer public key: ${parsed.error}`);
    }
  }

  // ============================================================================
  // Secure Enclave Operations
  // ============================================================================

  /**
   * Sign data using the Secure Enclave P-256 key
   *
   * The private key never leaves the Secure Enclave - all signing
   * operations are performed within the secure hardware.
   *
   * @param data - Data to sign (will be hashed with SHA-256 first)
   * @returns Promise resolving to the signature
   */
  async enclaveSign(data: Buffer | string): Promise<SignatureResult> {
    const dataBuffer = typeof data === 'string' ? Buffer.from(data) : data;
    const response = await this.sendCommand('ENCLAVE_SIGN', dataBuffer);
    const parsed = this.parseResponse(response);

    if (!parsed.success) {
      throw new Error(`Failed to sign: ${parsed.error}`);
    }

    const signatureBase64 = parsed.data!;
    const signatureBuffer = Buffer.from(signatureBase64, 'base64');

    return {
      base64: signatureBase64,
      buffer: signatureBuffer,
      hex: signatureBuffer.toString('hex'),
      // P-256 signatures are typically DER encoded
      format: 'der',
    };
  }

  /**
   * Decrypt ECIES-encrypted data
   *
   * Uses the secp256k1 key to perform ECDH and decrypt the data.
   * Compatible with @digitaldefiance/node-ecies-lib format:
   * - version (1 byte)
   * - cipher suite (1 byte)
   * - encryption type (1 byte): 33=Basic, 66=WithLength, 99=Multiple
   * - ephemeral public key (33 bytes, compressed)
   * - IV (12 bytes)
   * - auth tag (16 bytes)
   * - ciphertext (variable)
   *
   * @param encryptedData - ECIES encrypted data
   * @returns Promise resolving to the decrypted data
   */
  async decrypt(encryptedData: Buffer): Promise<DecryptionResult> {
    const response = await this.sendCommand('ENCLAVE_DECRYPT', encryptedData);
    const parsed = this.parseResponse(response);

    if (!parsed.success) {
      throw new Error(`Failed to decrypt: ${parsed.error}`);
    }

    const plaintextBase64 = parsed.data!;
    const plaintextBuffer = Buffer.from(plaintextBase64, 'base64');

    return {
      base64: plaintextBase64,
      buffer: plaintextBuffer,
      text: plaintextBuffer.toString('utf8'),
    };
  }

  /**
   * Alias for decrypt() to match the Swift API naming
   *
   * @param encryptedData - ECIES encrypted data
   * @returns Promise resolving to the decrypted data
   */
  async enclaveDecrypt(encryptedData: Buffer): Promise<DecryptionResult> {
    return this.decrypt(encryptedData);
  }

  // ============================================================================
  // Key Generation
  // ============================================================================

  /**
   * Generate a new key in the Secure Enclave
   *
   * Note: This generates a new ephemeral key, not a replacement for
   * the main Secure Enclave key.
   *
   * @returns Promise resolving to the generated key info
   */
  async enclaveGenerateKey(): Promise<KeyGenerationResult> {
    const response = await this.sendCommand('ENCLAVE_GENERATE_KEY');
    const parsed = this.parseResponse(response);

    if (!parsed.success) {
      throw new Error(`Failed to generate key: ${parsed.error}`);
    }

    const publicKeyBase64 = parsed.data!;
    const publicKeyBuffer = Buffer.from(publicKeyBase64, 'base64');

    return {
      publicKey: {
        base64: publicKeyBase64,
        buffer: publicKeyBuffer,
        hex: publicKeyBuffer.toString('hex'),
        compressed: publicKeyBuffer.length === 33,
      },
    };
  }

  // ============================================================================
  // Utility Methods
  // ============================================================================

  /**
   * Check if the EnclaveBridge server is reachable
   *
   * @returns Promise resolving to true if reachable
   */
  async ping(): Promise<boolean> {
    try {
      await this.getPublicKey();
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Get connection information
   *
   * @returns Connection info object
   */
  getConnectionInfo(): {
    socketPath: string;
    state: ConnectionState;
    isConnected: boolean;
  } {
    return {
      socketPath: this.socketPath,
      state: this._connectionState,
      isConnected: this.isConnected,
    };
  }
}

/**
 * Create and connect an EnclaveBridge client
 *
 * @param options - Client configuration options
 * @returns Promise resolving to a connected client
 *
 * @example
 * ```typescript
 * const client = await createClient();
 * const publicKey = await client.getPublicKey();
 * await client.disconnect();
 * ```
 */
export async function createClient(options?: EnclaveBridgeClientOptions): Promise<EnclaveBridgeClient> {
  const client = new EnclaveBridgeClient(options);
  await client.connect();
  return client;
}

// Default export
export default EnclaveBridgeClient;
