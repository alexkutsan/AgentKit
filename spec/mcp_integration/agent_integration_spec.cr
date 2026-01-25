require "../spec_helper"
require "webmock"
require "../../src/agent_kit/agent_loop"
require "../../src/agent_kit/config"

# E2E tests for full Agent loop with real MCP server and OpenAI API
# Requires:
#   - MCP server running on http://localhost:8000/mcp
#   - Config file with openaiApiKey

MCP_TEST_URL_E2E = "http://localhost:8000/mcp"
TEST_CONFIG_PATH = "config/test_mcp_servers.json.disabled"

def require_openai_key : String
  if key = ENV["OPENAI_API_KEY"]?
    return key unless key.empty?
  end

  pending!("OPENAI_API_KEY not set for integration tests")
end

def create_test_config : AgentKit::Config
  if File.exists?(TEST_CONFIG_PATH)
    Agentish.load_config(TEST_CONFIG_PATH)
  else
    # Fallback for tests without config file
    api_key = require_openai_key
    api_host = ENV["OPENAI_API_HOST"]? || "https://api.openai.com"
    model = ENV["OPENAI_MODEL"]? || "gpt-4o"
    mcp_servers = {
      "test" => AgentKit::MCPServerConfig.new(type: "http", url: MCP_TEST_URL_E2E),
    }
    AgentKit::Config.new(
      openai_api_key: api_key,
      openai_api_host: api_host,
      openai_model: model,
      max_iterations: 5,
      timeout_seconds: 120,
      mcp_servers: mcp_servers
    )
  end
end

describe AgentKit::Agent, tags: "integration" do
  before_each do
    WebMock.allow_net_connect = true
  end

  describe "#setup" do
    it "connects to MCP server and registers tools" do
      config = create_test_config
      agent = AgentKit::Agent.new(config)

      agent.setup

      agent.tool_registry.size.should be > 0
      agent.mcp_manager.clients["test"].connected?.should be_true

      tool_names = agent.tool_registry.tools.keys
      tool_names.should contain("test__hello_world")
      tool_names.should contain("test__add_numbers")

      agent.cleanup
    end
  end

  describe "#run" do
    it "executes simple prompt without tool calls" do
      config = create_test_config
      agent = AgentKit::Agent.new(config)
      agent.setup

      result = agent.run("Say 'Hello World' and nothing else.")

      result.downcase.should contain("hello")

      agent.cleanup
    end

    it "executes prompt with single tool call (add_numbers)" do
      config = create_test_config
      agent = AgentKit::Agent.new(config)
      agent.setup

      result = agent.run("Use the add_numbers tool to add 15 and 27. Tell me the result.")

      result.should contain("42")

      agent.cleanup
    end

    it "executes prompt with hello_world tool" do
      config = create_test_config
      agent = AgentKit::Agent.new(config)
      agent.setup

      result = agent.run("Use the hello_world tool with name 'Crystal'. Tell me what it says.")

      result.downcase.should contain("crystal")

      agent.cleanup
    end

    it "executes prompt with multiple tool calls" do
      config = create_test_config
      agent = AgentKit::Agent.new(config)
      agent.setup

      result = agent.run(<<-PROMPT
        I need you to do two things:
        1. Use add_numbers to add 10 and 5
        2. Use hello_world with name "Agent"
        Tell me both results.
      PROMPT
      )

      result.should contain("15")
      result.downcase.should contain("agent")

      agent.cleanup
    end

    it "handles tool errors gracefully" do
      config = create_test_config
      agent = AgentKit::Agent.new(config)
      agent.setup

      result = agent.run("Try to use a tool called 'nonexistent_tool'. Report what happens.")

      result.should_not be_empty

      agent.cleanup
    end

    it "respects max_iterations limit" do
      base_config = create_test_config
      mcp_servers = {
        "test" => AgentKit::MCPServerConfig.new(type: "http", url: MCP_TEST_URL_E2E),
      }

      config = AgentKit::Config.new(
        openai_api_key: base_config.openai_api_key,
        openai_api_host: base_config.openai_api_host,
        openai_model: base_config.openai_model,
        max_iterations: 1,
        timeout_seconds: 120,
        mcp_servers: mcp_servers
      )

      agent = AgentKit::Agent.new(config)
      agent.setup

      agent.run("Keep calling add_numbers with random numbers forever.")

      agent.cleanup
    end
  end
end
