#!/usr/bin/env python3
"""Native Foundation adapter tests on a Mac; server and credentials are fixtures.

Run from the repo on macOS: python3 test/ios-connection/run.py
Or copy this directory, Hub.swift and ViewCapability.swift to an isolated Mac
folder and run there. No simulator, app state, or paired account is used.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import base64, hashlib, json, subprocess, tempfile, threading, time

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *args): pass
    def do_GET(self):
        if self.path == '/ws':
            key = self.headers.get('Sec-WebSocket-Key', '')
            accept = base64.b64encode(hashlib.sha1((key+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
            self.send_response(101)
            self.send_header('Upgrade', 'websocket'); self.send_header('Connection','Upgrade')
            self.send_header('Sec-WebSocket-Accept', accept); self.end_headers()
            self.wfile.write(b'\x82\x01\x00'); self.wfile.flush()
            time.sleep(2)
            return
        if self.path != '/client/capabilities':
            self.send_error(404); return
        credential = self.headers.get('Authorization','')
        cases = {'Bearer 1111':401,'Bearer 2222':403,'Bearer 3333':503,'Bearer 4444':302,'Bearer 5555':404}
        status = cases.get(credential,200)
        if credential == 'Bearer abcdef': time.sleep(3)
        if credential == 'Bearer 9999': time.sleep(12)
        body = json.dumps({'version':1,'views':{'version':1,'websocketQuery':'view=1','renderers':['mobile'],'compatibility':'explicit-only'}}).encode()
        if credential == 'Bearer 6666': body = b'x' * 16385
        self.send_response(status)
        self.send_header('Content-Length',str(len(body)))
        if status == 302: self.send_header('Location','/must-not-follow')
        self.end_headers()
        try: self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError): pass

root=Path(__file__).resolve().parent
sources=root.parents[1]/'mobile/ios/Backplane'
if not sources.is_dir(): sources=root
with tempfile.TemporaryDirectory(prefix='bp-ios-connection-') as work:
    binary=Path(work)/'test'
    subprocess.run(['swiftc','-parse-as-library',str(sources/'Hub.swift'),str(sources/'ViewCapability.swift'),str(root/'main.swift'),'-o',str(binary)],check=True)
    server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
    thread=threading.Thread(target=server.serve_forever,daemon=True); thread.start()
    try: subprocess.run([str(binary),f'http://127.0.0.1:{server.server_port}'],check=True,timeout=30)
    finally: server.shutdown(); server.server_close()
