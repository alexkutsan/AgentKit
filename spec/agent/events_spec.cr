require "../spec_helper"
require "../../src/agent_kit/events"

describe AgentKit::AgentEvent do
  describe "stop/continue behavior" do
    it "continues by default" do
      event = AgentKit::BeforeMCPCallEvent.new("test_tool", nil)

      event.stopped?.should be_false
      event.continue?.should be_true
    end

    it "stops when stop! is called" do
      event = AgentKit::BeforeMCPCallEvent.new("test_tool", nil)

      event.stop!

      event.stopped?.should be_true
      event.continue?.should be_false
    end
  end
end

describe AgentKit::BeforeMCPCallEvent do
  it "stores tool_name and arguments" do
    args = JSON.parse(%q({"a": 1, "b": 2}))
    event = AgentKit::BeforeMCPCallEvent.new("my_tool", args)

    event.tool_name.should eq("my_tool")
    event.arguments.should eq(args)
  end

  it "handles nil arguments" do
    event = AgentKit::BeforeMCPCallEvent.new("my_tool", nil)

    event.tool_name.should eq("my_tool")
    event.arguments.should be_nil
  end
end

describe AgentKit::AfterMCPCallEvent do
  it "stores tool_name, result and error status" do
    event = AgentKit::AfterMCPCallEvent.new("my_tool", "result_value", error: false)

    event.tool_name.should eq("my_tool")
    event.result.should eq("result_value")
    event.error?.should be_false
  end

  it "stores error status when is_error is true" do
    event = AgentKit::AfterMCPCallEvent.new("my_tool", "error message", error: true)

    event.error?.should be_true
  end

  it "defaults is_error to false" do
    event = AgentKit::AfterMCPCallEvent.new("my_tool", "result")

    event.error?.should be_false
  end
end

describe AgentKit::BeforeLLMCallEvent do
  it "stores messages and tools" do
    messages = [
      AgentKit::OpenAIApi::ChatMessage.user("Hello"),
    ]
    tools = [
      AgentKit::OpenAIApi::Tool.new(
        type: "function",
        function: AgentKit::OpenAIApi::FunctionDef.new(
          name: "test",
          description: "Test tool"
        )
      ),
    ]

    event = AgentKit::BeforeLLMCallEvent.new(messages, tools)

    event.messages.should eq(messages)
    event.tools.should eq(tools)
  end

  it "handles nil tools" do
    messages = [AgentKit::OpenAIApi::ChatMessage.user("Hello")]

    event = AgentKit::BeforeLLMCallEvent.new(messages, nil)

    event.messages.should eq(messages)
    event.tools.should be_nil
  end
end

describe AgentKit::AfterLLMCallEvent do
  it "stores response and is_final flag" do
    response = AgentKit::OpenAIApi::ChatCompletionResponse.from_json({
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
      usage: {prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
    }.to_json)

    event = AgentKit::AfterLLMCallEvent.new(response, final: true)

    event.response.should eq(response)
    event.final?.should be_true
  end

  it "stores is_final as false when not final" do
    response = AgentKit::OpenAIApi::ChatCompletionResponse.from_json({
      id:      "chatcmpl-test",
      object:  "chat.completion",
      created: 1699000000,
      model:   "gpt-4o",
      choices: [
        {
          index:         0,
          message:       {role: "assistant", content: nil},
          finish_reason: "tool_calls",
        },
      ],
      usage: {prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
    }.to_json)

    event = AgentKit::AfterLLMCallEvent.new(response, final: false)

    event.final?.should be_false
  end
end

describe AgentKit::AgentCompletedEvent do
  it "stores result" do
    event = AgentKit::AgentCompletedEvent.new("Final answer")

    event.result.should eq("Final answer")
  end
end

describe AgentKit::AgentErrorEvent do
  it "stores error from exception" do
    ex = Exception.new("Something went wrong")
    event = AgentKit::AgentErrorEvent.new(ex)

    event.error.should eq(ex)
    event.message.should eq("Something went wrong")
  end

  it "stores error from message string" do
    event = AgentKit::AgentErrorEvent.new("Error message")

    event.message.should eq("Error message")
    event.error.message.should eq("Error message")
  end

  it "handles exception with nil message" do
    ex = Exception.new(nil)
    event = AgentKit::AgentErrorEvent.new(ex)

    event.message.should eq("Unknown error")
  end
end
