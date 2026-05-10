#!/usr/bin/env python3
"""
Legacy Refinement Preview Server

Serves a local markdown file as a styled HTML page with auto-refresh. This is a
legacy fallback / local debug helper only. The official refinement review path
is docs-manager Starlight, which reads canonical specs markdown directly from
docs-manager/src/content/docs/specs.

Usage:
    python3 scripts/refinement-preview.py .claude/designs/EPIC-530/refinement.md
    python3 scripts/refinement-preview.py .claude/designs/EPIC-530/refinement.md --port 3334

No dependencies required — uses Python stdlib + marked.js CDN.
"""

import argparse
import http.server
import json
import threading
import time
import webbrowser
from pathlib import Path


HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="zh-TW">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{title} — Refinement Preview</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }

  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
    line-height: 1.6;
    color: #24292f;
    background: #f6f8fa;
    padding: 0;
  }

  .header {
    background: #24292f;
    color: #fff;
    padding: 12px 24px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    position: sticky;
    top: 0;
    z-index: 100;
  }

  .header h1 {
    font-size: 16px;
    font-weight: 600;
  }

  .header .status {
    font-size: 13px;
    color: #8b949e;
  }

  .header .status.live {
    color: #3fb950;
  }

  .container {
    max-width: 960px;
    margin: 24px auto;
    padding: 32px 40px;
    background: #fff;
    border: 1px solid #d0d7de;
    border-radius: 6px;
  }

  /* GitHub-like markdown styles */
  .container h1 { font-size: 2em; border-bottom: 1px solid #d0d7de; padding-bottom: .3em; margin: 1em 0 .5em; }
  .container h2 { font-size: 1.5em; border-bottom: 1px solid #d0d7de; padding-bottom: .3em; margin: 1em 0 .5em; }
  .container h3 { font-size: 1.25em; margin: 1em 0 .5em; }
  .container h4 { font-size: 1em; margin: 1em 0 .5em; }

  .container p { margin: .5em 0; }
  .container ul, .container ol { padding-left: 2em; margin: .5em 0; }
  .container li { margin: .25em 0; }

  .container table {
    border-collapse: collapse;
    width: 100%;
    margin: .75em 0;
  }
  .container th, .container td {
    border: 1px solid #d0d7de;
    padding: 6px 13px;
    text-align: left;
  }
  .container th {
    background: #f6f8fa;
    font-weight: 600;
  }
  .container tr:nth-child(2n) {
    background: #f6f8fa;
  }

  .container code {
    background: #f6f8fa;
    padding: .2em .4em;
    border-radius: 3px;
    font-size: 85%;
  }
  .container pre {
    background: #f6f8fa;
    padding: 16px;
    border-radius: 6px;
    overflow-x: auto;
    margin: .75em 0;
  }
  .container pre code {
    background: none;
    padding: 0;
  }

  .container blockquote {
    border-left: 4px solid #d0d7de;
    color: #57606a;
    padding: 0 1em;
    margin: .75em 0;
  }

  .container hr {
    border: none;
    border-top: 1px solid #d0d7de;
    margin: 1.5em 0;
  }

  /* Checklist styling */
  .container .task-list-item {
    list-style: none;
    margin-left: -1.5em;
  }
  .container .task-list-item input {
    margin-right: .5em;
  }

  /* Confidence labels */
  .container code:has(+ :not(*)) { /* fallback */ }
  .high { color: #1a7f37; background: #dafbe1; }
  .medium { color: #9a6700; background: #fff8c5; }
  .low { color: #cf222e; background: #ffebe9; }
  .not-researched { color: #57606a; background: #f6f8fa; }

  .footer {
    text-align: center;
    padding: 16px;
    color: #8b949e;
    font-size: 13px;
  }
</style>
</head>
<body>

<div class="header">
  <h1>{title} — Refinement Preview</h1>
  <div class="status" id="status">Connecting...</div>
</div>

<div class="container" id="content">
  Loading...
</div>

<div class="footer">
  Auto-refreshes every 3 seconds &middot; Edit the markdown file to update
</div>

<script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
<script>
let lastContent = '';
let lastMtime = 0;

async function fetchContent() {
  try {
    const resp = await fetch('/api/content');
    const data = await resp.json();

    document.getElementById('status').textContent = 'Live — ' + data.mtime;
    document.getElementById('status').className = 'status live';

    if (data.content !== lastContent) {
      lastContent = data.content;
      document.getElementById('content').innerHTML = marked.parse(data.content);

      // Style confidence labels
      document.querySelectorAll('code').forEach(el => {
        const text = el.textContent;
        if (text === 'HIGH' || text === '[HIGH]') el.classList.add('high');
        else if (text === 'MEDIUM' || text === '[MEDIUM]') el.classList.add('medium');
        else if (text === 'LOW' || text === '[LOW]') el.classList.add('low');
        else if (text.includes('NOT_RESEARCHED')) el.classList.add('not-researched');
      });
    }
  } catch (e) {
    document.getElementById('status').textContent = 'Disconnected';
    document.getElementById('status').className = 'status';
  }
}

fetchContent();
setInterval(fetchContent, 3000);
</script>
</body>
</html>"""


class RefinementHandler(http.server.BaseHTTPRequestHandler):
    """HTTP handler that serves the preview HTML and markdown content API."""

    md_path: Path = None  # Set by factory

    def do_GET(self):
        if self.path == '/':
            self.send_html()
        elif self.path == '/api/content':
            self.send_content()
        else:
            self.send_error(404)

    def send_html(self):
        title = self.md_path.parent.name  # e.g., "EPIC-530"
        html = HTML_TEMPLATE.replace('{title}', title)
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()
        self.write_bytes(html.encode('utf-8'))

    def send_content(self):
        try:
            content = self.md_path.read_text(encoding='utf-8')
            mtime = time.strftime(
                '%H:%M:%S',
                time.localtime(self.md_path.stat().st_mtime)
            )
        except FileNotFoundError:
            content = '*Waiting for refinement.md to be created...*'
            mtime = '--:--:--'

        data = json.dumps({'content': content, 'mtime': mtime})
        self.send_response(200)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Cache-Control', 'no-cache')
        self.end_headers()
        self.write_bytes(data.encode('utf-8'))

    def write_bytes(self, data):
        self.wfile.write(data)

    def log_message(self, format, *args):
        # Suppress default access logging (too noisy with 3s polling)
        pass


def make_handler(md_path: Path):
    """Factory to create handler class with md_path bound."""
    class Handler(RefinementHandler):
        pass
    Handler.md_path = md_path
    return Handler


def main():
    parser = argparse.ArgumentParser(description='Refinement Preview Server')
    parser.add_argument('file', help='Path to refinement markdown file')
    parser.add_argument('--port', type=int, default=3333, help='Port (default: 3333)')
    parser.add_argument('--no-open', action='store_true', help='Do not auto-open browser')
    args = parser.parse_args()

    md_path = Path(args.file).resolve()

    # Create parent directory if needed (file may not exist yet)
    md_path.parent.mkdir(parents=True, exist_ok=True)

    if not md_path.exists():
        # Create a placeholder so the user knows it's working
        md_path.write_text(
            f'# Refinement — {md_path.parent.name}\n\n'
            '*Waiting for refinement content...*\n',
            encoding='utf-8'
        )

    handler = make_handler(md_path)
    server = http.server.HTTPServer(('127.0.0.1', args.port), handler)

    url = f'http://localhost:{args.port}'
    print(f'Refinement preview: {url}')
    print(f'Watching: {md_path}')
    print('Press Ctrl+C to stop\n')

    if not args.no_open:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nStopped.')
        server.shutdown()


if __name__ == '__main__':
    main()
