from flask import Flask, jsonify
import subprocess
import tempfile
from pathlib import Path

app = Flask(__name__)

@app.get('/genkey/api')
def genkey():
    with tempfile.TemporaryDirectory() as tmp:
        key_path = Path(tmp) / 'id_ed25519'
        subprocess.run([
            'ssh-keygen', '-t', 'ed25519', '-N', '', '-f', str(key_path)
        ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        private_key = key_path.read_text()
        public_key = key_path.with_suffix('.pub').read_text()
    return jsonify({
        'algorithm': 'ed25519',
        'publicKey': public_key,
        'privateKey': private_key,
    })

@app.get('/healthz')
def healthz():
    return {'status': 'ok'}
