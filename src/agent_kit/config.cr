require "json"
require "yaml"

module AgentKit
  struct MCPServerConfig
    include JSON::Serializable
    include YAML::Serializable

    property type : String?
    property url : String?
    property headers : Hash(String, String)?
    property command : String?
    property args : Array(String)?
    property env : Hash(String, String)?

    def initialize(
      @type : String? = nil,
      @url : String? = nil,
      @headers : Hash(String, String)? = nil,
      @command : String? = nil,
      @args : Array(String)? = nil,
      @env : Hash(String, String)? = nil,
    )
    end

    def stdio? : Bool
      !@command.nil?
    end

    def http? : Bool
      @type == "http"
    end
  end

  struct Config
    include JSON::Serializable
    include YAML::Serializable

    @[YAML::Field(key: "openai_api_key")]
    @[JSON::Field(key: "openai_api_key")]
    getter openai_api_key : String = ""

    @[YAML::Field(key: "openai_api_host")]
    @[JSON::Field(key: "openai_api_host")]
    getter openai_api_host : String = "https://api.openai.com"

    @[YAML::Field(key: "openai_model")]
    @[JSON::Field(key: "openai_model")]
    getter openai_model : String = "gpt-4o"

    @[YAML::Field(key: "max_iterations")]
    @[JSON::Field(key: "max_iterations")]
    getter max_iterations : Int32 = 10

    @[YAML::Field(key: "timeout_seconds")]
    @[JSON::Field(key: "timeout_seconds")]
    getter timeout_seconds : Int32 = 120

    @[YAML::Field(key: "mcp_servers")]
    @[JSON::Field(key: "mcp_servers")]
    property mcp_servers : Hash(String, MCPServerConfig) = {} of String => MCPServerConfig

    @[YAML::Field(key: "mcp_servers_json_path")]
    @[JSON::Field(key: "mcp_servers_json_path", ignore: true)]
    getter mcp_servers_json_path : String? = nil

    def initialize(
      @openai_api_key : String = "",
      @openai_api_host : String = "https://api.openai.com",
      @openai_model : String = "gpt-4o",
      @max_iterations : Int32 = 10,
      @timeout_seconds : Int32 = 120,
      @mcp_servers : Hash(String, MCPServerConfig) = {} of String => MCPServerConfig,
      @mcp_servers_json_path : String? = nil,
    )
    end

    def validate! : Nil
      raise ConfigError.new("openaiApiKey is required") if openai_api_key.empty?
      raise ConfigError.new("maxIterations must be positive") if max_iterations <= 0
      raise ConfigError.new("timeoutSeconds must be positive") if timeout_seconds <= 0

      validate_mcp_servers!
    end

    private def validate_mcp_servers! : Nil
      @mcp_servers.each do |name, server|
        if server.stdio?
          command = server.command
          raise ConfigError.new("mcpServers.#{name}.command is required") if command.nil? || command.empty?

          if server.type == "http" || server.url
            raise ConfigError.new("mcpServers.#{name}: stdio server cannot have type/url")
          end
        else
          unless server.type == "http"
            if server.url
              raise ConfigError.new("mcpServers.#{name}: HTTP server config requires type=\"http\"")
            end
            raise ConfigError.new("mcpServers.#{name}: missing type=\"http\" and url")
          end

          url = server.url
          raise ConfigError.new("mcpServers.#{name}.url is required") if url.nil? || url.empty?
        end
      end
    end

    def valid? : Bool
      validate!
      true
    rescue ConfigError
      false
    end
  end

  class ConfigError < Exception
  end
end
