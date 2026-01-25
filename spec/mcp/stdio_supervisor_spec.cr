require "../spec_helper"
require "../../src/agent_kit/mcp_client/manager"

module SupervisorTest
  # This server exits on the first request after initialize to force a restart,
  # then succeeds for subsequent runs.
  PY_SERVER = <<-'PY'
import sys, json, os

flag = os.environ.get("RESTART_FLAG_FILE")

def has_restarted():
    return flag and os.path.exists(flag)

def mark_restarted():
    if flag:
        with open(flag, "w") as f:
            f.write("1")

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    msg = json.loads(line)
    if "id" not in msg:
        continue

    rid = msg.get("id")
    method = msg.get("method")

    if method == "initialize":
        out = {"jsonrpc":"2.0","id":rid,"result":{"protocolVersion":"2024-11-05","capabilities":{},"serverInfo":{"name":"test","version":"1.0"}}}
        sys.stdout.write(json.dumps(out) + "\n")
        sys.stdout.flush()
        continue

    if method == "tools/list":
        if not has_restarted():
            mark_restarted()
            sys.exit(1)
        out = {"jsonrpc":"2.0","id":rid,"result":{"tools":[]}}
        sys.stdout.write(json.dumps(out) + "\n")
        sys.stdout.flush()
        continue

    if not has_restarted():
        mark_restarted()
        sys.exit(1)

    out = {"jsonrpc":"2.0","id":rid,"result":{}}
    sys.stdout.write(json.dumps(out) + "\n")
    sys.stdout.flush()
PY
end

describe AgentKit::MCPClient::StdioSupervisor do
  it "auto-restarts crashed stdio server" do
    flag_file : String? = File.tempname("mcp_stdio_restart", ".flag")
    ff = flag_file || raise "Failed to create temp flag file name"
    File.delete(ff) if File.exists?(ff)

    servers = {
      "stdio" => AgentKit::MCPServerConfig.new(
        command: "python3",
        args: ["-u", "-c", SupervisorTest::PY_SERVER],
        env: {"RESTART_FLAG_FILE" => ff}
      ),
    }

    manager = AgentKit::MCPClient::Manager.new(servers)
    connected = manager.connect_all
    connected.should contain("stdio")

    client = manager.get_client("stdio") || raise "Client should exist"

    begin
      client.list_tools
    rescue
    end

    sleep 500.milliseconds

    client = manager.get_client("stdio") || raise "Client should exist after restart"
    tools = client.list_tools
    tools.should be_a(Array(MCProtocol::Tool))

    manager.close_all
  ensure
    if ff = flag_file
      File.delete(ff) if File.exists?(ff)
    end
  end
end
