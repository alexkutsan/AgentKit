require "../spec_helper"
require "../../src/agent_kit/openai_api/types"
require "../../src/agent_kit/openai_api/client"
require "../../src/agent_kit/config"
require "webmock"

TEST_CONFIG_PATH_OPENAI = "config/test_mcp_servers.json.disabled"

def get_test_config : AgentKit::Config?
  if File.exists?(TEST_CONFIG_PATH_OPENAI)
    config = Agentish.load_config(TEST_CONFIG_PATH_OPENAI)
    config.openai_api_key.empty? ? nil : config
  else
    key = ENV["OPENAI_API_KEY"]?
    return nil if key.nil? || key.empty?

    api_host = ENV["OPENAI_API_HOST"]? || "https://api.openai.com"
    model = ENV["OPENAI_MODEL"]? || "gpt-4o"
    AgentKit::Config.new(openai_api_key: key, openai_api_host: api_host, openai_model: model)
  end
rescue
  nil
end

describe "OpenAI Integration" do
  before_each do
    WebMock.allow_net_connect = true
  end

  after_each do
    WebMock.allow_net_connect = false
  end
  describe AgentKit::OpenAIApi::Client do
    it "sends real request to OpenAI API", tags: "integration" do
      config = get_test_config
      pending!("OPENAI_API_KEY not set for integration tests") unless config

      client = AgentKit::OpenAIApi::Client.new(config.as(AgentKit::Config))
      messages = [
        AgentKit::OpenAIApi::ChatMessage.system("You are a helpful assistant. Be very brief."),
        AgentKit::OpenAIApi::ChatMessage.user("Say 'Hello' and nothing else."),
      ]

      response = client.chat_completion(messages)

      response.id.should_not be_empty
      response.choices.size.should be > 0
      response.choices[0].message.role.should eq("assistant")
      response.choices[0].message.content.should_not be_nil
      response.usage.total_tokens.should be > 0
    end

    it "handles tool calling with real API", tags: "integration" do
      config = get_test_config
      pending!("OPENAI_API_KEY not set for integration tests") unless config

      client = AgentKit::OpenAIApi::Client.new(config.as(AgentKit::Config))

      params = JSON.parse(%q({
        "type": "object",
        "properties": {
          "a": {"type": "number"},
          "b": {"type": "number"}
        },
        "required": ["a", "b"]
      }))

      tools = [
        AgentKit::OpenAIApi::Tool.new(
          function: AgentKit::OpenAIApi::FunctionDef.new(
            name: "add_numbers",
            description: "Add two numbers together",
            parameters: params
          )
        ),
      ]

      messages = [
        AgentKit::OpenAIApi::ChatMessage.system("You have access to tools. Use them when appropriate."),
        AgentKit::OpenAIApi::ChatMessage.user("What is 5 + 3? Use the add_numbers tool."),
      ]

      response = client.chat_completion(messages, tools: tools, tool_choice: "required")

      response.choices[0].finish_reason.should eq("tool_calls")
      tool_calls = response.choices[0].message.tool_calls
      tool_calls.should_not be_nil
      if tc = tool_calls
        tc.size.should be > 0
        tc[0].function.name.should eq("add_numbers")
      end
    end
  end
end
