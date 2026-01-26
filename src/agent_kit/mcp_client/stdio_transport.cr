require "json"
require "io"
require "process"
require "atomic"
require "../logger"
require "./transport"

module AgentKit::MCPClient
  class StdioTransport < Transport
    Log = AgentKit::MCPClient::Log.for("stdio_transport")

    @process : Process
    @stdin : IO
    @stdout : IO
    @stderr : IO

    @request_id : Int64 = 0
    @pending = {} of Int64 => Channel(JSON::Any)
    @pending_lock = Mutex.new
    @closed = Atomic(Bool).new(false)

    def initialize(
      command : String,
      args : Array(String) = [] of String,
      env : Hash(String, String) = {} of String => String,
      @timeout : Time::Span = 120.seconds,
    )
      @process = Process.new(
        command,
        args,
        input: Process::Redirect::Pipe,
        output: Process::Redirect::Pipe,
        error: Process::Redirect::Pipe,
        env: env
      )

      @stdin = @process.input.as(IO)
      @stdout = @process.output.as(IO)
      @stderr = @process.error.as(IO)

      spawn_stdout_reader
      spawn_stderr_reader
    end

    def connected? : Bool
      !@closed.get && @process.exists?
    rescue
      false
    end

    def close : Nil
      return if @closed.swap(true)

      @pending_lock.synchronize do
        @pending.each_value do |ch|
          begin
            ch.close
          rescue
          end
        end
        @pending.clear
      end

      begin
        @stdin.close
      rescue
      end

      begin
        @stdout.close
      rescue
      end

      begin
        @stderr.close
      rescue
      end

      begin
        @process.terminate
      rescue
      end

      begin
        @process.wait
      rescue
      end

      nil
    end

    def next_request_id : Int64
      @request_id += 1
    end

    def send_request(method : String, params : JSON::Any? = nil) : JSON::Any
      raise MCPError.new("Transport closed") if @closed.get

      request_id = next_request_id
      ch = Channel(JSON::Any).new(1)

      @pending_lock.synchronize do
        @pending[request_id] = ch
      end

      write_message({
        jsonrpc: "2.0",
        id:      request_id,
        method:  method,
        params:  params,
      }.to_json)

      begin
        result = receive_with_timeout(ch, @timeout)
        if result["__error__"]?.try(&.as_bool?) == true
          code = result["code"]?.try(&.as_i?) || -32000
          message = result["message"]?.try(&.as_s?) || "Unknown error"
          raise MCPError.new("MCP Error #{code}: #{message}")
        end

        result
      rescue ex : Channel::ClosedError
        raise MCPError.new("Transport closed")
      end
    end

    def send_notification(method : String, params : JSON::Any? = nil) : Nil
      raise MCPError.new("Transport closed") if @closed.get

      write_message({
        jsonrpc: "2.0",
        method:  method,
        params:  params,
      }.to_json)

      nil
    end

    private def write_message(json_line : String) : Nil
      Log.debug { "[MCP STDIO WRITE] #{json_line}" }
      @stdin << json_line
      @stdin << "\n"
      @stdin.flush
    end

    private def spawn_stdout_reader
      spawn do
        begin
          @stdout.each_line do |line|
            next if line.strip.empty?

            Log.debug { "[MCP STDIO READ] #{line}" }
            json = JSON.parse(line)

            if error = json["error"]?
              if id = json["id"]?
                complete_pending(id.as_i64, error: error)
              else
                Log.warn { "Received error without id: #{error.to_json}" }
              end
              next
            end

            if id = json["id"]?
              if result = json["result"]?
                complete_pending(id.as_i64, result: result)
              else
                complete_pending(id.as_i64, error: JSON.parse({code: -32000, message: "Missing result"}.to_json))
              end
            end
          end
        rescue ex
          Log.warn { "stdout reader crashed: #{ex.message}" }
        ensure
          close
        end
      end
    end

    private def spawn_stderr_reader
      spawn do
        begin
          @stderr.each_line do |line|
            Log.warn { "[MCP STDIO STDERR] #{line.strip}" }
          end
        rescue
        end
      end
    end

    private def receive_with_timeout(ch : Channel(JSON::Any), timeout : Time::Span) : JSON::Any
      select
      when value = ch.receive
        value
      when timeout(timeout)
        raise MCPError.new("Request timeout")
      end
    end

    private def complete_pending(id : Int64, result : JSON::Any? = nil, error : JSON::Any? = nil)
      ch = @pending_lock.synchronize do
        @pending.delete(id)
      end

      return unless ch

      if error
        code = error["code"]?.try(&.as_i?) || -32000
        message = error["message"]?.try(&.as_s?) || "Unknown error"
        begin
          ch.send(JSON.parse({__error__: true, code: code, message: message, data: error["data"]?}.to_json))
        ensure
          ch.close
        end
        return
      end

      if r = result
        begin
          ch.send(r)
        ensure
          ch.close
        end
      end
    end
  end
end
