require "option_parser"
require "log"
require "./agent_kit"
require "./agentish/config_loader"

module Agentish
  # Parse log severity from string - CLI responsibility
  def self.parse_log_severity(value : String) : ::Log::Severity
    case value.downcase
    when "debug" then ::Log::Severity::Debug
    when "info"  then ::Log::Severity::Info
    when "warn"  then ::Log::Severity::Warn
    when "error" then ::Log::Severity::Error
    else              ::Log::Severity::Info
    end
  end

  # Logger for CLI application
  Log = ::Log.for("agentish")

  # Log file handle (kept open for the lifetime of the application)
  @@log_file_io : File? = nil

  # Setup logging with specified severity level and optional file
  # Uses DispatchMode::Sync for file logging to avoid async issues on close
  def self.setup_logging(level : ::Log::Severity = ::Log::Severity::Info, log_file : String? = nil)
    backend = if file_path = log_file
                file_io = File.open(file_path, "a")
                @@log_file_io = file_io
                # Use Sync dispatch mode for file to avoid "Closed stream" errors
                ::Log::IOBackend.new(io: file_io, dispatcher: ::Log::DispatchMode::Sync)
              else
                ::Log::IOBackend.new(io: STDERR)
              end

    ::Log.setup do |c|
      c.bind("agentish.*", level, backend)
      c.bind("agentish", level, backend)
    end
  end

  # Close logging and flush any open file handles
  def self.close_logging
    if file = @@log_file_io
      file.flush rescue nil
      file.close rescue nil
      @@log_file_io = nil
    end
  end

  class CLI
    DEFAULT_CONFIG_PATHS = [
      "~/.config/agentish/config.json",
      "~/.agentish.json",
      "~/Library/Application Support/Claude/claude_desktop_config.json",
    ]
    property prompt : String?
    property prompt_file : String?
    property output_file : String?
    property config_file : String?
    property? interactive : Bool

    def initialize
      @prompt = nil
      @prompt_file = nil
      @output_file = nil
      @config_file = nil
      @interactive = false
    end

    def parse_args(args : Array(String))
      remaining_args = [] of String

      OptionParser.parse(args) do |parser|
        parser.banner = "Usage: agentish [options] [prompt_file]\n\n" \
                        "Arguments:\n" \
                        "  prompt_file    Path to prompt file (alternative to -p)\n\n" \
                        "Options:"

        parser.on("-p PROMPT", "--prompt PROMPT", "Prompt text (inline)") do |text|
          @prompt = text
        end

        parser.on("-o FILE", "--output FILE", "Output file (default: stdout)") do |file|
          @output_file = file
        end

        parser.on("-c FILE", "--config FILE", "Config file (default: auto-detect)") do |file|
          @config_file = file
        end

        parser.on("-i", "--interactive", "Interactive mode (REPL)") do
          @interactive = true
        end

        parser.on("-h", "--help", "Show this help") do
          puts parser
          puts "\nConfig file locations (checked in order):"
          DEFAULT_CONFIG_PATHS.each { |p| puts "  - #{p}" }
          exit
        end

        parser.on("-v", "--version", "Show version") do
          puts "agentish v#{AgentKit::VERSION}"
          exit
        end

        parser.unknown_args do |positional, _|
          remaining_args = positional
        end
      end

      if remaining_args.size > 0 && @prompt_file.nil? && @prompt.nil?
        @prompt_file = remaining_args[0]
      end
    end

    def find_default_config : String?
      DEFAULT_CONFIG_PATHS.each do |path|
        expanded = Path[path].expand(home: true).to_s
        return expanded if File.exists?(expanded)
      end
      nil
    end

    def validate!
      if @config_file.nil?
        @config_file = find_default_config
      end

      unless @config_file
        STDERR.puts "Error: No config file found"
        STDERR.puts "Searched locations:"
        DEFAULT_CONFIG_PATHS.each { |p| STDERR.puts "  - #{p}" }
        STDERR.puts "Use --config to specify a config file"
        exit 1
      end

      if cf = @config_file
        unless File.exists?(cf)
          STDERR.puts "Error: Config file not found: #{cf}"
          exit 1
        end
      end

      if !interactive? && @prompt.nil? && @prompt_file.nil?
        STDERR.puts "Error: No prompt provided"
        STDERR.puts "Use: agentish <prompt_file>"
        STDERR.puts "  or: agentish -p \"your prompt\""
        STDERR.puts "  or: agentish -i (interactive mode)"
        exit 1
      end

      if pf = @prompt_file
        unless File.exists?(pf)
          STDERR.puts "Error: Prompt file not found: #{pf}"
          exit 1
        end
      end
    end

    def prompt_text : String
      if p = @prompt
        p
      elsif pf = @prompt_file
        File.read(pf)
      else
        raise "No prompt source"
      end
    end

    def run
      validate!

      config = Agentish.load_config(@config_file.as(String))

      log_level = Agentish.parse_log_severity(ENV["AGENTISH_LOG_LEVEL"]? || "warn")
      log_file = ENV["AGENTISH_LOG_FILE"]?
      Agentish.setup_logging(log_level, log_file)

      Log.info { "Agentish v#{AgentKit::VERSION}" }
      Log.debug { "Using config: #{@config_file}" }

      if interactive?
        run_interactive(config)
      else
        run_single(config)
      end
    end

    private def run_single(config : AgentKit::Config)
      prompt = prompt_text
      Log.debug { "Prompt: #{prompt[0, [100, prompt.size].min]}..." }

      agent = AgentKit::Agent.new(config)

      begin
        agent.setup
        result = agent.run(prompt) do |event|
          handle_event(event)
        end

        if output = @output_file
          File.write(output, result)
          Log.info { "Output written to #{output}" }
        else
          puts result
        end
      rescue ex
        Log.error { "Agent error: #{ex.message}" }
        STDERR.puts "Error: #{ex.message}"
        exit 1
      ensure
        agent.cleanup
        Agentish.close_logging
      end
    end

    private def run_interactive(config : AgentKit::Config)
      agent = AgentKit::Agent.new(config)

      begin
        agent.setup

        print_mcp_servers(agent)

        puts "\nAgentish v#{AgentKit::VERSION} - Interactive Mode"
        puts "Type your prompts below. Press Ctrl-C to exit.\n"

        Signal::INT.trap do
          puts "\n\nExiting..."
          agent.cleanup
          Agentish.close_logging
          exit 0
        end

        loop do
          print "\n> "
          STDOUT.flush

          input = gets
          break if input.nil? # EOF

          prompt = input.strip
          next if prompt.empty?

          begin
            result = agent.run_continue(prompt) do |event|
              handle_event(event)
            end
            puts "\n#{result}"
          rescue ex
            STDERR.puts "Error: #{ex.message}"
            Log.error { "Agent error: #{ex.message}" }
          end
        end
      rescue ex
        Log.error { "Agent error: #{ex.message}" }
        STDERR.puts "Error: #{ex.message}"
        exit 1
      ensure
        agent.cleanup
        Agentish.close_logging
      end
    end

    private def print_mcp_servers(agent : AgentKit::Agent)
      clients = agent.mcp_manager.clients

      if clients.empty?
        puts "No MCP servers configured."
        return
      end

      clients.each do |name, client|
        if client.connected?
          tools_count = agent.tool_registry.tools.values.count { |t| t.server_name == name }
          puts "  [✓] #{name} (#{tools_count} tools)"
        else
          puts "  [✗] #{name} (not connected)"
        end
      end
    end

    private def handle_event(event : AgentKit::AgentEvent)
      case event
      when AgentKit::BeforeMCPCallEvent
        args_str = event.arguments ? event.arguments.to_json : "{}"
        puts "[MCP CALL] #{event.tool_name}(#{args_str})"
      when AgentKit::AfterMCPCallEvent
        if event.error?
          puts "[MCP ERROR] #{event.tool_name} => #{event.result}"
        else
          puts "[MCP RESULT] #{event.tool_name} => #{event.result}"
        end
      when AgentKit::AgentErrorEvent
        STDERR.puts "[AGENT ERROR] #{event.message}"
      end
    end
  end
end

{% unless flag?(:spec) %}
  cli = Agentish::CLI.new
  cli.parse_args(ARGV)
  cli.run
{% end %}
