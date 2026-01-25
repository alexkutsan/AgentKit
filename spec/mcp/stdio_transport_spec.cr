require "../spec_helper"
require "../../src/agent_kit/mcp_client/stdio_transport"

module StdioTest
  PY_SERVER = <<-'PY'
import sys, json, time

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    msg = json.loads(line)
    if "id" not in msg:
        continue

    rid = msg.get("id")
    method = msg.get("method")

    if method == "sleep":
        time.sleep(5)
        continue

    if method == "fail":
        out = {"jsonrpc":"2.0","id":rid,"error":{"code":-32000,"message":"Boom"}}
        sys.stdout.write(json.dumps(out) + "\n")
        sys.stdout.flush()
        continue

    out = {"jsonrpc":"2.0","id":rid,"result":{"ok":True,"method":method}}
    sys.stdout.write(json.dumps(out) + "\n")
    sys.stdout.flush()
PY
end

describe AgentKit::MCPClient::StdioTransport do
  it "matches request/response by id" do
    transport = AgentKit::MCPClient::StdioTransport.new(
      "python3",
      ["-u", "-c", StdioTest::PY_SERVER],
      {} of String => String,
      2.seconds
    )

    result = transport.send_request("tools/list")
    result["ok"].as_bool.should be_true
    result["method"].as_s.should eq("tools/list")

    transport.close
  end

  it "raises MCPError on error response" do
    transport = AgentKit::MCPClient::StdioTransport.new(
      "python3",
      ["-u", "-c", StdioTest::PY_SERVER],
      {} of String => String,
      2.seconds
    )

    expect_raises(AgentKit::MCPClient::MCPError, /Boom/) do
      transport.send_request("fail")
    end

    transport.close
  end

  it "times out requests" do
    transport = AgentKit::MCPClient::StdioTransport.new(
      "python3",
      ["-u", "-c", StdioTest::PY_SERVER],
      {} of String => String,
      200.milliseconds
    )

    expect_raises(AgentKit::MCPClient::MCPError, /timeout/i) do
      transport.send_request("sleep")
    end

    transport.close
  end
end
