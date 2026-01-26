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
