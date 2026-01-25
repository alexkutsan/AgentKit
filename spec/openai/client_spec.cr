require "../spec_helper"
require "../../src/agent_kit/openai_api/types"
require "../../src/agent_kit/openai_api/client"
require "webmock"

describe AgentKit::OpenAIApi::Client do
  describe "#initialize" do
    it "creates client with direct parameters" do
      client = AgentKit::OpenAIApi::Client.new(
        api_key: "test-key",
        api_host: "https://custom.api.com",
        model: "gpt-4"
      )

      client.api_key.should eq("test-key")
      client.api_host.should eq("https://custom.api.com")
      client.model.should eq("gpt-4")
    end

    it "creates client from config" do
      config = AgentKit::Config.new(
        openai_api_key: "config-key",
        openai_api_host: "https://config.api.com",
        openai_model: "gpt-4o-mini"
      )

      client = AgentKit::OpenAIApi::Client.new(config)

      client.api_key.should eq("config-key")
      client.api_host.should eq("https://config.api.com")
      client.model.should eq("gpt-4o-mini")
    end
  end

  describe "#chat_completion" do
    before_each do
      WebMock.reset
    end

    it "sends request and parses response" do
      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {
            id:      "chatcmpl-test",
            object:  "chat.completion",
            created: 1699000000,
            model:   "gpt-4o",
            choices: [
              {
                index:         0,
                message:       {role: "assistant", content: "Hello!"},
                finish_reason: "stop",
              },
            ],
            usage: {
              prompt_tokens:     10,
              completion_tokens: 5,
              total_tokens:      15,
            },
          }.to_json
        )

      client = AgentKit::OpenAIApi::Client.new(api_key: "test-key")
      messages = [AgentKit::OpenAIApi::ChatMessage.user("Hi")]

      response = client.chat_completion(messages)

      response.id.should eq("chatcmpl-test")
      response.choices[0].message.content.should eq("Hello!")
      response.choices[0].finish_reason.should eq("stop")
    end

    it "handles tool_calls response" do
      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {
            id:      "chatcmpl-tools",
            object:  "chat.completion",
            created: 1699000000,
            model:   "gpt-4o",
            choices: [
              {
                index:   0,
                message: {
                  role:       "assistant",
                  content:    nil,
                  tool_calls: [
                    {
                      id:       "call_abc",
                      type:     "function",
                      function: {
                        name:      "get_weather",
                        arguments: "{\"location\": \"Paris\"}",
                      },
                    },
                  ],
                },
                finish_reason: "tool_calls",
              },
            ],
            usage: {
              prompt_tokens:     20,
              completion_tokens: 10,
              total_tokens:      30,
            },
          }.to_json
        )

      client = AgentKit::OpenAIApi::Client.new(api_key: "test-key")
      messages = [AgentKit::OpenAIApi::ChatMessage.user("Weather?")]

      response = client.chat_completion(messages)

      response.choices[0].finish_reason.should eq("tool_calls")
      if tool_calls = response.choices[0].message.tool_calls
        tool_calls.size.should eq(1)
        tool_calls[0].function.name.should eq("get_weather")
      end
    end

    it "raises AuthenticationError on 401" do
      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(status: 401, body: "Unauthorized")

      client = AgentKit::OpenAIApi::Client.new(api_key: "bad-key")
      messages = [AgentKit::OpenAIApi::ChatMessage.user("Hi")]

      expect_raises(AgentKit::OpenAIApi::AuthenticationError) do
        client.chat_completion(messages)
      end
    end

    it "raises RateLimitError on 429 after max retries" do
      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(status: 429, body: "Rate limited")

      client = AgentKit::OpenAIApi::Client.new(
        api_key: "test-key",
        max_retries: 1 # Fail immediately without retry
      )
      messages = [AgentKit::OpenAIApi::ChatMessage.user("Hi")]

      expect_raises(AgentKit::OpenAIApi::RateLimitError) do
        client.chat_completion(messages)
      end
    end

    it "retries on 429 and succeeds" do
      call_count = 0
      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return do |_|
          call_count += 1
          if call_count < 2
            HTTP::Client::Response.new(
              status: :too_many_requests,
              body: "Rate limited",
              headers: HTTP::Headers{"Retry-After" => "0"}
            )
          else
            HTTP::Client::Response.new(
              status: :ok,
              headers: HTTP::Headers{"Content-Type" => "application/json"},
              body: {
                id:      "chatcmpl-retry",
                object:  "chat.completion",
                created: 1699000000,
                model:   "gpt-4o",
                choices: [{index: 0, message: {role: "assistant", content: "Success after retry!"}, finish_reason: "stop"}],
                usage:   {prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
              }.to_json
            )
          end
        end

      client = AgentKit::OpenAIApi::Client.new(
        api_key: "test-key",
        max_retries: 3,
        base_retry_delay: 0.001.seconds # Very short delay for tests
      )
      messages = [AgentKit::OpenAIApi::ChatMessage.user("Hi")]

      response = client.chat_completion(messages)

      call_count.should eq(2)
      response.choices[0].message.content.should eq("Success after retry!")
    end

    it "respects Retry-After header" do
      call_count = 0
      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return do |_|
          call_count += 1
          if call_count < 2
            HTTP::Client::Response.new(
              status: :too_many_requests,
              body: "Rate limited",
              headers: HTTP::Headers{"Retry-After" => "0"} # 0 seconds for fast test
            )
          else
            HTTP::Client::Response.new(
              status: :ok,
              headers: HTTP::Headers{"Content-Type" => "application/json"},
              body: {
                id:      "chatcmpl-header",
                object:  "chat.completion",
                created: 1699000000,
                model:   "gpt-4o",
                choices: [{index: 0, message: {role: "assistant", content: "OK"}, finish_reason: "stop"}],
                usage:   {prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
              }.to_json
            )
          end
        end

      client = AgentKit::OpenAIApi::Client.new(
        api_key: "test-key",
        max_retries: 3,
        base_retry_delay: 10.seconds # Long base delay, but Retry-After: 0 should override
      )
      messages = [AgentKit::OpenAIApi::ChatMessage.user("Hi")]

      response = client.chat_completion(messages)

      call_count.should eq(2)
      response.id.should eq("chatcmpl-header")
    end

    it "raises ServerError on 500" do
      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(status: 500, body: "Internal error")

      client = AgentKit::OpenAIApi::Client.new(api_key: "test-key")
      messages = [AgentKit::OpenAIApi::ChatMessage.user("Hi")]

      expect_raises(AgentKit::OpenAIApi::ServerError) do
        client.chat_completion(messages)
      end
    end

    it "raises BadRequestError on 400 with error message" do
      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(
          status: 400,
          body: {
            error: {
              message: "Invalid model specified",
              type:    "invalid_request_error",
            },
          }.to_json
        )

      client = AgentKit::OpenAIApi::Client.new(api_key: "test-key")
      messages = [AgentKit::OpenAIApi::ChatMessage.user("Hi")]

      expect_raises(AgentKit::OpenAIApi::BadRequestError, "Invalid model specified") do
        client.chat_completion(messages)
      end
    end
  end
end
