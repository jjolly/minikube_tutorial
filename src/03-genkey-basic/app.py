from flask import Flask, jsonify
import subprocess
import tempfile
from pathlib import Path

app = Flask(__name__)

@app.get('/genkey')
def genkey():
    with tempfile.TemporaryDirectory() as tmp:
        key_path = Path(tmp) / 'id_ed25519'
        subprocess.run([
            'ssh-keygen', '-t', 'ed25519', '-N', '', '-f', str(key_path)
        ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        private_key = key_path.read_text()
        public_key = key_path.with_suffix('.pub').read_text()
    return jsonify({
        'privateKey': private_key,
        'publicKey': public_key
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
