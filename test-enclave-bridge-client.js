// test-enclave-bridge-client.js
// Node.js client for e2e testing with Enclave Bridge
// Exercises all safe (non-destructive) API endpoints
// Requires: npm install @digitaldefiance/node-ecies-lib

const net = require('net');
const fs = require('fs');
const ECIES = require('@digitaldefiance/node-ecies-lib');
const ecies = new ECIES.ECIESService();

// Socket paths to check (in order of preference)
const SOCKET_PATHS = [
  // Sandboxed app path
  `${process.env.HOME}/Library/Containers/com.JessicaMulein.EnclaveBridge/Data/.enclave/enclave-bridge.sock`,
  // Non-sandboxed path
  `${process.env.HOME}/.enclave/enclave-bridge.sock`,
  // Default path
  '/tmp/enclave-bridge.sock',
];

// Find the first existing socket path, or use env override
function findSocketPath() {
  if (process.env.ENCLAVE_SOCKET_PATH) {
    return process.env.ENCLAVE_SOCKET_PATH;
  }
  for (const p of SOCKET_PATHS) {
    if (fs.existsSync(p)) {
      return p;
    }
  }
  // Default to first path if none exist
  return SOCKET_PATHS[0];
}

const SOCKET_PATH = findSocketPath();

// Test results
const results = { passed: 0, failed: 0, skipped: 0 };

function log(icon, msg) {
  console.log(`${icon} ${msg}`);
}

function pass(test, detail = '') {
  results.passed++;
  log('✅', `PASS: ${test}${detail ? ' - ' + detail : ''}`);
}

function fail(test, detail = '') {
  results.failed++;
  log('❌', `FAIL: ${test}${detail ? ' - ' + detail : ''}`);
}

function skip(test, reason = '') {
  results.skipped++;
  log('⏭️', `SKIP: ${test}${reason ? ' - ' + reason : ''}`);
}

class TestClient {
  constructor(socketPath) {
    this.socketPath = socketPath;
    this.socket = null;
    this.pendingResolve = null;
  }

  connect() {
    return new Promise((resolve, reject) => {
      this.socket = net.createConnection(this.socketPath);
      this.socket.on('connect', resolve);
      this.socket.on('error', reject);
      this.socket.on('data', (data) => {
        if (this.pendingResolve) {
          try {
            this.pendingResolve(JSON.parse(data.toString()));
          } catch (e) {
            this.pendingResolve({ _parseError: e.message, _raw: data.toString() });
          }
          this.pendingResolve = null;
        }
      });
    });
  }

  disconnect() {
    return new Promise((resolve) => {
      if (this.socket) {
        this.socket.end();
        this.socket.on('close', resolve);
      } else {
        resolve();
      }
    });
  }

  send(cmd) {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pendingResolve = null;
        reject(new Error('Timeout waiting for response'));
      }, 5000);

      this.pendingResolve = (resp) => {
        clearTimeout(timeout);
        resolve(resp);
      };

      this.socket.write(JSON.stringify(cmd));
    });
  }
}

