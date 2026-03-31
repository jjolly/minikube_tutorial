import { useState } from 'react';

export default function App() {
  const [publicKey, setPublicKey] = useState('');
  const [privateKey, setPrivateKey] = useState('');
  const [loading, setLoading] = useState(false);

  async function generate() {
    setLoading(true);
    setPublicKey('Loading...');
    setPrivateKey('Loading...');
    try {
      const response = await fetch('/genkey/api');
      const data = await response.json();
      setPublicKey(data.publicKey);
      setPrivateKey(data.privateKey);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div id="app">
      <h1>SSH Key Generator</h1>
      <p>Generate an ed25519 keypair from the Flask API behind nginx.</p>
      <button onClick={generate} disabled={loading}>
        {loading ? 'Generating…' : 'Generate keypair'}
      </button>
      <h2>Public key</h2>
      <pre>{publicKey}</pre>
      <h2>Private key</h2>
      <pre>{privateKey}</pre>
    </div>
  );
}
