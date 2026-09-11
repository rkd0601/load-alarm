#!/usr/bin/env python3
"""Build and serve the Flutter web app on localhost using Python's standard library."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()


def main():
    parser = argparse.ArgumentParser(description='보스 알림 로컬 웹 서버')
    parser.add_argument('--port', type=int, default=8080)
    parser.add_argument('--no-build', action='store_true',
                        help='기존 build/web을 사용하여 바로 실행')
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error('포트는 1~65535 사이여야 합니다.')

    output = ROOT / 'build' / 'web'
    config = ROOT / 'config' / 'firebase.web.json'
    if not args.no_build:
        if not config.is_file():
            parser.error('config/firebase.web.json이 필요합니다. firebase.web.example.json을 참고하세요.')
        command = ['flutter', 'build', 'web', '--pwa-strategy=none',
                   f'--dart-define-from-file={config}']
        try:
            subprocess.run(command, cwd=ROOT, check=True)
        except FileNotFoundError:
            parser.error('flutter를 찾을 수 없습니다. Flutter SDK의 bin을 PATH에 추가하세요.')
        except subprocess.CalledProcessError as error:
            return error.returncode

    if not (output / 'index.html').is_file():
        parser.error('웹 빌드가 없습니다. --no-build 없이 다시 실행하세요.')
    try:
        server = ThreadingHTTPServer(
            ('127.0.0.1', args.port), partial(Handler, directory=str(output)))
    except OSError as error:
        parser.error(f'서버를 시작하지 못했습니다: {error}. --port로 다른 포트를 지정하세요.')
    print(f'로컬 웹: http://localhost:{args.port}', flush=True)
    print('Firebase는 config/firebase.web.json에 지정된 실제 프로젝트를 사용합니다.', flush=True)
    print('종료: Ctrl+C', flush=True)
    with server:
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
    return 0


if __name__ == '__main__':
    sys.exit(main())