async function main() {
  console.log('═'.repeat(60));
  console.log('Enclave Bridge E2E Test Client');
  console.log('═'.repeat(60));
  console.log(`Socket: ${SOCKET_PATH}`);
  console.log('');

  const client = new TestClient(SOCKET_PATH);

  try {
    // ══════════════════════════════════════════════════════════
    // Connect
    // ══════════════════════════════════════════════════════════
    log('🔌', 'Connecting to Enclave Bridge...');
    await client.connect();
    pass('Connection established');
    console.log('');

    // ══════════════════════════════════════════════════════════
    // Test: HEARTBEAT
    // ══════════════════════════════════════════════════════════
    log('💓', 'Testing HEARTBEAT...');
    const heartbeat = await client.send({ cmd: 'HEARTBEAT' });
    if (heartbeat.ok === true && heartbeat.timestamp && heartbeat.service === 'enclave-bridge') {
      pass('HEARTBEAT', `timestamp=${heartbeat.timestamp}`);
    } else {
      fail('HEARTBEAT', JSON.stringify(heartbeat));
    }

    // ══════════════════════════════════════════════════════════
    // Test: VERSION
    // ══════════════════════════════════════════════════════════
    log('📦', 'Testing VERSION...');
    const version = await client.send({ cmd: 'VERSION' });
    if (version.appVersion && version.build && version.platform === 'macOS' && typeof version.uptimeSeconds === 'number') {
      pass('VERSION', `v${version.appVersion} build ${version.build}, uptime ${version.uptimeSeconds}s`);
    } else {
      fail('VERSION', JSON.stringify(version));
    }

    // ══════════════════════════════════════════════════════════
    // Test: INFO (alias)
    // ══════════════════════════════════════════════════════════
    log('ℹ️', 'Testing INFO...');
    const info = await client.send({ cmd: 'INFO' });
    if (info.appVersion && info.platform === 'macOS') {
      pass('INFO', 'returns same structure as VERSION');
    } else {
      fail('INFO', JSON.stringify(info));
    }

    // ══════════════════════════════════════════════════════════
    // Test: STATUS (before peer key)
    // ══════════════════════════════════════════════════════════
    log('📊', 'Testing STATUS (initial)...');
    const status1 = await client.send({ cmd: 'STATUS' });
    if (status1.ok === true && typeof status1.peerPublicKeySet === 'boolean' && typeof status1.enclaveKeyAvailable === 'boolean') {
      pass('STATUS (initial)', `peerKeySet=${status1.peerPublicKeySet}, enclaveAvailable=${status1.enclaveKeyAvailable}`);
    } else {
      fail('STATUS (initial)', JSON.stringify(status1));
    }

    // ══════════════════════════════════════════════════════════
    // Test: METRICS
    // ══════════════════════════════════════════════════════════
    log('📈', 'Testing METRICS...');
    const metrics = await client.send({ cmd: 'METRICS' });
    if (metrics.service === 'enclave-bridge' && typeof metrics.uptimeSeconds === 'number' && metrics.requestCounters !== undefined) {
      pass('METRICS', `uptime=${metrics.uptimeSeconds}s`);
    } else {
      fail('METRICS', JSON.stringify(metrics));
    }

    // ══════════════════════════════════════════════════════════
    // Test: GET_PUBLIC_KEY (ECIES secp256k1)
    // ══════════════════════════════════════════════════════════
    log('🔑', 'Testing GET_PUBLIC_KEY...');
    const pubKeyResp = await client.send({ cmd: 'GET_PUBLIC_KEY' });
    let bridgePubKey = null;
    if (pubKeyResp.publicKey) {
      bridgePubKey = Buffer.from(pubKeyResp.publicKey, 'base64');
      if (bridgePubKey.length === 33 || bridgePubKey.length === 65) {
        pass('GET_PUBLIC_KEY', `${bridgePubKey.length} bytes, prefix=0x${bridgePubKey[0].toString(16)}`);
      } else {
        fail('GET_PUBLIC_KEY', `unexpected length ${bridgePubKey.length}`);
      }
    } else if (pubKeyResp.error) {
      skip('GET_PUBLIC_KEY', pubKeyResp.error);
    } else {
      fail('GET_PUBLIC_KEY', JSON.stringify(pubKeyResp));
    }

    // ══════════════════════════════════════════════════════════
    // Test: GET_ENCLAVE_PUBLIC_KEY (Secure Enclave P-256)
    // ══════════════════════════════════════════════════════════
    log('🔐', 'Testing GET_ENCLAVE_PUBLIC_KEY...');
    const enclavePubResp = await client.send({ cmd: 'GET_ENCLAVE_PUBLIC_KEY' });
    if (enclavePubResp.publicKey) {
      const enclavePubKey = Buffer.from(enclavePubResp.publicKey, 'base64');
      pass('GET_ENCLAVE_PUBLIC_KEY', `${enclavePubKey.length} bytes (P-256)`);
    } else if (enclavePubResp.error) {
      skip('GET_ENCLAVE_PUBLIC_KEY', enclavePubResp.error);
    } else {
      fail('GET_ENCLAVE_PUBLIC_KEY', JSON.stringify(enclavePubResp));
    }

    // ══════════════════════════════════════════════════════════
    // Test: LIST_KEYS
    // ══════════════════════════════════════════════════════════
    log('🗝️', 'Testing LIST_KEYS...');
    const listKeysResp = await client.send({ cmd: 'LIST_KEYS' });
    if (listKeysResp.ecies && Array.isArray(listKeysResp.ecies)) {
      const eciesCount = listKeysResp.ecies.length;
      const enclaveCount = listKeysResp.enclave ? listKeysResp.enclave.length : 0;
      pass('LIST_KEYS', `ecies=${eciesCount}, enclave=${enclaveCount}`);
    } else if (listKeysResp.error) {
      skip('LIST_KEYS', listKeysResp.error);
    } else {
      fail('LIST_KEYS', JSON.stringify(listKeysResp));
    }

    // ══════════════════════════════════════════════════════════
    // Test: SET_PEER_PUBLIC_KEY
    // ══════════════════════════════════════════════════════════
    log('🤝', 'Testing SET_PEER_PUBLIC_KEY...');
    const mnemonic = ecies.generateNewMnemonic();
    const clientKey = ecies.mnemonicToSimpleKeyPairBuffer(mnemonic);
    const clientPubKey = clientKey.publicKey;

    const setPeerResp = await client.send({
      cmd: 'SET_PEER_PUBLIC_KEY',
      publicKey: clientPubKey.toString('base64')
    });
    if (setPeerResp.ok === true) {
      pass('SET_PEER_PUBLIC_KEY', `set ${clientPubKey.length}-byte key`);
    } else {
      fail('SET_PEER_PUBLIC_KEY', JSON.stringify(setPeerResp));
    }

    // ══════════════════════════════════════════════════════════
    // Test: STATUS (after peer key)
    // ══════════════════════════════════════════════════════════
    log('📊', 'Testing STATUS (after peer key)...');
    const status2 = await client.send({ cmd: 'STATUS' });
    if (status2.peerPublicKeySet === true) {
      pass('STATUS (after peer key)', 'peerPublicKeySet=true');
    } else {
      fail('STATUS (after peer key)', `peerPublicKeySet=${status2.peerPublicKeySet}`);
    }

    // ══════════════════════════════════════════════════════════
    // Test: ENCLAVE_SIGN
    // ══════════════════════════════════════════════════════════
    log('✍️', 'Testing ENCLAVE_SIGN...');
    const testMessage = Buffer.from('Hello from e2e test!');
    const signResp = await client.send({
      cmd: 'ENCLAVE_SIGN',
      data: testMessage.toString('base64')
    });
    if (signResp.signature) {
      const sig = Buffer.from(signResp.signature, 'base64');
      pass('ENCLAVE_SIGN', `${sig.length}-byte signature`);
    } else if (signResp.error) {
      skip('ENCLAVE_SIGN', signResp.error);
    } else {
      fail('ENCLAVE_SIGN', JSON.stringify(signResp));
    }

    // ══════════════════════════════════════════════════════════
    // Test: ENCLAVE_DECRYPT
    // ══════════════════════════════════════════════════════════
    log('🔓', 'Testing ENCLAVE_DECRYPT...');
    if (bridgePubKey) {
      const secretMessage = Buffer.from('Secret message for decryption!');
      const encrypted = await ecies.encryptBasic(bridgePubKey, secretMessage);

      const decryptResp = await client.send({
        cmd: 'ENCLAVE_DECRYPT',
        data: encrypted.toString('base64')
      });

      if (decryptResp.plaintext) {
        const decrypted = Buffer.from(decryptResp.plaintext, 'base64');
        if (decrypted.toString() === secretMessage.toString()) {
          pass('ENCLAVE_DECRYPT', `"${decrypted.toString()}"`);
        } else {
          fail('ENCLAVE_DECRYPT', `mismatch: got "${decrypted.toString()}"`);
        }
      } else if (decryptResp.error) {
        fail('ENCLAVE_DECRYPT', decryptResp.error);
      } else {
        fail('ENCLAVE_DECRYPT', JSON.stringify(decryptResp));
      }
    } else {
      skip('ENCLAVE_DECRYPT', 'no bridge public key available');
    }

    // ══════════════════════════════════════════════════════════
    // Test: Error handling - invalid command
    // ══════════════════════════════════════════════════════════
    log('⚠️', 'Testing error handling (unknown command)...');
    const unknownResp = await client.send({ cmd: 'NONEXISTENT_COMMAND' });
    if (unknownResp.error && unknownResp.error.includes('Unknown command')) {
      pass('Unknown command error handling');
    } else {
      fail('Unknown command error handling', JSON.stringify(unknownResp));
    }

    // ══════════════════════════════════════════════════════════
    // Test: Error handling - missing data
    // ══════════════════════════════════════════════════════════
    log('⚠️', 'Testing error handling (missing data)...');
    const missingDataResp = await client.send({ cmd: 'ENCLAVE_SIGN' });
    if (missingDataResp.error) {
      pass('Missing data error handling');
    } else {
      fail('Missing data error handling', JSON.stringify(missingDataResp));
    }

    // ══════════════════════════════════════════════════════════
    // Test: ENCLAVE_GENERATE_KEY (stub - should return error)
    // ══════════════════════════════════════════════════════════
    log('🆕', 'Testing ENCLAVE_GENERATE_KEY (expected: not implemented)...');
    const genKeyResp = await client.send({ cmd: 'ENCLAVE_GENERATE_KEY' });
    if (genKeyResp.error && genKeyResp.error.includes('not implemented')) {
      pass('ENCLAVE_GENERATE_KEY', 'correctly returns not implemented');
    } else if (genKeyResp.publicKey) {
      pass('ENCLAVE_GENERATE_KEY', 'implemented and working');
    } else {
      fail('ENCLAVE_GENERATE_KEY', JSON.stringify(genKeyResp));
    }

    // ══════════════════════════════════════════════════════════
    // Test: ENCLAVE_ROTATE_KEY (stub - should return error)
    // NOTE: We test this but don't actually rotate (it's not implemented anyway)
    // ══════════════════════════════════════════════════════════
    log('🔄', 'Testing ENCLAVE_ROTATE_KEY (expected: not supported)...');
    const rotateResp = await client.send({ cmd: 'ENCLAVE_ROTATE_KEY' });
    if (rotateResp.error && rotateResp.error.includes('not supported')) {
      pass('ENCLAVE_ROTATE_KEY', 'correctly returns not supported');
    } else {
      fail('ENCLAVE_ROTATE_KEY', JSON.stringify(rotateResp));
    }

    console.log('');

  } catch (err) {
    fail('Test execution', err.message);
  } finally {
    await client.disconnect();
  }

  // ══════════════════════════════════════════════════════════
  // Summary
  // ══════════════════════════════════════════════════════════
  console.log('═'.repeat(60));
  console.log('Test Summary');
  console.log('═'.repeat(60));
  console.log(`  Passed:  ${results.passed}`);
  console.log(`  Failed:  ${results.failed}`);
  console.log(`  Skipped: ${results.skipped}`);
  console.log('═'.repeat(60));

  process.exit(results.failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});

