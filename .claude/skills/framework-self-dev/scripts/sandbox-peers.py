#!/usr/bin/env python3
"""盲跑候選的假收件者：一個 stdio MCP server，提供 list_agents 與 send_message 兩個工具。

compare-skill-versions.py 把 Claude Code 的 SendMessage／ListAgents 拿掉，接上這一支。候選要送的
每一則訊息 append 一行 JSON 到第一個參數指名的檔案，不碰這台機器上任何一個真的 session（DP-980）。

用法：sandbox-peers.py <sent.jsonl>
"""
import json
import sys
import time

TOOLS = [
    {"name": "list_agents",
     "description": "List the other Claude sessions on this machine that you can message.",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "send_message",
     "description": "Send a message to another Claude session on this machine by its name.",
     "inputSchema": {"type": "object",
                     "properties": {"to": {"type": "string"}, "message": {"type": "string"},
                                    "summary": {"type": "string"}},
                     "required": ["to", "message"]}},
]


def call(sent, name, args):
    """Run one tool call; return the text the candidate sees."""
    if name == "list_agents":
        return "沒有其他 session 在線上。訊息仍可用 send_message 以名字送出，對方上線後會收到。"
    if name == "send_message":
        with open(sent, "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"at": time.strftime("%Y-%m-%dT%H:%M:%S"), **args}, ensure_ascii=False) + "\n")
        return f"已送出給 {args.get('to', '')}。"
    raise KeyError(name)


def main():
    sent = sys.argv[1]
    for line in sys.stdin:
        if not line.strip():
            continue
        req = json.loads(line)
        if "id" not in req:  # notification：不回
            continue
        method, rid = req.get("method"), req["id"]
        if method == "initialize":
            result = {"protocolVersion": req.get("params", {}).get("protocolVersion", "2024-11-05"),
                      "capabilities": {"tools": {}}, "serverInfo": {"name": "peers", "version": "1"}}
        elif method == "tools/list":
            result = {"tools": TOOLS}
        elif method == "tools/call":
            params = req.get("params", {})
            try:
                text = call(sent, params.get("name"), params.get("arguments") or {})
                result = {"content": [{"type": "text", "text": text}]}
            except KeyError:
                result = {"content": [{"type": "text", "text": "unknown tool"}], "isError": True}
        elif method == "ping":
            result = {}
        else:
            print(json.dumps({"jsonrpc": "2.0", "id": rid,
                              "error": {"code": -32601, "message": f"method not found: {method}"}}), flush=True)
            continue
        print(json.dumps({"jsonrpc": "2.0", "id": rid, "result": result}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
