require "../spec_helper"
require "../../src/agent_kit/message_history"

describe AgentKit::MessageHistory do
  describe "#initialize" do
    it "creates empty history" do
      history = AgentKit::MessageHistory.new
      history.size.should eq(0)
      history.messages.should be_empty
    end
  end

  describe "#add_system" do
    it "adds system message" do
      history = AgentKit::MessageHistory.new
      history.add_system("You are helpful")

      history.size.should eq(1)
      history.messages[0].role.should eq("system")
      history.messages[0].content.should eq("You are helpful")
    end
  end

  describe "#add_user" do
    it "adds user message" do
      history = AgentKit::MessageHistory.new
      history.add_user("Hello")

      history.size.should eq(1)
      history.messages[0].role.should eq("user")
      history.messages[0].content.should eq("Hello")
    end
  end

  describe "#add_assistant" do
    it "adds assistant message" do
      history = AgentKit::MessageHistory.new
      history.add_assistant("Hi there")

      history.size.should eq(1)
      history.messages[0].role.should eq("assistant")
      history.messages[0].content.should eq("Hi there")
    end
  end

  describe "#add_assistant_with_tools" do
    it "adds assistant message with tool calls" do
      history = AgentKit::MessageHistory.new

      tool_calls = [
        AgentKit::OpenAIApi::ToolCall.new(
          id: "call_123",
          function: AgentKit::OpenAIApi::FunctionCall.new(
            name: "get_weather",
            arguments: %q({"location": "Paris"})
          )
        ),
      ]

      history.add_assistant_with_tools(tool_calls)

      history.size.should eq(1)
      history.messages[0].role.should eq("assistant")
      history.messages[0].tool_calls.should_not be_nil
      if tool_calls = history.messages[0].tool_calls
        tool_calls.size.should eq(1)
      end
    end
  end

  describe "#add_tool_result" do
    it "adds tool result message" do
      history = AgentKit::MessageHistory.new
      history.add_tool_result("call_123", "Sunny, 25°C")

      history.size.should eq(1)
      history.messages[0].role.should eq("tool")
      history.messages[0].content.should eq("Sunny, 25°C")
      history.messages[0].tool_call_id.should eq("call_123")
    end
  end

  describe "#to_messages" do
    it "returns copy of messages" do
      history = AgentKit::MessageHistory.new
      history.add_user("Test")

      messages = history.to_messages
      messages.size.should eq(1)

      messages << AgentKit::OpenAIApi::ChatMessage.user("Extra")
      history.size.should eq(1)
    end
  end

  describe "#last_message" do
    it "returns last message" do
      history = AgentKit::MessageHistory.new
      history.add_user("First")
      history.add_assistant("Second")

      last = history.last_message
      last.should_not be_nil
      if l = last
        l.content.should eq("Second")
      end
    end

    it "returns nil for empty history" do
      history = AgentKit::MessageHistory.new
      history.last_message.should be_nil
    end
  end

  describe "#clear" do
    it "removes all messages" do
      history = AgentKit::MessageHistory.new
      history.add_user("Test")
      history.add_assistant("Response")

      history.clear

      history.size.should eq(0)
      history.messages.should be_empty
    end
  end

  describe "conversation flow" do
    it "maintains message order" do
      history = AgentKit::MessageHistory.new

      history.add_system("System prompt")
      history.add_user("User question")
      history.add_assistant("Assistant response")

      history.size.should eq(3)
      history.messages[0].role.should eq("system")
      history.messages[1].role.should eq("user")
      history.messages[2].role.should eq("assistant")
    end
  end
end
