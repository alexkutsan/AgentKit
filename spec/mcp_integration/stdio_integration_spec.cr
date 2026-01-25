require "../spec_helper"
require "../../src/agent_kit/mcp_client/client"

module StdioIntegration
  PY_SERVER = <<-'PY'
import sys, json

def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    msg = json.loads(line)

    if "id" not in msg:
        continue

    rid = msg.get("id")
    method = msg.get("method")
    params = msg.get("params") or {}

    if method == "initialize":
        send({"jsonrpc":"2.0","id":rid,"result":{"protocolVersion":"2024-11-05","capabilities":{},"serverInfo":{"name":"test","version":"1.0"}}})
        continue

    if method == "tools/list":
        send({"jsonrpc":"2.0","id":rid,"result":{"tools":[
            {"name":"hello_world","description":"Say hello","inputSchema":{"type":"object"}},
            {"name":"add_numbers","description":"Add two numbers","inputSchema":{"type":"object"}}
        ]}})
        continue

    if method == "tools/call":
        name = params.get("name")
        args = params.get("arguments") or {}
        if name == "hello_world":
            who = args.get("name") or "World"
            send({"jsonrpc":"2.0","id":rid,"result":{"content":[{"type":"text","text":f"Hello, {who}!"}],"isError":False}})
        elif name == "add_numbers":
            a = args.get("a")
            b = args.get("b")
            send({"jsonrpc":"2.0","id":rid,"result":{"content":[{"type":"text","text":str(a + b)}],"isError":False}})
        else:
            send({"jsonrpc":"2.0","id":rid,"result":{"content":[{"type":"text","text":"Unknown tool"}],"isError":True}})
        continue

    send({"jsonrpc":"2.0","id":rid,"result":{}})
PY
end

# Integration tests for MCP stdio transport.
# Spawns a minimal python JSONL MCP server as a subprocess via StdioTransport.
describe AgentKit::MCPClient::Client, tags: "integration_stdio" do
  it "connects and lists tools via stdio" do
    config = AgentKit::MCPServerConfig.new(
      command: "python3",
      args: ["-u", "-c", StdioIntegration::PY_SERVER]
    )

    client = AgentKit::MCPClient::Client.new("test-stdio", config)
    client.connect

    tools = client.list_tools
    tools.map(&.name).should contain("hello_world")

    client.close
  end

  it "calls tool via stdio" do
    config = AgentKit::MCPServerConfig.new(
      command: "python3",
      args: ["-u", "-c", StdioIntegration::PY_SERVER]
    )

    client = AgentKit::MCPClient::Client.new("test-stdio", config)
    client.connect

    args = JSON.parse(%({"a": 5, "b": 3}))
    result = client.call_tool("add_numbers", args)

    result.error?.should be_false
    result.text_content.should contain("8")

    client.close
  end
end
