require "http/client"
require "json"
require "./sse_parser"
require "../logger"

module AgentKit::MCPClient
  abstract class Transport
    abstract def send_request(method : String, params : JSON::Any? = nil) : JSON::Any
    abstract def send_notification(method : String, params : JSON::Any? = nil) : Nil
    abstract def close : Nil
    abstract def connected? : Bool
  end

  class HttpTransport < Transport
    Log = AgentKit::MCPClient::Log.for("transport")
    getter url : String
    getter headers : Hash(String, String)
    getter timeout : Time::Span
    getter session_id : String?

    @request_id : Int64 = 0

    def initialize(
      @url : String,
      @headers : Hash(String, String) = {} of String => String,
      @timeout : Time::Span = 120.seconds,
    )
      @session_id = nil
    end

    def next_request_id : Int64
      @request_id += 1
    end

    def session_id=(value : String?)
      @session_id = value
    end

    def connected? : Bool
      !@session_id.nil?
    end

    def close : Nil
      @session_id = nil
    end

    def send_request(method : String, params : JSON::Any? = nil) : JSON::Any
      request_id = next_request_id

      body = {
        jsonrpc: "2.0",
        id:      request_id,
        method:  method,
        params:  params,
      }.to_json

      Log.debug { "[MCP REQUEST] #{method} => #{body}" }

      response = post(body)
      result = handle_response(response, request_id)

      Log.debug { "[MCP RESPONSE] #{method} => #{result.to_json}" }

      result
    end

    def send_notification(method : String, params : JSON::Any? = nil) : Nil
      body = {
        jsonrpc: "2.0",
        method:  method,
        params:  params,
      }.to_json

      Log.debug { "[MCP NOTIFICATION] #{method} => #{body}" }

      post(body)
      nil
    end

    private def post(body : String) : HTTP::Client::Response
      uri = URI.parse(@url)

      client = HTTP::Client.new(uri)
      client.read_timeout = @timeout
      client.connect_timeout = 30.seconds

      headers = build_headers

      client.post(uri.path || "/", headers: headers, body: body)
    ensure
      client.try(&.close)
    end

    private def build_headers : HTTP::Headers
      h = HTTP::Headers{
        "Content-Type" => "application/json",
        "Accept"       => "application/json, text/event-stream",
      }

      @headers.each { |k, v| h[k] = v }

      if sid = @session_id
        h["Mcp-Session-Id"] = sid
      end

      h
    end

    private def handle_response(response : HTTP::Client::Response, expected_id : Int64) : JSON::Any
      extract_session_id(response)

      case response.content_type
      when "text/event-stream"
        handle_sse_response(response.body)
      else
        handle_json_response(response.body, expected_id)
      end
    end

    private def extract_session_id(response : HTTP::Client::Response)
      if sid = response.headers["Mcp-Session-Id"]?
        @session_id = sid
      end
    end

    private def handle_json_response(body : String, expected_id : Int64) : JSON::Any
      json = JSON.parse(body)

      if error = json["error"]?
        code = error["code"].as_i
        message = error["message"].as_s
        raise MCPError.new("MCP Error #{code}: #{message}")
      end

      json["result"]
    end

    private def handle_sse_response(body : String) : JSON::Any
      parser = SSEParser.new
      events = parser.parse(body + "\n\n")

      events.each do |event|
        json = JSON.parse(event.data)

        if error = json["error"]?
          code = error["code"].as_i
          message = error["message"].as_s
          raise MCPError.new("MCP Error #{code}: #{message}")
        end

        if result = json["result"]?
          return result
        end
      end

      raise MCPError.new("No result in SSE response")
    end
  end

  class MCPError < Exception
  end
end
