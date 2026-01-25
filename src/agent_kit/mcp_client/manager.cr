require "./client"
require "./stdio_supervisor"
require "../../logger"

module AgentKit::MCPClient
  Log = AgentKit::Log.for("mcp")

  struct ToolInfo
    getter server_name : String
    getter tool : MCProtocol::Tool

    def initialize(@server_name : String, @tool : MCProtocol::Tool)
    end

    def full_name : String
      "#{@server_name}__#{@tool.name}"
    end
  end

  class Manager
    getter clients : Hash(String, Client)
    getter server_configs : Hash(String, AgentKit::MCPServerConfig)

    @stdio_holders = {} of String => ClientHolder
    @stdio_supervisors = {} of String => StdioSupervisor

    def initialize
      @clients = {} of String => Client
      @server_configs = {} of String => AgentKit::MCPServerConfig
    end

    def initialize(servers : Hash(String, AgentKit::MCPServerConfig))
      @clients = {} of String => Client
      @server_configs = {} of String => AgentKit::MCPServerConfig
      servers.each do |name, config|
        @server_configs[name] = config
        @clients[name] = Client.new(name, config)
      end
    end

    def add_server(name : String, config : AgentKit::MCPServerConfig)
      @server_configs[name] = config
      @clients[name] = Client.new(name, config)
    end

    def add_stdio_server(name : String, command : String, args : Array(String) = [] of String, env : Hash(String, String) = {} of String => String)
      config = AgentKit::MCPServerConfig.new(command: command, args: args, env: env)
      @server_configs[name] = config
      @clients[name] = Client.new(name, config)
    end

    def connect_all : Array(String)
      connected = [] of String
      @clients.each do |name, client|
        begin
          config = @server_configs[name]?
          if config && config.stdio?
            holder = @stdio_holders[name]?
            unless holder
              holder = ClientHolder.new(client)
              @stdio_holders[name] = holder
            end

            supervisor = @stdio_supervisors[name]?
            unless supervisor
              supervisor = StdioSupervisor.new(name, config, holder)
              @stdio_supervisors[name] = supervisor
            end

            supervisor.run

            if supervisor.ensure_connected
              @clients[name] = holder.client
              connected << name
            else
              Log.warn { "Failed to connect to stdio MCP server '#{name}'" }
            end
          else
            client.connect
            connected << name
          end
        rescue ex
          Log.warn { "Failed to connect to MCP server '#{name}': #{ex.message}" }
        end
      end
      connected
    end

    def close_all
      @stdio_supervisors.each_value(&.stop)
      @stdio_supervisors.clear

      @clients.each_value(&.close)
      @stdio_holders.clear
    end

    def all_tools : Array(ToolInfo)
      tools = [] of ToolInfo

      @clients.each do |server_name, _|
        client = current_client(server_name)
        client.list_tools.each do |tool|
          tools << ToolInfo.new(server_name, tool)
        end
      end

      tools
    end

    def call_tool(full_name : String, arguments : JSON::Any?) : CallToolResult
      server_name, tool_name = parse_tool_name(full_name)

      client = @clients[server_name]?
      raise MCPError.new("Unknown server: #{server_name}") unless client

      current_client(server_name).call_tool(tool_name, arguments)
    end

    def get_client(name : String) : Client?
      return nil unless @clients[name]?
      current_client(name)
    end

    private def current_client(name : String) : Client
      if holder = @stdio_holders[name]?
        holder.client
      else
        @clients[name]
      end
    end

    private def parse_tool_name(full_name : String) : {String, String}
      parts = full_name.split("__", 2)
      if parts.size == 2
        {parts[0], parts[1]}
      else
        raise MCPError.new("Invalid tool name format: #{full_name}. Expected 'server__tool'")
      end
    end
  end
end
