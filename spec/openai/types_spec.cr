require "../spec_helper"
require "../../src/agent_kit/openai_api/types"

describe AgentKit::OpenAIApi::ChatMessage do
  describe ".system" do
    it "creates system message" do
      msg = AgentKit::OpenAIApi::ChatMessage.system("You are helpful")
      msg.role.should eq("system")
      msg.content.should eq("You are helpful")
    end
  end

  describe ".user" do
    it "creates user message" do
      msg = AgentKit::OpenAIApi::ChatMessage.user("Hello")
      msg.role.should eq("user")
      msg.content.should eq("Hello")
    end
  end

  describe ".assistant" do
    it "creates assistant message" do
      msg = AgentKit::OpenAIApi::ChatMessage.assistant("Hi there")
      msg.role.should eq("assistant")
      msg.content.should eq("Hi there")
    end
  end

  describe ".tool_result" do
    it "creates tool result message" do
      msg = AgentKit::OpenAIApi::ChatMessage.tool_result("call_123", "result data")
      msg.role.should eq("tool")
      msg.content.should eq("result data")
      msg.tool_call_id.should eq("call_123")
    end
  end

  describe "JSON serialization" do
    it "serializes simple message" do
      msg = AgentKit::OpenAIApi::ChatMessage.user("Hello")
      json = msg.to_json
      parsed = JSON.parse(json)

      parsed["role"].as_s.should eq("user")
      parsed["content"].as_s.should eq("Hello")
    end

    it "deserializes message with tool_calls" do
      json = %q({
        "role": "assistant",
        "content": null,
        "tool_calls": [
          {
            "id": "call_abc123",
            "type": "function",
            "function": {
              "name": "get_weather",
              "arguments": "{\"location\": \"Paris\"}"
            }
          }
        ]
      })

      msg = AgentKit::OpenAIApi::ChatMessage.from_json(json)
      msg.role.should eq("assistant")
      msg.content.should be_nil
      msg.tool_calls.should_not be_nil
      if tool_calls = msg.tool_calls
        tool_calls.size.should eq(1)
        tool_calls[0].id.should eq("call_abc123")
        tool_calls[0].function.name.should eq("get_weather")
      end
    end
  end
end

describe AgentKit::OpenAIApi::ToolCall do
  it "deserializes from JSON" do
    json = %q({
      "id": "call_xyz",
      "type": "function",
      "function": {
        "name": "add_numbers",
        "arguments": "{\"a\": 5, \"b\": 3}"
      }
    })

    tc = AgentKit::OpenAIApi::ToolCall.from_json(json)
    tc.id.should eq("call_xyz")
    tc.type.should eq("function")
    tc.function.name.should eq("add_numbers")
    tc.function.arguments.should eq("{\"a\": 5, \"b\": 3}")
  end
end

describe AgentKit::OpenAIApi::FunctionCall do
  describe "#parsed_arguments" do
    it "parses JSON arguments" do
      fc = AgentKit::OpenAIApi::FunctionCall.new(
        name: "test",
        arguments: %q({"key": "value", "num": 42})
      )

      args = fc.parsed_arguments
      args["key"].as_s.should eq("value")
      args["num"].as_i.should eq(42)
    end
  end
end

describe AgentKit::OpenAIApi::Tool do
  it "serializes to OpenAI format" do
    params = JSON.parse(%q({
      "type": "object",
      "properties": {
        "location": {"type": "string"}
      },
      "required": ["location"]
    }))

    tool = AgentKit::OpenAIApi::Tool.new(
      type: "function",
      function: AgentKit::OpenAIApi::FunctionDef.new(
        name: "get_weather",
        description: "Get weather for location",
        parameters: params
      )
    )

    json = JSON.parse(tool.to_json)
    json["type"].as_s.should eq("function")
    json["function"]["name"].as_s.should eq("get_weather")
    json["function"]["description"].as_s.should eq("Get weather for location")
    json["function"]["parameters"]["type"].as_s.should eq("object")
  end
end

describe AgentKit::OpenAIApi::ChatCompletionRequest do
  it "serializes request with tools" do
    messages = [
      AgentKit::OpenAIApi::ChatMessage.system("You are helpful"),
      AgentKit::OpenAIApi::ChatMessage.user("Hello"),
    ]

    request = AgentKit::OpenAIApi::ChatCompletionRequest.new(
      model: "gpt-4o",
      messages: messages,
      tool_choice: "auto"
    )

    json = JSON.parse(request.to_json)
    json["model"].as_s.should eq("gpt-4o")
    json["messages"].as_a.size.should eq(2)
    json["tool_choice"].as_s.should eq("auto")
  end
end

describe AgentKit::OpenAIApi::ChatCompletionResponse do
  it "deserializes response with text content" do
    json = %q({
      "id": "chatcmpl-abc123",
      "object": "chat.completion",
      "created": 1699000000,
      "model": "gpt-4o",
      "choices": [
        {
          "index": 0,
          "message": {
            "role": "assistant",
            "content": "Hello! How can I help?"
          },
          "finish_reason": "stop"
        }
      ],
      "usage": {
        "prompt_tokens": 50,
        "completion_tokens": 10,
        "total_tokens": 60
      }
    })

    response = AgentKit::OpenAIApi::ChatCompletionResponse.from_json(json)
    response.id.should eq("chatcmpl-abc123")
    response.model.should eq("gpt-4o")
    response.choices.size.should eq(1)
    response.choices[0].finish_reason.should eq("stop")
    response.choices[0].message.content.should eq("Hello! How can I help?")
    response.usage.total_tokens.should eq(60)
  end

  it "deserializes response with tool_calls" do
    json = %q({
      "id": "chatcmpl-xyz",
      "object": "chat.completion",
      "created": 1699000000,
      "model": "gpt-4o",
      "choices": [
        {
          "index": 0,
          "message": {
            "role": "assistant",
            "content": null,
            "tool_calls": [
              {
                "id": "call_123",
                "type": "function",
                "function": {
                  "name": "get_weather",
                  "arguments": "{\"location\": \"Paris\"}"
                }
              }
            ]
          },
          "finish_reason": "tool_calls"
        }
      ],
      "usage": {
        "prompt_tokens": 100,
        "completion_tokens": 50,
        "total_tokens": 150
      }
    })

    response = AgentKit::OpenAIApi::ChatCompletionResponse.from_json(json)
    response.choices[0].finish_reason.should eq("tool_calls")
    response.choices[0].message.tool_calls.should_not be_nil

    if tool_calls = response.choices[0].message.tool_calls
      tool_calls.size.should eq(1)
      tool_calls[0].function.name.should eq("get_weather")
    end
  end
end
