require "../spec_helper"
require "../../src/agent_kit/mcp_client/client"
require "webmock"

describe AgentKit::MCPClient::Client do
  before_each do
    WebMock.reset
  end

  describe "#initialize" do
    it "creates client with name and url" do
      config = AgentKit::MCPServerConfig.new(type: "http", url: "http://localhost:8000/mcp")
      client = AgentKit::MCPClient::Client.new("test", config)
      client.name.should eq("test")
      client.connected?.should be_false
    end
  end

  describe "#connect" do
    it "performs initialize handshake" do
      WebMock.stub(:post, "http://localhost:8000/mcp")
        .to_return(
          status: 200,
          headers: {
            "Content-Type"   => "application/json",
            "Mcp-Session-Id" => "session-xyz",
          },
          body: {
            jsonrpc: "2.0",
            id:      1,
            result:  {
              protocolVersion: "2024-11-05",
              capabilities:    {tools: {listChanged: false}},
              serverInfo:      {name: "test-server", version: "1.0.0"},
            },
          }.to_json
        )

      WebMock.stub(:post, "http://localhost:8000/mcp")
        .to_return(status: 202, body: "")

      config = AgentKit::MCPServerConfig.new(type: "http", url: "http://localhost:8000/mcp")
      client = AgentKit::MCPClient::Client.new("test", config)
      client.connect

      client.connected?.should be_true
      if server_info = client.server_info
        server_info.name.should eq("test-server")
      end
    end
  end

  describe "#list_tools" do
    it "returns list of tools" do
      WebMock.stub(:post, "http://localhost:8000/mcp")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {
            jsonrpc: "2.0",
            id:      1,
            result:  {
              tools: [
                {
                  name:        "add_numbers",
                  description: "Add two numbers",
                  inputSchema: {
                    type:       "object",
                    properties: {
                      a: {type: "number"},
                      b: {type: "number"},
                    },
                    required: ["a", "b"],
                  },
                },
              ],
            },
          }.to_json
        )

      config = AgentKit::MCPServerConfig.new(type: "http", url: "http://localhost:8000/mcp")
      client = AgentKit::MCPClient::Client.new("test", config)
      client.transport.as(AgentKit::MCPClient::HttpTransport).session_id = "session-123"

      tools = client.list_tools
      tools.size.should eq(1)
      tools[0].name.should eq("add_numbers")
      tools[0].description.should eq("Add two numbers")
    end
  end

  describe "#call_tool" do
    it "calls tool and returns result" do
      WebMock.stub(:post, "http://localhost:8000/mcp")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {
            jsonrpc: "2.0",
            id:      1,
            result:  {
              content: [{type: "text", text: "8"}],
              isError: false,
            },
          }.to_json
        )

      config = AgentKit::MCPServerConfig.new(type: "http", url: "http://localhost:8000/mcp")
      client = AgentKit::MCPClient::Client.new("test", config)
      client.transport.as(AgentKit::MCPClient::HttpTransport).session_id = "session-123"

      result = client.call_tool("add_numbers", JSON.parse(%q({"a": 5, "b": 3})))
      result.content.try(&.size).should eq(1)
      result.text_content.should eq("8")
    end
  end

  describe "#close" do
    it "clears session" do
      config = AgentKit::MCPServerConfig.new(type: "http", url: "http://localhost:8000/mcp")
      client = AgentKit::MCPClient::Client.new("test", config)
      client.transport.as(AgentKit::MCPClient::HttpTransport).session_id = "session-123"

      client.close

      client.connected?.should be_false
      client.server_info.should be_nil
    end
  end
end
