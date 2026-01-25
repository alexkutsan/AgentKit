require "../spec_helper"
require "webmock"
require "../../src/agent_kit/mcp_client/client"
require "../../src/agent_kit/mcp_client/manager"

# E2E tests for MCP Client with real MCP server
# Requires: MCP server running on http://localhost:8000/mcp
# Start server: cd /tmp/mcp-test && python simple_streamable_http_mcp_server.py

MCP_TEST_URL = "http://localhost:8000/mcp"

describe AgentKit::MCPClient::Client, tags: "integration" do
  before_each do
    WebMock.allow_net_connect = true
  end
  describe "#connect" do
    it "connects to real MCP server and performs initialize handshake" do
      config = AgentKit::MCPServerConfig.new(type: "http", url: MCP_TEST_URL)
      client = AgentKit::MCPClient::Client.new("test", config)
      client.connect

      client.connected?.should be_true
      client.server_info.should_not be_nil
      client.server_capabilities.should_not be_nil

      client.close
    end
  end

  describe "#list_tools" do
    it "retrieves list of tools from MCP server" do
      config = AgentKit::MCPServerConfig.new(type: "http", url: MCP_TEST_URL)
      client = AgentKit::MCPClient::Client.new("test", config)
      client.connect

      tools = client.list_tools

      tools.should_not be_empty
      tool_names = tools.map(&.name)
      tool_names.should contain("hello_world")
      tool_names.should contain("add_numbers")

      client.close
    end
  end

  describe "#call_tool" do
    it "calls hello_world tool with parameters" do
      config = AgentKit::MCPServerConfig.new(type: "http", url: MCP_TEST_URL)
      client = AgentKit::MCPClient::Client.new("test", config)
      client.connect

      args = JSON.parse(%({"name": "Crystal"}))
      result = client.call_tool("hello_world", args)

      result.error?.should be_false
      result.content.should_not be_empty
      result.text_content.should contain("Crystal")

      client.close
    end

    it "calls add_numbers tool and verifies result" do
      config = AgentKit::MCPServerConfig.new(type: "http", url: MCP_TEST_URL)
      client = AgentKit::MCPClient::Client.new("test", config)
      client.connect

      args = JSON.parse(%({"a": 5, "b": 3}))
      result = client.call_tool("add_numbers", args)

      result.error?.should be_false
      result.content.should_not be_empty
      result.text_content.should contain("8")

      client.close
    end

    it "handles tool call with missing parameters" do
      config = AgentKit::MCPServerConfig.new(type: "http", url: MCP_TEST_URL)
      client = AgentKit::MCPClient::Client.new("test", config)
      client.connect

      args = JSON.parse(%({"invalid": "params"}))
      result = client.call_tool("add_numbers", args)

      result.content.should_not be_nil

      client.close
    end
  end

  describe "session management" do
    it "maintains session ID across multiple requests" do
      config = AgentKit::MCPServerConfig.new(type: "http", url: MCP_TEST_URL)
      client = AgentKit::MCPClient::Client.new("test", config)
      client.connect

      session_id = client.transport.as(AgentKit::MCPClient::HttpTransport).session_id
      session_id.should_not be_nil

      client.list_tools
      client.transport.as(AgentKit::MCPClient::HttpTransport).session_id.should eq(session_id)

      args = JSON.parse(%({"name": "Test"}))
      client.call_tool("hello_world", args)
      client.transport.as(AgentKit::MCPClient::HttpTransport).session_id.should eq(session_id)

      client.close
    end
  end
end

describe AgentKit::MCPClient::Manager, tags: "integration" do
  before_each do
    WebMock.allow_net_connect = true
  end

  describe "#connect_all" do
    it "connects to multiple MCP servers" do
      servers = {
        "test1" => AgentKit::MCPServerConfig.new(type: "http", url: MCP_TEST_URL),
      }
      manager = AgentKit::MCPClient::Manager.new(servers)

      manager.connect_all

      manager.clients.size.should eq(1)
      manager.clients["test1"].connected?.should be_true

      manager.close_all
    end
  end

  describe "#call_tool" do
    it "routes tool call to correct server" do
      servers = {
        "test" => AgentKit::MCPServerConfig.new(type: "http", url: MCP_TEST_URL),
      }
      manager = AgentKit::MCPClient::Manager.new(servers)
      manager.connect_all

      args = JSON.parse(%({"a": 10, "b": 20}))
      result = manager.call_tool("test__add_numbers", args)

      result.error?.should be_false
      result.text_content.should contain("30")

      manager.close_all
    end
  end
end
