// test-enclave-bridge-e2e.js
// Comprehensive E2E test suite for Enclave Bridge API commands
// Requires: npm install @digitaldefiance/node-ecies-lib
// Usage: node test-enclave-bridge-e2e.js

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

// Test results tracking
const results = {
  passed: 0,
  failed: 0,
  tests: []
};

function logTest(name, passed, details = '') {
  const status = passed ? '✅ PASS' : '❌ FAIL';
  console.log(`${status}: ${name}${details ? ' - ' + details : ''}`);
  results.tests.push({ name, passed, details });
  if (passed) results.passed++;
  else results.failed++;
}

function assert(condition, testName, details = '') {
  logTest(testName, condition, details);
  return condition;
}

class EnclaveBridgeTestClient {
  constructor(socketPath) {
    this.socketPath = socketPath;
    this.socket = null;
    this.responsePromise = null;
    this.responseResolve = null;
  }

  connect() {
    return new Promise((resolve, reject) => {
      this.socket = net.createConnection(this.socketPath);
      this.socket.on('connect', () => resolve());
      this.socket.on('error', reject);
      this.socket.on('data', (data) => {
        if (this.responseResolve) {
          try {
            const response = JSON.parse(data.toString());
            this.responseResolve(response);
          } catch (e) {
            this.responseResolve({ parseError: e.message, raw: data.toString() });
          }
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

  sendCommand(cmd) {
    return new Promise((resolve, reject) => {
      this.responseResolve = resolve;
      const timeout = setTimeout(() => {
        this.responseResolve = null;
        reject(new Error('Response timeout'));
      }, 5000);
      
      const originalResolve = resolve;
      this.responseResolve = (response) => {
        clearTimeout(timeout);
        originalResolve(response);
      };
      
      this.socket.write(JSON.stringify(cmd));
    });
  }
}

async function runTests() {
  console.log('='.repeat(60));
  console.log('Enclave Bridge E2E Test Suite');
  console.log('='.repeat(60));
  console.log(`Socket path: ${SOCKET_PATH}`);
  console.log('');

  const client = new EnclaveBridgeTestClient(SOCKET_PATH);
  
  try {
    // Connect to bridge
    console.log('Connecting to Enclave Bridge...');
    await client.connect();
    logTest('Connection established', true);
    console.log('');

    // ========================================
    // Test: HEARTBEAT
    // ========================================
    console.log('--- Testing HEARTBEAT ---');
    const heartbeat = await client.sendCommand({ cmd: 'HEARTBEAT' });
    assert(heartbeat.ok === true, 'HEARTBEAT returns ok: true');
    assert(typeof heartbeat.timestamp === 'string', 'HEARTBEAT returns timestamp');
    assert(heartbeat.service === 'enclave-bridge', 'HEARTBEAT returns correct service name');
    // Verify ISO8601 timestamp
    const tsDate = new Date(heartbeat.timestamp);
    assert(!isNaN(tsDate.getTime()), 'HEARTBEAT timestamp is valid ISO8601');
    console.log('');

    // ========================================
    // Test: VERSION
    // ========================================
    console.log('--- Testing VERSION ---');
    const version = await client.sendCommand({ cmd: 'VERSION' });
    assert(typeof version.appVersion === 'string', 'VERSION returns appVersion');
    assert(typeof version.build === 'string', 'VERSION returns build');
    assert(version.platform === 'macOS', 'VERSION returns correct platform');
    assert(typeof version.uptimeSeconds === 'number', 'VERSION returns uptimeSeconds');
    assert(version.uptimeSeconds >= 0, 'VERSION uptimeSeconds is non-negative');
    console.log(`  App version: ${version.appVersion}, Build: ${version.build}`);
    console.log('');

    // ========================================
    // Test: INFO (alias for VERSION)
    // ========================================
    console.log('--- Testing INFO ---');
    const info = await client.sendCommand({ cmd: 'INFO' });
    assert(typeof info.appVersion === 'string', 'INFO returns appVersion');
    assert(typeof info.build === 'string', 'INFO returns build');
    assert(info.platform === 'macOS', 'INFO returns correct platform');
    assert(typeof info.uptimeSeconds === 'number', 'INFO returns uptimeSeconds');
    console.log('');

    // ========================================
    // Test: STATUS (before peer key set)
    // ========================================
    console.log('--- Testing STATUS (initial) ---');
    const statusInitial = await client.sendCommand({ cmd: 'STATUS' });
    assert(statusInitial.ok === true, 'STATUS returns ok: true');
    assert(typeof statusInitial.peerPublicKeySet === 'boolean', 'STATUS returns peerPublicKeySet');
    assert(typeof statusInitial.enclaveKeyAvailable === 'boolean', 'STATUS returns enclaveKeyAvailable');
    console.log(`  Peer key set: ${statusInitial.peerPublicKeySet}, Enclave available: ${statusInitial.enclaveKeyAvailable}`);
    console.log('');

    // ========================================
    // Test: METRICS
    // ========================================
    console.log('--- Testing METRICS ---');
    const metrics = await client.sendCommand({ cmd: 'METRICS' });
    assert(metrics.service === 'enclave-bridge', 'METRICS returns correct service name');
    assert(typeof metrics.uptimeSeconds === 'number', 'METRICS returns uptimeSeconds');
    assert(metrics.uptimeSeconds >= 0, 'METRICS uptimeSeconds is non-negative');
    assert(typeof metrics.requestCounters === 'object', 'METRICS returns requestCounters object');
    console.log(`  Uptime: ${metrics.uptimeSeconds}s`);
    console.log('');

    // ========================================
    // Test: GET_PUBLIC_KEY
    // ========================================
    console.log('--- Testing GET_PUBLIC_KEY ---');
    const pubKeyResp = await client.sendCommand({ cmd: 'GET_PUBLIC_KEY' });
    const hasPublicKey = typeof pubKeyResp.publicKey === 'string';
    const hasError = typeof pubKeyResp.error === 'string';
    assert(hasPublicKey || hasError, 'GET_PUBLIC_KEY returns publicKey or error');
    
    let bridgePubKey = null;
    if (hasPublicKey) {
      bridgePubKey = Buffer.from(pubKeyResp.publicKey, 'base64');
      assert(bridgePubKey.length === 33 || bridgePubKey.length === 65, 
        'GET_PUBLIC_KEY returns valid key length', `got ${bridgePubKey.length} bytes`);
      console.log(`  Public key length: ${bridgePubKey.length} bytes`);
    } else {
      console.log(`  Error (expected in some environments): ${pubKeyResp.error}`);
    }
    console.log('');

    // ========================================
    // Test: GET_ENCLAVE_PUBLIC_KEY
    // ========================================
    console.log('--- Testing GET_ENCLAVE_PUBLIC_KEY ---');
    const enclavePubKeyResp = await client.sendCommand({ cmd: 'GET_ENCLAVE_PUBLIC_KEY' });
    const hasEnclavePubKey = typeof enclavePubKeyResp.publicKey === 'string';
    const hasEnclaveError = typeof enclavePubKeyResp.error === 'string';
    assert(hasEnclavePubKey || hasEnclaveError, 'GET_ENCLAVE_PUBLIC_KEY returns publicKey or error');
    
    if (hasEnclavePubKey) {
      const enclavePubKey = Buffer.from(enclavePubKeyResp.publicKey, 'base64');
      assert(enclavePubKey.length === 65, 
        'GET_ENCLAVE_PUBLIC_KEY returns 65-byte P-256 key', `got ${enclavePubKey.length} bytes`);
      console.log(`  Enclave public key length: ${enclavePubKey.length} bytes`);
    } else {
      console.log(`  Error (expected without Secure Enclave): ${enclavePubKeyResp.error}`);
    }
    console.log('');

    // ========================================
    // Test: LIST_KEYS
    // ========================================
    console.log('--- Testing LIST_KEYS ---');
    const listKeysResp = await client.sendCommand({ cmd: 'LIST_KEYS' });
    const hasListKeysError = typeof listKeysResp.error === 'string';
    
    if (hasListKeysError) {
      logTest('LIST_KEYS returns error (acceptable)', true, listKeysResp.error);
    } else {
      assert(Array.isArray(listKeysResp.ecies), 'LIST_KEYS returns ecies array');
      assert(Array.isArray(listKeysResp.enclave), 'LIST_KEYS returns enclave array');
      
      if (listKeysResp.ecies.length > 0) {
        const firstEcies = listKeysResp.ecies[0];
        assert(typeof firstEcies.id === 'string', 'LIST_KEYS ecies key has id');
        assert(typeof firstEcies.publicKey === 'string', 'LIST_KEYS ecies key has publicKey');
        console.log(`  ECIES keys: ${listKeysResp.ecies.length}, Enclave keys: ${listKeysResp.enclave.length}`);
      }
    }
    console.log('');

    // ========================================
    // Test: SET_PEER_PUBLIC_KEY
    // ========================================
    console.log('--- Testing SET_PEER_PUBLIC_KEY ---');
    const mnemonic = ecies.generateNewMnemonic();
    const clientKey = ecies.mnemonicToSimpleKeyPairBuffer(mnemonic);
    const clientPubKey = clientKey.publicKey;
    
    const setPeerResp = await client.sendCommand({
      cmd: 'SET_PEER_PUBLIC_KEY',
      publicKey: clientPubKey.toString('base64')
    });
    assert(setPeerResp.ok === true, 'SET_PEER_PUBLIC_KEY returns ok: true');
    console.log('');

    // ========================================
    // Test: STATUS (after peer key set)
    // ========================================
    console.log('--- Testing STATUS (after peer key set) ---');
    const statusAfter = await client.sendCommand({ cmd: 'STATUS' });
    assert(statusAfter.peerPublicKeySet === true, 'STATUS shows peerPublicKeySet: true after setting');
    console.log('');

    // ========================================
    // Test: SET_PEER_PUBLIC_KEY (invalid)
    // ========================================
    console.log('--- Testing SET_PEER_PUBLIC_KEY (invalid) ---');
    const setPeerInvalid = await client.sendCommand({
      cmd: 'SET_PEER_PUBLIC_KEY',
      publicKey: 'not-valid-base64!!!'
    });
    assert(typeof setPeerInvalid.error === 'string', 'SET_PEER_PUBLIC_KEY returns error for invalid base64');
    console.log('');

    // ========================================
    // Test: SET_PEER_PUBLIC_KEY (missing)
    // ========================================
    console.log('--- Testing SET_PEER_PUBLIC_KEY (missing key) ---');
    const setPeerMissing = await client.sendCommand({ cmd: 'SET_PEER_PUBLIC_KEY' });
    assert(typeof setPeerMissing.error === 'string', 'SET_PEER_PUBLIC_KEY returns error when key missing');
    console.log('');

    // ========================================
    // Test: ENCLAVE_SIGN
    // ========================================
    console.log('--- Testing ENCLAVE_SIGN ---');
    const testData = Buffer.from('Hello, Secure Enclave!');
    const signResp = await client.sendCommand({
      cmd: 'ENCLAVE_SIGN',
      data: testData.toString('base64')
    });
    const hasSignature = typeof signResp.signature === 'string';
    const hasSignError = typeof signResp.error === 'string';
    assert(hasSignature || hasSignError, 'ENCLAVE_SIGN returns signature or error');
    
    if (hasSignature) {
      const signature = Buffer.from(signResp.signature, 'base64');
      assert(signature.length > 0, 'ENCLAVE_SIGN returns non-empty signature');
      console.log(`  Signature length: ${signature.length} bytes`);
    } else {
      console.log(`  Error (expected without Secure Enclave): ${signResp.error}`);
    }
    console.log('');

    // ========================================
    // Test: ENCLAVE_SIGN (missing data)
    // ========================================
    console.log('--- Testing ENCLAVE_SIGN (missing data) ---');
    const signMissing = await client.sendCommand({ cmd: 'ENCLAVE_SIGN' });
    assert(typeof signMissing.error === 'string', 'ENCLAVE_SIGN returns error when data missing');
    console.log('');

    // ========================================
    // Test: ENCLAVE_DECRYPT
    // ========================================
    console.log('--- Testing ENCLAVE_DECRYPT ---');
    if (bridgePubKey) {
      const testMessage = Buffer.from('Secret message for decryption test');
      const encrypted = await ecies.encryptBasic(bridgePubKey, testMessage);
      
      const decryptResp = await client.sendCommand({
        cmd: 'ENCLAVE_DECRYPT',
        data: encrypted.toString('base64')
      });
      
      const hasPlaintext = typeof decryptResp.plaintext === 'string';
      const hasDecryptError = typeof decryptResp.error === 'string';
      assert(hasPlaintext || hasDecryptError, 'ENCLAVE_DECRYPT returns plaintext or error');
      
      if (hasPlaintext) {
        const decrypted = Buffer.from(decryptResp.plaintext, 'base64');
        assert(decrypted.toString() === testMessage.toString(), 
          'ENCLAVE_DECRYPT correctly decrypts message');
        console.log(`  Decrypted: "${decrypted.toString()}"`);
      } else {
        console.log(`  Error: ${decryptResp.error}`);
      }
    } else {
      logTest('ENCLAVE_DECRYPT (skipped - no bridge public key)', true, 'No bridge public key available');
    }
    console.log('');

    // ========================================
    // Test: ENCLAVE_DECRYPT (missing data)
    // ========================================
    console.log('--- Testing ENCLAVE_DECRYPT (missing data) ---');
    const decryptMissing = await client.sendCommand({ cmd: 'ENCLAVE_DECRYPT' });
    assert(typeof decryptMissing.error === 'string', 'ENCLAVE_DECRYPT returns error when data missing');
    console.log('');

    // ========================================
    // Test: ENCLAVE_DECRYPT (invalid base64)
    // ========================================
    console.log('--- Testing ENCLAVE_DECRYPT (invalid base64) ---');
    const decryptInvalid = await client.sendCommand({
      cmd: 'ENCLAVE_DECRYPT',
      data: 'not-valid-base64!!!'
    });
    assert(typeof decryptInvalid.error === 'string', 'ENCLAVE_DECRYPT returns error for invalid base64');
    console.log('');

    // ========================================
    // Test: ENCLAVE_GENERATE_KEY
    // ========================================
    console.log('--- Testing ENCLAVE_GENERATE_KEY ---');
    const genKeyResp = await client.sendCommand({ cmd: 'ENCLAVE_GENERATE_KEY' });
    const hasGenKey = typeof genKeyResp.publicKey === 'string';
    const hasGenKeyError = typeof genKeyResp.error === 'string';
    assert(hasGenKey || hasGenKeyError, 'ENCLAVE_GENERATE_KEY returns publicKey or error');
    if (hasGenKeyError) {
      console.log(`  Error (expected - not implemented): ${genKeyResp.error}`);
    }
    console.log('');

    // ========================================
    // Test: ENCLAVE_ROTATE_KEY
    // ========================================
    console.log('--- Testing ENCLAVE_ROTATE_KEY ---');
    const rotateKeyResp = await client.sendCommand({ cmd: 'ENCLAVE_ROTATE_KEY' });
    assert(typeof rotateKeyResp.error === 'string', 'ENCLAVE_ROTATE_KEY returns error (not supported)');
    assert(rotateKeyResp.error.includes('not supported'), 
      'ENCLAVE_ROTATE_KEY error mentions not supported');
    console.log(`  Error (expected): ${rotateKeyResp.error}`);
    console.log('');

    // ========================================
    // Test: Unknown command
    // ========================================
    console.log('--- Testing Unknown Command ---');
    const unknownResp = await client.sendCommand({ cmd: 'UNKNOWN_COMMAND_XYZ' });
    assert(typeof unknownResp.error === 'string', 'Unknown command returns error');
    assert(unknownResp.error.includes('Unknown command'), 'Error mentions unknown command');
    console.log('');

    // ========================================
    // Test: Invalid JSON (malformed request)
    // ========================================
    console.log('--- Testing Invalid Request (no cmd) ---');
    const invalidResp = await client.sendCommand({ foo: 'bar' });
    assert(typeof invalidResp.error === 'string', 'Request without cmd returns error');
    console.log('');

  } catch (error) {
    console.error('Test suite error:', error.message);
    logTest('Test suite execution', false, error.message);
  } finally {
    await client.disconnect();
  }

  // Print summary
  console.log('='.repeat(60));
  console.log('Test Summary');
  console.log('='.repeat(60));
  console.log(`Total: ${results.passed + results.failed}`);
  console.log(`Passed: ${results.passed}`);
  console.log(`Failed: ${results.failed}`);
  console.log('='.repeat(60));

  // Exit with appropriate code
  process.exit(results.failed > 0 ? 1 : 0);
}

runTests();
