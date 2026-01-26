/**
 * Integration tests for EnclaveBridge Client
 *
 * These tests use a mock socket server to test the client's behavior
 * in a more realistic environment.
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { createServer, Server, Socket } from 'node:net';
import { EnclaveBridgeClient, createClient } from '../../src/index.js';
import { ECIESEncryptionType } from '../../src/types.js';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';

// Create a unique socket path for each test
const getTestSocketPath = () =>
  path.join(os.tmpdir(), `enclave-test-${Date.now()}-${Math.random().toString(36).slice(2)}.sock`);

describe('Integration: Client-Server Communication', () => {
  let server: Server;
  let socketPath: string;
  let clients: Socket[] = [];

  beforeEach(() => {
    socketPath = getTestSocketPath();
    clients = [];
  });

  afterEach(async () => {
    // Clean up clients
    for (const client of clients) {
      client.destroy();
    }

    // Clean up server
    if (server) {
      await new Promise<void>((resolve) => {
        server.close(() => resolve());
      });
    }

    // Remove socket file
    try {
      fs.unlinkSync(socketPath);
    } catch {
      // Ignore
    }
  });

  const startServer = (handler: (socket: Socket, data: string) => void): Promise<void> => {
    return new Promise((resolve) => {
      server = createServer((socket) => {
        clients.push(socket);
        socket.setEncoding('utf8');

        let buffer = '';
        socket.on('data', (data) => {
          buffer += data;
          const lines = buffer.split('\n');
          buffer = lines.pop() || '';

          for (const line of lines) {
            if (line) handler(socket, line);
          }
        });
      });

      server.listen(socketPath, () => resolve());
    });
  };

  describe('Connection handling', () => {
    it('should connect to a real socket server', async () => {
      await startServer(() => {});

      const client = new EnclaveBridgeClient({ socketPath });
      await client.connect();

      expect(client.isConnected).toBe(true);
      await client.disconnect();
    });

    it('should handle connection refused', async () => {
      const client = new EnclaveBridgeClient({ socketPath: '/nonexistent/path.sock' });

      // Add error listener to prevent uncaught exception
      client.on('error', () => {});

      await expect(client.connect()).rejects.toThrow();
      expect(client.isConnected).toBe(false);
    });

    it('should handle server disconnect', async () => {
      await startServer(() => {});

      const client = new EnclaveBridgeClient({ socketPath });
      
      // Add error listener to handle potential errors
      client.on('error', () => {});
      
      await client.connect();
      expect(client.isConnected).toBe(true);
      
      // Set up disconnect listener before closing
      const disconnectPromise = new Promise<void>((resolve, reject) => {
        const timeout = setTimeout(() => reject(new Error('Disconnect timeout')), 2000);
        client.on('disconnect', () => {
          clearTimeout(timeout);
          resolve();
        });
      });

      // Destroy all connected clients (server-side sockets tracked in `clients` array)
      clients.forEach(s => s.destroy());

      // Wait for disconnect
      await disconnectPromise;

      expect(client.isConnected).toBe(false);
    });
  });

  describe('Command-response flow', () => {
    it('should send and receive GET_PUBLIC_KEY', async () => {
      const testKey = Buffer.from('03' + 'ab'.repeat(32), 'hex');

      await startServer((socket, data) => {
        if (data === 'GET_PUBLIC_KEY') {
          socket.write(`OK:${testKey.toString('base64')}\n`);
        }
      });

      const client = new EnclaveBridgeClient({ socketPath });
      await client.connect();

      const result = await client.getPublicKey();

      expect(result.buffer).toEqual(testKey);
      expect(result.compressed).toBe(true);

      await client.disconnect();
    });

    it('should send and receive GET_ENCLAVE_PUBLIC_KEY', async () => {
      const testKey = Buffer.from('04' + 'cd'.repeat(64), 'hex');

      await startServer((socket, data) => {
        if (data === 'GET_ENCLAVE_PUBLIC_KEY') {
          socket.write(`OK:${testKey.toString('base64')}\n`);
        }
      });

      const client = new EnclaveBridgeClient({ socketPath });
      await client.connect();

      const result = await client.getEnclavePublicKey();

      expect(result.buffer).toEqual(testKey);
      expect(result.compressed).toBe(false);

      await client.disconnect();
    });

    it('should send SET_PEER_PUBLIC_KEY with payload', async () => {
      const peerKey = Buffer.from('03' + 'ef'.repeat(32), 'hex');
      let receivedCommand = '';

      await startServer((socket, data) => {
        receivedCommand = data;
        socket.write('OK:success\n');
      });

      const client = new EnclaveBridgeClient({ socketPath });
      await client.connect();

      await client.setPeerPublicKey(peerKey);

      expect(receivedCommand).toBe(`SET_PEER_PUBLIC_KEY:${peerKey.toString('base64')}`);

      await client.disconnect();
    });

    it('should send ENCLAVE_SIGN and receive signature', async () => {
      const testMessage = Buffer.from('message to sign');
      const testSignature = Buffer.from('mock_signature_bytes');

      await startServer((socket, data) => {
        if (data.startsWith('ENCLAVE_SIGN:')) {
          socket.write(`OK:${testSignature.toString('base64')}\n`);
        }
      });

      const client = new EnclaveBridgeClient({ socketPath });
      await client.connect();

      const result = await client.enclaveSign(testMessage);

      expect(result.buffer).toEqual(testSignature);
      expect(result.format).toBe('der');

      await client.disconnect();
    });

    it('should send ENCLAVE_DECRYPT and receive plaintext', async () => {
      const encrypted = Buffer.from('encrypted_data');
      const plaintext = Buffer.from('decrypted message');

      await startServer((socket, data) => {
        if (data.startsWith('ENCLAVE_DECRYPT:')) {
          socket.write(`OK:${plaintext.toString('base64')}\n`);
        }
      });

      const client = new EnclaveBridgeClient({ socketPath });
      await client.connect();

      const result = await client.decrypt(encrypted);

      expect(result.buffer).toEqual(plaintext);
      expect(result.text).toBe('decrypted message');

      await client.disconnect();
    });

    it('should send ENCLAVE_GENERATE_KEY and receive new key', async () => {
      const newKey = Buffer.from('03' + '11'.repeat(32), 'hex');

      await startServer((socket, data) => {
        if (data === 'ENCLAVE_GENERATE_KEY') {
          socket.write(`OK:${newKey.toString('base64')}\n`);
        }
      });

      const client = new EnclaveBridgeClient({ socketPath });
      await client.connect();

      const result = await client.enclaveGenerateKey();

      expect(result.publicKey.buffer).toEqual(newKey);

      await client.disconnect();
    });
  });

  describe('Error handling', () => {
    it('should handle ERROR responses', async () => {
      await startServer((socket, data) => {
        socket.write('ERROR:Key not found\n');
      });

      const client = new EnclaveBridgeClient({ socketPath });
      await client.connect();

      await expect(client.getPublicKey()).rejects.toThrow('Key not found');

      await client.disconnect();
    });

    it('should handle server closing during request', async () => {
      await startServer((socket, data) => {
        socket.destroy();
      });

      const client = new EnclaveBridgeClient({ socketPath });
      await client.connect();

      await expect(client.getPublicKey()).rejects.toThrow('Connection closed');
    });

    it('should handle timeout', async () => {
      await startServer(() => {
        // Never respond
      });

      const client = new EnclaveBridgeClient({ socketPath, timeout: 100 });
      await client.connect();

      await expect(client.getPublicKey()).rejects.toThrow('timeout');

      await client.disconnect();
    });
  });

  describe('Multiple requests', () => {
    it('should handle sequential requests', async () => {
      const key1 = Buffer.from('03' + 'aa'.repeat(32), 'hex');
      const key2 = Buffer.from('04' + 'bb'.repeat(64), 'hex');

      await startServer((socket, data) => {
        if (data === 'GET_PUBLIC_KEY') {
          socket.write(`OK:${key1.toString('base64')}\n`);
        } else if (data === 'GET_ENCLAVE_PUBLIC_KEY') {
          socket.write(`OK:${key2.toString('base64')}\n`);
        }
      });

      const client = new EnclaveBridgeClient({ socketPath });
      await client.connect();

      const result1 = await client.getPublicKey();
      const result2 = await client.getEnclavePublicKey();

      expect(result1.buffer).toEqual(key1);
      expect(result2.buffer).toEqual(key2);

      await client.disconnect();
    });

    it('should reject concurrent requests', async () => {
      await startServer((socket, data) => {
        // Delayed response
        setTimeout(() => {
          socket.write('OK:test\n');
        }, 50);
      });

      const client = new EnclaveBridgeClient({ socketPath });
      await client.connect();

      const promise1 = client.getPublicKey();
      await expect(client.getEnclavePublicKey()).rejects.toThrow('Another request is pending');

      await promise1.catch(() => {}); // Clean up
      await client.disconnect();
    });
  });

  describe('createClient helper', () => {
    it('should create and connect a client', async () => {
      await startServer(() => {});

      const client = await createClient({ socketPath });

      expect(client).toBeInstanceOf(EnclaveBridgeClient);
      expect(client.isConnected).toBe(true);

      await client.disconnect();
    });
  });
});

describe('Integration: ECIES Format Handling', () => {
  let server: Server;
  let socketPath: string;
  let clients: Socket[] = [];

  beforeEach(() => {
    socketPath = getTestSocketPath();
    clients = [];
  });

  afterEach(async () => {
    for (const client of clients) {
      client.destroy();
    }
    if (server) {
      await new Promise<void>((resolve) => {
        server.close(() => resolve());
      });
    }
    try {
      fs.unlinkSync(socketPath);
    } catch {
      // Ignore
    }
  });

  const startServer = (handler: (socket: Socket, data: string) => void): Promise<void> => {
    return new Promise((resolve) => {
      server = createServer((socket) => {
        clients.push(socket);
        socket.setEncoding('utf8');

        let buffer = '';
        socket.on('data', (data) => {
          buffer += data;
          const lines = buffer.split('\n');
          buffer = lines.pop() || '';

          for (const line of lines) {
            if (line) handler(socket, line);
          }
        });
      });

      server.listen(socketPath, () => resolve());
    });
  };

  it('should correctly encode and decode ECIES data for decryption', async () => {
    // Create mock ECIES encrypted data
    const ephemeralKey = Buffer.concat([Buffer.from([0x02]), Buffer.alloc(32, 0xab)]);
    const iv = Buffer.alloc(12, 0xcd);
    const authTag = Buffer.alloc(16, 0xef);
    const ciphertext = Buffer.from('encrypted content');

    const eciesData = Buffer.concat([
      Buffer.from([1, 0, ECIESEncryptionType.Basic]), // version, cipherSuite, type
      ephemeralKey,
      iv,
      authTag,
      ciphertext,
    ]);

    const plaintext = Buffer.from('hello world');

    await startServer((socket, data) => {
      if (data.startsWith('ENCLAVE_DECRYPT:')) {
        const payloadBase64 = data.split(':')[1];
        const receivedData = Buffer.from(payloadBase64, 'base64');

        // Verify the received data matches what we sent
        expect(receivedData).toEqual(eciesData);

        socket.write(`OK:${plaintext.toString('base64')}\n`);
      }
    });

    const client = new EnclaveBridgeClient({ socketPath });
    await client.connect();

    const result = await client.decrypt(eciesData);

    expect(result.text).toBe('hello world');

    await client.disconnect();
  });
});
