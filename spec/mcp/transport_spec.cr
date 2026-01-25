require "../spec_helper"
require "../../src/agent_kit/mcp_client/transport"
require "webmock"

describe AgentKit::MCPClient::HttpTransport do
  before_each do
    WebMock.reset
  end

  describe "#initialize" do
    it "creates transport with url" do
      transport = AgentKit::MCPClient::HttpTransport.new("http://localhost:8000/mcp")
      transport.url.should eq("http://localhost:8000/mcp")
      transport.session_id.should be_nil
    end

    it "creates transport with headers" do
      transport = AgentKit::MCPClient::HttpTransport.new(
        "http://localhost:8000/mcp",
        {"Authorization" => "Bearer token123"}
      )
      transport.headers["Authorization"].should eq("Bearer token123")
    end
  end

  describe "#next_request_id" do
    it "increments request id" do
      transport = AgentKit::MCPClient::HttpTransport.new("http://localhost:8000/mcp")

      transport.next_request_id.should eq(1)
      transport.next_request_id.should eq(2)
      transport.next_request_id.should eq(3)
    end
  end

  describe "#send_request" do
    it "sends JSON-RPC request and parses response" do
      WebMock.stub(:post, "http://localhost:8000/mcp")
        .to_return(
          status: 200,
          headers: {
            "Content-Type"   => "application/json",
            "Mcp-Session-Id" => "session-123",
          },
          body: {
            jsonrpc: "2.0",
            id:      1,
            result:  {
              protocolVersion: "2024-11-05",
              capabilities:    {} of String => String,
              serverInfo:      {name: "test", version: "1.0"},
            },
          }.to_json
        )

      transport = AgentKit::MCPClient::HttpTransport.new("http://localhost:8000/mcp")
      result = transport.send_request("initialize", JSON.parse({
        protocolVersion: "2024-11-05",
        capabilities:    {} of String => String,
        clientInfo:      {name: "test", version: "1.0"},
      }.to_json))

      result["protocolVersion"].as_s.should eq("2024-11-05")
      transport.session_id.should eq("session-123")
    end

    it "raises MCPError on error response" do
      WebMock.stub(:post, "http://localhost:8000/mcp")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {
            jsonrpc: "2.0",
            id:      1,
            error:   {
              code:    -32600,
              message: "Invalid Request",
            },
          }.to_json
        )

      transport = AgentKit::MCPClient::HttpTransport.new("http://localhost:8000/mcp")

      expect_raises(AgentKit::MCPClient::MCPError, "MCP Error -32600: Invalid Request") do
        transport.send_request("invalid")
      end
    end
  end

  describe "#send_notification" do
    it "sends notification without expecting response" do
      WebMock.stub(:post, "http://localhost:8000/mcp")
        .to_return(status: 202, body: "")

      transport = AgentKit::MCPClient::HttpTransport.new("http://localhost:8000/mcp")
      transport.session_id = "session-123"

      result = transport.send_notification("notifications/initialized")
      result.should be_nil
    end
  end

  describe "session management" do
    it "includes session id in subsequent requests" do
      WebMock.stub(:post, "http://localhost:8000/mcp")
        .with(headers: {"Mcp-Session-Id" => "session-abc"})
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {jsonrpc: "2.0", id: 1, result: {tools: [] of String}}.to_json
        )

      transport = AgentKit::MCPClient::HttpTransport.new("http://localhost:8000/mcp")
      transport.session_id = "session-abc"

      result = transport.send_request("tools/list")
      result["tools"].as_a.should be_empty
    end
  end

  describe "SSE responses" do
    it "parses SSE response and returns result" do
      sse_body = "data: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"tools\":[]}}\n\n"

      WebMock.stub(:post, "http://localhost:8000/mcp")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "text/event-stream"},
          body: sse_body
        )

      transport = AgentKit::MCPClient::HttpTransport.new("http://localhost:8000/mcp")
      result = transport.send_request("tools/list")

      result["tools"].as_a.should be_empty
    end

    it "raises MCPError when SSE contains error" do
      sse_body = "data: {\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32000,\"message\":\"Boom\"}}\n\n"

      WebMock.stub(:post, "http://localhost:8000/mcp")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "text/event-stream"},
          body: sse_body
        )

      transport = AgentKit::MCPClient::HttpTransport.new("http://localhost:8000/mcp")

      expect_raises(AgentKit::MCPClient::MCPError, "MCP Error -32000: Boom") do
        transport.send_request("tools/list")
      end
    end

    it "raises MCPError when SSE has no result" do
      sse_body = "data: {\"jsonrpc\":\"2.0\",\"id\":1}\n\n"

      WebMock.stub(:post, "http://localhost:8000/mcp")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "text/event-stream"},
          body: sse_body
        )

      transport = AgentKit::MCPClient::HttpTransport.new("http://localhost:8000/mcp")

      expect_raises(AgentKit::MCPClient::MCPError, "No result in SSE response") do
        transport.send_request("tools/list")
      end
    end
  end

  describe "custom headers" do
    it "includes custom headers in request" do
      WebMock.stub(:post, "http://localhost:8000/mcp")
        .with(headers: {"Authorization" => "Bearer token123", "X-Test" => "1"})
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {jsonrpc: "2.0", id: 1, result: {tools: [] of String}}.to_json
        )

      transport = AgentKit::MCPClient::HttpTransport.new(
        "http://localhost:8000/mcp",
        {"Authorization" => "Bearer token123", "X-Test" => "1"}
      )

      result = transport.send_request("tools/list")
      result["tools"].as_a.should be_empty
    end
  end
end
