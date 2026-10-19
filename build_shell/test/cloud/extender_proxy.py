#!/usr/bin/env python3
"""extender_proxy.py - a local plain-HTTP door to a remote Extender for a cloud session.

    build_shell/test/cloud/extender_proxy.py [--port 9100] [--target https://build.defold.com]

The cloud container has no DNS of its own: every outbound HTTPS connection goes through the agent proxy
($HTTPS_PROXY, CONNECT). The Extender client inside bob ignores the proxy settings and fails to resolve
build.defold.com, so bob is pointed at http://127.0.0.1:<port> (--build-server) and this script forwards
every request there through the proxy's CONNECT tunnel, streaming bodies both ways.
build_shell/test/cloud/instance.sh starts it when nothing answers on the port. Python 3.9+, standard
library only. Shared by every Defold project and synced by sync_defold_docs.py.
"""

import argparse
import http.client
import http.server
import os
import ssl
import urllib.parse

HOP = {"connection", "keep-alive", "proxy-connection", "transfer-encoding", "te", "trailer", "upgrade", "host"}
CHUNK = 1 << 16


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=9100)
    parser.add_argument("--target", default="https://build.defold.com")
    return parser.parse_args()


def upstream_connection(target):
    host = urllib.parse.urlsplit(target).hostname
    context = ssl.create_default_context(cafile=os.environ.get("SSL_CERT_FILE") or None)
    proxy = urllib.parse.urlsplit(os.environ["HTTPS_PROXY"])
    connection = http.client.HTTPSConnection(proxy.hostname, proxy.port, context=context, timeout=1800)
    connection.set_tunnel(host, 443)
    return connection, host


def request_body(handler):
    if handler.headers.get("Transfer-Encoding", "").lower() == "chunked":
        return read_chunked(handler.rfile)
    return handler.rfile.read(int(handler.headers.get("Content-Length", 0)))


def read_chunked(stream):
    parts = []
    while True:
        size = int(stream.readline().split(b";")[0], 16)
        if size == 0:
            stream.readline()
            return b"".join(parts)
        parts.append(stream.read(size))
        stream.readline()


def make_handler(target):
    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def forward(self):
            body = request_body(self)
            connection, host = upstream_connection(target)
            headers = {key: value for key, value in self.headers.items() if key.lower() not in HOP}
            headers["Host"] = host
            headers["Content-Length"] = str(len(body))
            connection.request(self.command, self.path, body=body, headers=headers)
            response = connection.getresponse()
            self.send_response(response.status, response.reason)
            bodiless = self.command == "HEAD" or response.status in (204, 304)
            for key, value in response.getheaders():
                if key.lower() not in HOP and (bodiless or key.lower() != "content-length"):
                    self.send_header(key, value)
            if bodiless:
                self.end_headers()
                connection.close()
                return
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            while chunk := response.read(CHUNK):
                self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk))
            self.wfile.write(b"0\r\n\r\n")
            connection.close()

        do_GET = do_POST = do_PUT = do_HEAD = do_DELETE = forward

        def log_message(self, format, *args):
            print(f"{self.command} {self.path} -> {args[1] if len(args) > 1 else ''}", flush=True)

    return Handler


def main():
    args = parse_args()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), make_handler(args.target))
    print(f"EXTENDER_PROXY=http://127.0.0.1:{args.port} -> {args.target}", flush=True)
    server.serve_forever()


main()
