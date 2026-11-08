#!/usr/bin/env python3
"""Exercise the actual bundled HTTP/TLS modules against private loopback servers.
Usage: python3 .agents/test-github-tls.py /path/to/koreader/usr/lib/koreader
Requires Python, openssl, and an extracted KOReader build; creates no GitHub issues.
"""
import http.server
import json
import os
from pathlib import Path
import ssl
import subprocess
import sys
import tempfile
import threading

repo = Path(__file__).resolve().parent.parent
runtime = Path(sys.argv[1]).resolve()
received = []

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        assert self.headers['Authorization'] == 'Bearer FAKE_TLS_TEST_TOKEN'
        data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        assert data['title'] in ('Local TLS test', 'Legacy parser test')
        received.append(('POST', self.path))
        self.respond(201, {'number': 123})

    def do_GET(self):
        received.append(('GET', self.path))
        if self.path == '/redirect':
            self.send_response(301)
            self.send_header('Location', 'https://must-not-follow.example/')
            self.send_header('Content-Length', '0')
            self.end_headers()
        else:
            self.respond(200, [{'number': 123}])

    def respond(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

with tempfile.TemporaryDirectory(prefix='kanban-tls-') as directory:
    tmp = Path(directory)
    servers = []
    for name, host in [('good', 'api.github.com'), ('wrong', 'other.example'), ('untrusted', 'api.github.com')]:
        cert, key = tmp / f'{name}.pem', tmp / f'{name}.key'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                        '-keyout', str(key), '-out', str(cert), '-days', '1',
                        '-subj', f'/CN={host}', '-addext', f'subjectAltName=DNS:{host}'],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        servers.append(server)
    ca = tmp / 'ca.pem'
    ca.write_bytes((tmp / 'good.pem').read_bytes() + (tmp / 'wrong.pem').read_bytes())
    try:
        result = subprocess.run([str(runtime / 'luajit'), str(repo / '.agents/test-github-tls.lua'),
                                 str(repo), *(str(s.server_port) for s in servers)],
                                cwd=runtime, env={**os.environ, 'SSL_CERT_FILE': str(ca)},
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
        print(result.stdout, end='')
        if result.returncode:
            raise SystemExit(result.returncode)
        assert received == [('POST', '/post'), ('GET', '/get'), ('POST', '/post'), ('GET', '/redirect')], received
    finally:
        for server in servers:
            server.shutdown()
            server.server_close()
