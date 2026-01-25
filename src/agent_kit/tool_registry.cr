require "json"
require "mcprotocol"
require "./openai_api/types"
require "./mcp_client/manager"

module AgentKit
  class ToolRegistry
    struct RegisteredTool
      getter server_name : String
      getter original_name : String
      getter full_name : String
      getter openai_tool : OpenAIApi::Tool
      getter tool : MCProtocol::Tool

      def initialize(@server_name : String, @original_name : String, @openai_tool : OpenAIApi::Tool, @tool : MCProtocol::Tool)
        @full_name = "#{@server_name}__#{@original_name}"
      end
    end

    getter tools : Hash(String, RegisteredTool)

    def initialize
      @tools = {} of String => RegisteredTool
    end

    def register_mcp_tools(server_name : String, mcp_tools : Array(MCProtocol::Tool))
      mcp_tools.each do |mcp_tool|
        openai_tool = convert_to_openai(server_name, mcp_tool)
        full_name = "#{server_name}__#{mcp_tool.name}"

        @tools[full_name] = RegisteredTool.new(
          server_name: server_name,
          original_name: mcp_tool.name,
          openai_tool: openai_tool,
          tool: mcp_tool
        )
      end
    end

    def openai_tools : Array(OpenAIApi::Tool)
      @tools.values.map(&.openai_tool)
    end

    def resolve(full_name : String) : {String, String}?
      if tool = @tools[full_name]?
        {tool.server_name, tool.original_name}
      else
        nil
      end
    end

    def has_tool?(full_name : String) : Bool
      @tools.has_key?(full_name)
    end

    def size : Int32
      @tools.size
    end

    def clear
      @tools.clear
    end

    private def convert_to_openai(server_name : String, mcp_tool : MCProtocol::Tool) : OpenAIApi::Tool
      full_name = "#{server_name}__#{mcp_tool.name}"

      parameters = build_parameters(mcp_tool.inputSchema)

      OpenAIApi::Tool.new(
        type: "function",
        function: OpenAIApi::FunctionDef.new(
          name: full_name,
          description: mcp_tool.description || "",
          parameters: parameters
        )
      )
    end

    private def build_parameters(input_schema : MCProtocol::ToolInputSchema) : JSON::Any
      params = {} of String => JSON::Any

      params["type"] = JSON::Any.new(input_schema.type)

      if props = input_schema.properties
        params["properties"] = props
      else
        params["properties"] = JSON::Any.new({} of String => JSON::Any)
      end

      if required = input_schema.required
        params["required"] = JSON::Any.new(required.map { |r| JSON::Any.new(r) })
      else
        params["required"] = JSON::Any.new([] of JSON::Any)
      end

      JSON::Any.new(params)
    end
  end
end
