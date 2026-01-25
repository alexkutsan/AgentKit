require "./spec_helper"

describe AgentKit::MCPServerConfig do
  it "deserializes from JSON" do
    json = %q({"type": "http", "url": "http://localhost:8000/mcp"})
    config = AgentKit::MCPServerConfig.from_json(json)
    config.type.should eq("http")
    config.url.should eq("http://localhost:8000/mcp")
    config.headers.should be_nil
  end

  it "deserializes with headers" do
    json = %q({"type": "http", "url": "http://localhost:8000/mcp", "headers": {"Authorization": "Bearer token123"}})
    config = AgentKit::MCPServerConfig.from_json(json)
    config.url.should eq("http://localhost:8000/mcp")
    config.headers.should eq({"Authorization" => "Bearer token123"})
  end

  it "deserializes stdio config" do
    json = %q({"command": "python", "args": ["-m", "server"], "env": {"A": "1"}})
    config = AgentKit::MCPServerConfig.from_json(json)
    config.command.should eq("python")
    config.args.should eq(["-m", "server"])
    config.env.should eq({"A" => "1"})
    config.type.should be_nil
    config.url.should be_nil
  end
end

describe Agentish::ConfigFile do
  it "deserializes full configuration" do
    json = %q({
      "openaiApiKey": "test-key",
      "openaiApiHost": "https://custom.api.com",
      "openaiModel": "gpt-4",
      "maxIterations": 15,
      "timeoutSeconds": 60,
      "mcpServers": {
        "filesystem": {
          "type": "http",
          "url": "http://localhost:3001/mcp",
          "headers": {"Authorization": "Bearer token123"}
        },
        "database": {
          "type": "http",
          "url": "http://localhost:3002/mcp"
        }
      }
    })

    file = Agentish::ConfigFile.from_json(json)
    file.openai_api_key.should eq("test-key")
    file.openai_api_host.should eq("https://custom.api.com")
    file.openai_model.should eq("gpt-4")
    file.max_iterations.should eq(15)
    file.timeout_seconds.should eq(60)
    file.mcp_servers.size.should eq(2)
    file.mcp_servers["filesystem"].url.should eq("http://localhost:3001/mcp")
    file.mcp_servers["filesystem"].headers.should eq({"Authorization" => "Bearer token123"})
    file.mcp_servers["database"].url.should eq("http://localhost:3002/mcp")
  end

  it "uses defaults for optional fields" do
    json = %q({"openaiApiKey": "test-key"})
    file = Agentish::ConfigFile.from_json(json)
    file.openai_api_key.should eq("test-key")
    file.openai_api_host.should eq("https://api.openai.com")
    file.openai_model.should eq("gpt-4o")
    file.max_iterations.should eq(10)
    file.timeout_seconds.should eq(120)
    file.mcp_servers.should be_empty
  end
end

