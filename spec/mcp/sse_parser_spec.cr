require "../spec_helper"
require "../../src/agent_kit/mcp_client/sse_parser"

describe AgentKit::MCPClient::SSEEvent do
  it "creates event with defaults" do
    event = AgentKit::MCPClient::SSEEvent.new
    event.event.should eq("message")
    event.data.should eq("")
    event.id.should be_nil
    event.retry.should be_nil
  end

  it "creates event with custom values" do
    event = AgentKit::MCPClient::SSEEvent.new(
      event: "custom",
      data: "payload",
      id: "123",
      retry: 5000
    )
    event.event.should eq("custom")
    event.data.should eq("payload")
    event.id.should eq("123")
    event.retry.should eq(5000)
  end
end

describe AgentKit::MCPClient::SSEParser do
  describe "#parse" do
    it "parses simple event" do
      parser = AgentKit::MCPClient::SSEParser.new
      events = parser.parse("data: hello\n\n")

      events.size.should eq(1)
      events[0].data.should eq("hello")
      events[0].event.should eq("message")
    end

    it "parses named event" do
      parser = AgentKit::MCPClient::SSEParser.new
      events = parser.parse("event: custom\ndata: payload\n\n")

      events[0].event.should eq("custom")
      events[0].data.should eq("payload")
    end

    it "handles multiline data" do
      parser = AgentKit::MCPClient::SSEParser.new
      events = parser.parse("data: line1\ndata: line2\ndata: line3\n\n")

      events[0].data.should eq("line1\nline2\nline3")
    end

    it "ignores comments" do
      parser = AgentKit::MCPClient::SSEParser.new
      events = parser.parse(": this is a comment\ndata: value\n\n")

      events.size.should eq(1)
      events[0].data.should eq("value")
    end

    it "handles chunked input" do
      parser = AgentKit::MCPClient::SSEParser.new

      events1 = parser.parse("data: hel")
      events1.should be_empty

      events2 = parser.parse("lo\n\n")
      events2.size.should eq(1)
      events2[0].data.should eq("hello")
    end

    it "parses multiple events" do
      parser = AgentKit::MCPClient::SSEParser.new
      events = parser.parse("data: first\n\ndata: second\n\n")

      events.size.should eq(2)
      events[0].data.should eq("first")
      events[1].data.should eq("second")
    end

    it "parses event with id" do
      parser = AgentKit::MCPClient::SSEParser.new
      events = parser.parse("id: 42\ndata: test\n\n")

      events[0].id.should eq("42")
      events[0].data.should eq("test")
    end

    it "parses event with retry" do
      parser = AgentKit::MCPClient::SSEParser.new
      events = parser.parse("retry: 3000\ndata: test\n\n")

      events[0].retry.should eq(3000)
    end

    it "parses JSON-RPC response in data" do
      parser = AgentKit::MCPClient::SSEParser.new
      json_data = %q({"jsonrpc":"2.0","id":1,"result":{"tools":[]}})
      events = parser.parse("event: message\ndata: #{json_data}\n\n")

      events.size.should eq(1)
      parsed = JSON.parse(events[0].data)
      parsed["jsonrpc"].as_s.should eq("2.0")
      parsed["result"]["tools"].as_a.should be_empty
    end

    it "returns empty for incomplete event" do
      parser = AgentKit::MCPClient::SSEParser.new
      events = parser.parse("data: incomplete")

      events.should be_empty
    end

    it "skips events without data" do
      parser = AgentKit::MCPClient::SSEParser.new
      events = parser.parse("event: empty\n\n")

      events.should be_empty
    end
  end

  describe "#reset" do
    it "clears buffer" do
      parser = AgentKit::MCPClient::SSEParser.new
      parser.parse("data: partial")
      parser.reset

      events = parser.parse("data: new\n\n")
      events.size.should eq(1)
      events[0].data.should eq("new")
    end
  end
end
