import http.server
import os

os.chdir(os.path.dirname(os.path.abspath(__file__)))

class CORSHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

port = 9527
print(f'CORS server on http://localhost:{port}/')
http.server.HTTPServer(('localhost', port), CORSHandler).serve_forever()