describe AgentKit::Config do
  describe "#initialize" do
    it "creates config with defaults" do
      config = AgentKit::Config.new(openai_api_key: "test-key")
      config.openai_api_key.should eq("test-key")
      config.openai_api_host.should eq("https://api.openai.com")
      config.openai_model.should eq("gpt-4o")
      config.max_iterations.should eq(10)
      config.timeout_seconds.should eq(120)
    end

    it "creates config with custom values" do
      config = AgentKit::Config.new(
        openai_api_key: "my-key",
        openai_api_host: "https://custom.api.com",
        openai_model: "gpt-4o-mini",
        max_iterations: 20,
        timeout_seconds: 60
      )
      config.openai_api_key.should eq("my-key")
      config.openai_api_host.should eq("https://custom.api.com")
      config.openai_model.should eq("gpt-4o-mini")
      config.max_iterations.should eq(20)
      config.timeout_seconds.should eq(60)
    end
  end

  describe "Agentish.load_config" do
    it "loads config from JSON file" do
      temp_file = File.tempfile("config_test", ".json") do |file|
        file.print(%q({
          "openaiApiKey": "file-test-key",
          "openaiApiHost": "https://file.api.com",
          "openaiModel": "gpt-4",
          "maxIterations": 5,
          "timeoutSeconds": 30,
          "mcpServers": {
            "test": {"type": "http", "url": "http://localhost:8000/mcp"}
          }
        }))
      end

      config = Agentish.load_config(temp_file.path)

      config.openai_api_key.should eq("file-test-key")
      config.openai_api_host.should eq("https://file.api.com")
      config.openai_model.should eq("gpt-4")
      config.max_iterations.should eq(5)
      config.timeout_seconds.should eq(30)
      config.mcp_servers.size.should eq(1)
      config.mcp_servers["test"].url.should eq("http://localhost:8000/mcp")
    ensure
      temp_file.try(&.delete)
    end

    it "expands env vars in mcp config" do
      ENV["MCP_PORT"] = "8123"
      ENV.delete("MCP_TOKEN")

      temp_file = File.tempfile("config_test", ".json") do |file|
        file.print(%q({
          "openaiApiKey": "file-test-key",
          "mcpServers": {
            "http": {
              "type": "http",
              "url": "http://localhost:${MCP_PORT}/mcp",
              "headers": {"Authorization": "Bearer ${MCP_TOKEN:-default-token}"}
            },
            "stdio": {
              "command": "python",
              "args": ["-m", "server", "--port", "${MCP_PORT}"],
              "env": {"TOKEN": "${MCP_TOKEN:-default-token}"}
            }
          }
        }))
      end

      config = Agentish.load_config(temp_file.path)
      config.mcp_servers["http"].url.should eq("http://localhost:8123/mcp")
      config.mcp_servers["http"].headers.should eq({"Authorization" => "Bearer default-token"})
      config.mcp_servers["stdio"].args.should eq(["-m", "server", "--port", "8123"])
      config.mcp_servers["stdio"].env.should eq({"TOKEN" => "default-token"})
    ensure
      temp_file.try(&.delete)
      ENV.delete("MCP_PORT")
    end

    it "raises error for http mcp server config without type" do
      temp_file = File.tempfile("config_test", ".json") do |file|
        file.print(%q({
          "openaiApiKey": "file-test-key",
          "mcpServers": {"test": {"url": "http://localhost:8000/mcp"}}
        }))
      end

      expect_raises(AgentKit::ConfigError, /requires type="http"/) do
        Agentish.load_config(temp_file.path)
      end
    ensure
      temp_file.try(&.delete)
    end

    it "uses defaults for optional fields" do
      temp_file = File.tempfile("config_test", ".json") do |file|
        file.print(%q({"openaiApiKey": "minimal-key"}))
      end

      config = Agentish.load_config(temp_file.path)

      config.openai_api_key.should eq("minimal-key")
      config.openai_api_host.should eq("https://api.openai.com")
      config.openai_model.should eq("gpt-4o")
      config.max_iterations.should eq(10)
      config.timeout_seconds.should eq(120)
    ensure
      temp_file.try(&.delete)
    end

    it "raises error for non-existent file" do
      expect_raises(AgentKit::ConfigError, /Config file not found/) do
        Agentish.load_config("/non/existent/path.json")
      end
    end

    it "raises error for invalid JSON" do
      temp_file = File.tempfile("config_test", ".json") do |file|
        file.print("invalid json {{{")
      end

      expect_raises(AgentKit::ConfigError, /Invalid config file format/) do
        Agentish.load_config(temp_file.path)
      end
    ensure
      temp_file.try(&.delete)
    end
  end

  describe "#validate!" do
    it "raises error when openaiApiKey is empty" do
      config = AgentKit::Config.new(openai_api_key: "")
      expect_raises(AgentKit::ConfigError, "openaiApiKey is required") do
        config.validate!
      end
    end

    it "raises error when maxIterations is not positive" do
      config = AgentKit::Config.new(openai_api_key: "key", max_iterations: 0)
      expect_raises(AgentKit::ConfigError, "maxIterations must be positive") do
        config.validate!
      end
    end

    it "raises error when timeoutSeconds is not positive" do
      config = AgentKit::Config.new(openai_api_key: "key", timeout_seconds: -1)
      expect_raises(AgentKit::ConfigError, "timeoutSeconds must be positive") do
        config.validate!
      end
    end

    it "passes validation with valid config" do
      config = AgentKit::Config.new(openai_api_key: "valid-key")
      config.validate!
    end
  end

  describe "#valid?" do
    it "returns false for invalid config" do
      config = AgentKit::Config.new(openai_api_key: "")
      config.valid?.should be_false
    end

    it "returns true for valid config" do
      config = AgentKit::Config.new(openai_api_key: "valid-key")
      config.valid?.should be_true
    end
  end
end
