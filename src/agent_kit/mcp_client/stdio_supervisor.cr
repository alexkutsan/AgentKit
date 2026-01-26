require "random"
require "atomic"
require "../logger"
require "../config"
require "./client"

module AgentKit::MCPClient
  class ClientHolder
    property client : Client

    def initialize(@client : Client)
    end
  end

  class StdioSupervisor
    Log = AgentKit::MCPClient::Log.for("stdio_supervisor")

    enum State
      Starting
      Connected
      Failed
      Stopped
    end

    getter name : String
    getter state : State
    getter config : AgentKit::MCPServerConfig
    @holder : ClientHolder

    @stopped = Atomic(Bool).new(false)
    @restart_times = [] of Time

    @base_backoff = 200.milliseconds
    @multiplier = 2.0
    @max_backoff = 5.seconds
    @max_restarts = 5
    @restart_window = 2.minutes
    @jitter_ratio = 0.2

    def initialize(@name : String, @config : AgentKit::MCPServerConfig, @holder : ClientHolder)
      @state = State::Starting
    end

    def stop : Nil
      @stopped.set(true)
      @state = State::Stopped
      nil
    end

    def ensure_connected(timeout : Time::Span = 10.seconds) : Bool
      deadline = Time.instant + timeout

      while Time.instant < deadline
        return true if client.connected?

        if @stopped.get
          return false
        end

        if @state == State::Failed
          return false
        end

        attempt_connect_once
        sleep 50.milliseconds
      end

      client.connected?
    end

    def run
      spawn(name: "mcp-stdio-supervisor-#{@name}") do
        loop do
          break if @stopped.get

          begin
            if client.connected?
              @state = State::Connected
              sleep 200.milliseconds
              next
            end

            @state = State::Starting
            attempt_connect_once
          rescue ex
            Log.warn { "Supervisor loop error for '#{@name}': #{ex.message}" }
          ensure
            sleep 200.milliseconds
          end
        end
      end
    end

    private def client : Client
      @holder.client
    end

    private def attempt_connect_once : Nil
      return if @stopped.get

      prune_restart_times
      if @restart_times.size >= @max_restarts
        @state = State::Failed
        Log.warn { "Stdio server '#{@name}' exceeded restart limit" }
        return
      end

      backoff = compute_backoff(@restart_times.size)

      begin
        client.close
      rescue
      end

      begin
        @holder.client = Client.new(@name, @config)
        @holder.client.connect
        @restart_times << Time.utc
        @state = State::Connected
      rescue ex
        @restart_times << Time.utc
        @state = State::Starting
        Log.warn { "Failed to (re)connect stdio server '#{@name}': #{ex.message}" }
        sleep backoff
      end
    end

    private def prune_restart_times
      cutoff = Time.utc - @restart_window
      @restart_times = @restart_times.select { |t| t > cutoff }
    end

    private def compute_backoff(attempt : Int32) : Time::Span
      base = @base_backoff.total_milliseconds.to_f64 * (@multiplier ** attempt)
      capped = Math.min(base, @max_backoff.total_milliseconds.to_f64)
      jitter = (Random.rand * 2.0 - 1.0) * @jitter_ratio
      with_jitter = capped * (1.0 + jitter)
      with_jitter.round.to_i64.milliseconds
    end
  end
end
