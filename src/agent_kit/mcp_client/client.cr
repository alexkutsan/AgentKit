require "json"
require "mcprotocol"
require "../config"
require "./transport"
require "./stdio_transport"
require "./types"

module AgentKit::MCPClient
  class Client
    getter name : String
    getter transport : Transport
    getter server_info : MCProtocol::Implementation?
    getter server_capabilities : MCProtocol::ServerCapabilities?
    getter? initialized : Bool = false

    def initialize(@name : String, config : MCPServerConfig)
      @transport = build_transport(@name, config)
      @server_info = nil
      @server_capabilities = nil
      @initialized = false
    end

    def connect
      initialize_handshake
      send_initialized
      @initialized = true
    end

    def connected? : Bool
      @initialized && @transport.connected?
    end

    def list_tools : Array(MCProtocol::Tool)
      result = @transport.send_request("tools/list")
      MCProtocol::ListToolsResult.from_json(result.to_json).tools
    end

    def call_tool(tool_name : String, arguments : JSON::Any?) : CallToolResult
      params = JSON.parse({
        name:      tool_name,
        arguments: arguments,
      }.to_json)

      result = @transport.send_request("tools/call", params)
      CallToolResult.from_json(result.to_json)
    end

    def list_resources : Array(MCProtocol::Resource)
      result = @transport.send_request("resources/list")
      MCProtocol::ListResourcesResult.from_json(result.to_json).resources
    end

    def read_resource(uri : String) : MCProtocol::ReadResourceResult
      params = JSON.parse({uri: uri}.to_json)
      result = @transport.send_request("resources/read", params)
      MCProtocol::ReadResourceResult.from_json(result.to_json)
    end

    def list_prompts : Array(MCProtocol::Prompt)
      result = @transport.send_request("prompts/list")
      MCProtocol::ListPromptsResult.from_json(result.to_json).prompts
    end

    def get_prompt(prompt_name : String, arguments : JSON::Any? = nil) : MCProtocol::GetPromptResult
      params = JSON.parse({
        name:      prompt_name,
        arguments: arguments,
      }.to_json)

      result = @transport.send_request("prompts/get", params)
      MCProtocol::GetPromptResult.from_json(result.to_json)
    end

    def close
      @transport.close
      @server_info = nil
      @server_capabilities = nil
      @initialized = false
    end

    private def build_transport(name : String, config : MCPServerConfig) : Transport
      if config.stdio?
        command = config.command
        raise MCPError.new("mcpServers.#{name}.command is required") if command.nil? || command.empty?

        args = config.args || [] of String
        env = config.env || {} of String => String
        StdioTransport.new(command, args, env)
      else
        unless config.http?
          raise MCPError.new("mcpServers.#{name}: HTTP server config requires type=\"http\" and url")
        end

        url = config.url
        raise MCPError.new("mcpServers.#{name}.url is required") if url.nil? || url.empty?

        headers = config.headers || {} of String => String
        HttpTransport.new(url, headers)
      end
    end

    private def initialize_handshake
      params = JSON.parse({
        protocolVersion: "2024-11-05",
        capabilities:    {} of String => String,
        clientInfo:      {
          name:    "agent_kit",
          version: "0.1.0",
        },
      }.to_json)

      result = @transport.send_request("initialize", params)
      init_result = MCProtocol::InitializeResult.from_json(result.to_json)

      @server_info = init_result.serverInfo
      @server_capabilities = init_result.capabilities
    end

    private def send_initialized
      @transport.send_notification("notifications/initialized")
    end
  end
end
