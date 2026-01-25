require "json"

module Agentish
  struct ConfigFile
    include JSON::Serializable

    @[JSON::Field(key: "openaiApiKey")]
    getter openai_api_key : String

    @[JSON::Field(key: "openaiApiHost")]
    getter openai_api_host : String = "https://api.openai.com"

    @[JSON::Field(key: "openaiModel")]
    getter openai_model : String = "gpt-4o"

    @[JSON::Field(key: "maxIterations")]
    getter max_iterations : Int32 = 10

    @[JSON::Field(key: "timeoutSeconds")]
    getter timeout_seconds : Int32 = 120

    @[JSON::Field(key: "mcpServers")]
    getter mcp_servers : Hash(String, AgentKit::MCPServerConfig) = {} of String => AgentKit::MCPServerConfig
  end

  def self.load_config(path : String) : AgentKit::Config
    raise AgentKit::ConfigError.new("Config file not found: #{path}") unless File.exists?(path)

    content = File.read(path)
    config_file = ConfigFile.from_json(content)

    config = AgentKit::Config.new(
      openai_api_key: config_file.openai_api_key,
      openai_api_host: config_file.openai_api_host,
      openai_model: config_file.openai_model,
      max_iterations: config_file.max_iterations,
      timeout_seconds: config_file.timeout_seconds,
      mcp_servers: expand_mcp_servers(config_file.mcp_servers)
    )

    config.validate!
    config
  rescue ex : JSON::ParseException
    raise AgentKit::ConfigError.new("Invalid config file format: #{ex.message}")
  end

  private def self.expand_mcp_servers(servers : Hash(String, AgentKit::MCPServerConfig)) : Hash(String, AgentKit::MCPServerConfig)
    expanded = {} of String => AgentKit::MCPServerConfig

    servers.each do |name, server|
      if server.stdio?
        if args = server.args
          server.args = args.map { |a| expand_env(a) }
        end

        if env = server.env
          expanded_env = {} of String => String
          env.each { |k, v| expanded_env[k] = expand_env(v) }
          server.env = expanded_env
        end
      else
        if url = server.url
          server.url = expand_env(url)
        end

        if headers = server.headers
          expanded_headers = {} of String => String
          headers.each { |k, v| expanded_headers[k] = expand_env(v) }
          server.headers = expanded_headers
        end
      end

      expanded[name] = server
    end

    expanded
  end

  private def self.expand_env(value : String) : String
    pattern = /\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-(.*?))?\}/

    value.gsub(pattern) do |match_str|
      md = pattern.match!(match_str)

      var_name = md[1]
      default = md[2]?
      env_value = ENV[var_name]?

      if d = default
        if env_value.nil? || env_value.empty?
          d
        else
          env_value.as(String)
        end
      else
        env_value || ""
      end
    end
  end
end
