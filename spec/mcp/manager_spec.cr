require "../spec_helper"
require "../../src/agent_kit/mcp_client/manager"
require "webmock"

describe AgentKit::MCPClient::Manager do
  before_each do
    WebMock.reset
  end

  describe "#initialize" do
    it "creates empty manager" do
      manager = AgentKit::MCPClient::Manager.new
      manager.clients.should be_empty
    end

    it "creates manager from config" do
      servers = {
        "test1" => AgentKit::MCPServerConfig.new(type: "http", url: "http://localhost:8001/mcp"),
        "test2" => AgentKit::MCPServerConfig.new(type: "http", url: "http://localhost:8002/mcp"),
      }

      manager = AgentKit::MCPClient::Manager.new(servers)
      manager.clients.size.should eq(2)
      manager.clients["test1"].name.should eq("test1")
      manager.clients["test2"].name.should eq("test2")
    end
  end

  describe "#add_server" do
    it "adds server to manager" do
      manager = AgentKit::MCPClient::Manager.new
      manager.add_server("new", AgentKit::MCPServerConfig.new(type: "http", url: "http://localhost:9000/mcp"))

      manager.clients.size.should eq(1)
      manager.clients["new"].name.should eq("new")
    end
  end

  describe "#all_tools" do
    it "aggregates tools from all servers" do
      WebMock.stub(:post, "http://localhost:8001/mcp")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {
            jsonrpc: "2.0",
            id:      1,
            result:  {
              tools: [
                {name: "tool1", description: "Tool 1", inputSchema: {type: "object"}},
              ],
            },
          }.to_json
        )

      WebMock.stub(:post, "http://localhost:8002/mcp")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {
            jsonrpc: "2.0",
            id:      1,
            result:  {
              tools: [
                {name: "tool2", description: "Tool 2", inputSchema: {type: "object"}},
              ],
            },
          }.to_json
        )

      manager = AgentKit::MCPClient::Manager.new
      manager.add_server("server1", AgentKit::MCPServerConfig.new(type: "http", url: "http://localhost:8001/mcp"))
      manager.add_server("server2", AgentKit::MCPServerConfig.new(type: "http", url: "http://localhost:8002/mcp"))

      tools = manager.all_tools
      tools.size.should eq(2)
      tools[0].full_name.should eq("server1__tool1")
      tools[1].full_name.should eq("server2__tool2")
    end
  end

  describe "#call_tool" do
    it "routes call to correct server" do
      WebMock.stub(:post, "http://localhost:8001/mcp")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {
            jsonrpc: "2.0",
            id:      1,
            result:  {
              content: [{type: "text", text: "result"}],
              isError: false,
            },
          }.to_json
        )

      manager = AgentKit::MCPClient::Manager.new
      manager.add_server("myserver", AgentKit::MCPServerConfig.new(type: "http", url: "http://localhost:8001/mcp"))

      result = manager.call_tool("myserver__mytool", JSON.parse("{}"))
      result.content.try(&.size).should eq(1)
      result.text_content.should eq("result")
    end

    it "raises error for unknown server" do
      manager = AgentKit::MCPClient::Manager.new

      expect_raises(AgentKit::MCPClient::MCPError, "Unknown server: unknown") do
        manager.call_tool("unknown__tool", nil)
      end
    end

    it "raises error for invalid tool name format" do
      manager = AgentKit::MCPClient::Manager.new

      expect_raises(AgentKit::MCPClient::MCPError, "Invalid tool name format") do
        manager.call_tool("invalidname", nil)
      end
    end
  end

  describe "#get_client" do
    it "returns client by name" do
      manager = AgentKit::MCPClient::Manager.new
      manager.add_server("test", AgentKit::MCPServerConfig.new(type: "http", url: "http://localhost:8000/mcp"))

      client = manager.get_client("test")
      client.should_not be_nil
      if c = client
        c.name.should eq("test")
      end
    end

    it "returns nil for unknown name" do
      manager = AgentKit::MCPClient::Manager.new
      manager.get_client("unknown").should be_nil
    end
  end

  describe "#close_all" do
    it "closes all clients" do
      manager = AgentKit::MCPClient::Manager.new
      manager.add_server("test", AgentKit::MCPServerConfig.new(type: "http", url: "http://localhost:8000/mcp"))

      client = manager.get_client("test")
      client.should_not be_nil
      if c = client
        c.transport.as(AgentKit::MCPClient::HttpTransport).session_id = "session-1"

        manager.close_all
        c.connected?.should be_false
      end
    end
  end
end

describe AgentKit::MCPClient::ToolInfo do
  it "creates tool info" do
    tool = MCProtocol::Tool.from_json({
      name:        "test_tool",
      description: "A test tool",
      inputSchema: {type: "object"},
    }.to_json)

    info = AgentKit::MCPClient::ToolInfo.new("server1", tool)
    info.server_name.should eq("server1")
    info.tool.name.should eq("test_tool")
    info.full_name.should eq("server1__test_tool")
  end
end
