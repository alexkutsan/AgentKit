require "../spec_helper"
require "../../src/agent_kit/tool_registry"

describe AgentKit::ToolRegistry do
  describe "#initialize" do
    it "creates empty registry" do
      registry = AgentKit::ToolRegistry.new
      registry.size.should eq(0)
      registry.openai_tools.should be_empty
    end
  end

  describe "#register_mcp_tools" do
    it "registers tools from MCP server" do
      registry = AgentKit::ToolRegistry.new

      mcp_tools = [
        MCProtocol::Tool.from_json({
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
        }.to_json),
      ]

      registry.register_mcp_tools("math", mcp_tools)

      registry.size.should eq(1)
      registry.has_tool?("math__add_numbers").should be_true
    end

    it "registers tools from multiple servers" do
      registry = AgentKit::ToolRegistry.new

      tools1 = [
        MCProtocol::Tool.from_json({
          name:        "tool1",
          description: "Tool 1",
          inputSchema: {type: "object"},
        }.to_json),
      ]

      tools2 = [
        MCProtocol::Tool.from_json({
          name:        "tool2",
          description: "Tool 2",
          inputSchema: {type: "object"},
        }.to_json),
      ]

      registry.register_mcp_tools("server1", tools1)
      registry.register_mcp_tools("server2", tools2)

      registry.size.should eq(2)
      registry.has_tool?("server1__tool1").should be_true
      registry.has_tool?("server2__tool2").should be_true
    end
  end

  describe "#openai_tools" do
    it "returns tools in OpenAI format" do
      registry = AgentKit::ToolRegistry.new

      mcp_tools = [
        MCProtocol::Tool.from_json({
          name:        "get_weather",
          description: "Get weather for location",
          inputSchema: {
            type:       "object",
            properties: {
              location: {type: "string", description: "City name"},
            },
            required: ["location"],
          },
        }.to_json),
      ]

      registry.register_mcp_tools("weather", mcp_tools)

      openai_tools = registry.openai_tools
      openai_tools.size.should eq(1)

      tool = openai_tools[0]
      tool.type.should eq("function")
      tool.function.name.should eq("weather__get_weather")
      tool.function.description.should eq("Get weather for location")
      tool.function.parameters["type"].as_s.should eq("object")
      tool.function.parameters["properties"]["location"]["type"].as_s.should eq("string")
      tool.function.parameters["required"].as_a.map(&.as_s).should eq(["location"])
    end

    it "handles tools without description" do
      registry = AgentKit::ToolRegistry.new

      mcp_tools = [
        MCProtocol::Tool.from_json({
          name:        "no_desc",
          inputSchema: {type: "object"},
        }.to_json),
      ]

      registry.register_mcp_tools("test", mcp_tools)

      openai_tools = registry.openai_tools
      openai_tools[0].function.description.should eq("")
    end
  end

  describe "#resolve" do
    it "resolves full name to server and tool name" do
      registry = AgentKit::ToolRegistry.new

      mcp_tools = [
        MCProtocol::Tool.from_json({
          name:        "my_tool",
          description: "My tool",
          inputSchema: {type: "object"},
        }.to_json),
      ]

      registry.register_mcp_tools("myserver", mcp_tools)

      result = registry.resolve("myserver__my_tool")
      result.should_not be_nil
      if r = result
        server, tool = r
        server.should eq("myserver")
        tool.should eq("my_tool")
      end
    end

    it "returns nil for unknown tool" do
      registry = AgentKit::ToolRegistry.new
      registry.resolve("unknown__tool").should be_nil
    end
  end

  describe "#has_tool?" do
    it "returns true for registered tool" do
      registry = AgentKit::ToolRegistry.new

      mcp_tools = [
        MCProtocol::Tool.from_json({
          name:        "exists",
          inputSchema: {type: "object"},
        }.to_json),
      ]

      registry.register_mcp_tools("srv", mcp_tools)

      registry.has_tool?("srv__exists").should be_true
      registry.has_tool?("srv__notexists").should be_false
    end
  end

  describe "#clear" do
    it "removes all registered tools" do
      registry = AgentKit::ToolRegistry.new

      mcp_tools = [
        MCProtocol::Tool.from_json({
          name:        "tool",
          inputSchema: {type: "object"},
        }.to_json),
      ]

      registry.register_mcp_tools("srv", mcp_tools)
      registry.size.should eq(1)

      registry.clear
      registry.size.should eq(0)
      registry.openai_tools.should be_empty
    end
  end
end

describe AgentKit::ToolRegistry::RegisteredTool do
  it "creates registered tool with full name" do
    openai_tool = AgentKit::OpenAIApi::Tool.new(
      function: AgentKit::OpenAIApi::FunctionDef.new(
        name: "srv__mytool",
        description: "My tool"
      )
    )

    mcp_tool = MCProtocol::Tool.from_json({
      name:        "mytool",
      description: "My tool",
      inputSchema: {type: "object"},
    }.to_json)

    registered = AgentKit::ToolRegistry::RegisteredTool.new(
      server_name: "srv",
      original_name: "mytool",
      openai_tool: openai_tool,
      tool: mcp_tool
    )

    registered.server_name.should eq("srv")
    registered.original_name.should eq("mytool")
    registered.full_name.should eq("srv__mytool")
    registered.tool.name.should eq("mytool")
  end
end
