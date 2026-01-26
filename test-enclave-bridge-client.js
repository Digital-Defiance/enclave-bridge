// test-enclave-bridge-client.js
// Minimal Node.js client for e2e testing with Enclave
// Requires: npm install @digitaldefiance/node-ecies-lib

const net = require('net');
const ECIES = require('@digitaldefiance/node-ecies-lib');
// Use ECIESService for keypair generation
const ecies = new ECIES.ECIESService();

// Use the sandboxed path for the Swift app
const SOCKET_PATH = '/Users/jessica/Library/Containers/com.JessicaMulein.EnclaveBridge/Data/.enclave/enclave-bridge.sock';

async function main() {
  // 1. Create ECIES keypair for this client using ECIESService
  const mnemonic = ecies.generateNewMnemonic();
  const clientKey = ecies.mnemonicToSimpleKeyPairBuffer(mnemonic);
  const clientPubKey = clientKey.publicKey;

  // 2. Connect to the Swift bridge
  const socket = net.createConnection(SOCKET_PATH);
  socket.on('error', err => console.error('Socket error:', err));

  // Helper to send/receive JSON
  function sendJson(obj) {
    const buf = Buffer.from(JSON.stringify(obj));
    socket.write(buf);
  }

  socket.on('connect', () => {
    // 3. Request Swift bridge public key
    sendJson({ cmd: 'GET_PUBLIC_KEY' });
  });

  let bridgePubKey = null;
  let testMessage = Buffer.from('hello enclave bridge!');

  socket.on('data', async (data) => {
    try {
      const resp = JSON.parse(data.toString());
      if (resp.publicKey && !bridgePubKey) {
        bridgePubKey = Buffer.from(resp.publicKey, 'base64');
        console.log('Bridge public key:', bridgePubKey.toString('hex'));
        console.log('Bridge public key length:', bridgePubKey.length);
        console.log('Bridge public key prefix (hex):', bridgePubKey.slice(0, 4).toString('hex'));
        // 4. Send our public key
        sendJson({ cmd: 'SET_PEER_PUBLIC_KEY', publicKey: clientPubKey.toString('base64') });
      } else if (resp.ok) {
        // 5. Test signing: ask bridge to sign a message
        sendJson({ cmd: 'ENCLAVE_SIGN', data: testMessage.toString('base64') });
      } else if (resp.signature) {
        console.log('Received signature from bridge:', resp.signature);
        // 6. (Optional) Test ECIES encryption/decryption
        // Encrypt a message for the bridge using ECIESService
        const encrypted = await ecies.encryptBasic(bridgePubKey, testMessage);
        console.log('Encrypted payload length:', encrypted.length);
        console.log('Encrypted payload hex:', encrypted.toString('hex'));
        sendJson({ cmd: 'ENCLAVE_DECRYPT', data: encrypted.toString('base64') });
      } else if (resp.plaintext) {
        const plaintext = Buffer.from(resp.plaintext, 'base64');
        console.log('Decrypted by bridge:', plaintext.toString());
        socket.end();
      } else if (resp.error) {
        console.error('Bridge error:', resp.error);
        socket.end();
      } else {
        console.log('Unknown response:', resp);
        socket.end();
      }
    } catch (e) {
      console.error('Failed to parse response:', e, data);
      socket.end();
    }
  });
}

main().catch(console.error);
