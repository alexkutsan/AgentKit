require "json"
require "./config"
require "../logger"
require "./openai_api/types"
require "./openai_api/client"
require "./mcp_client/manager"
require "./tool_registry"
require "./message_history"
require "./events"

module AgentKit
  DEFAULT_SYSTEM_PROMPT = "You are a helpful AI assistant."

  class Agent
    Log = AgentKit::Log.for("agent")

    getter config : Config
    getter openai_client : OpenAIApi::Client
    getter mcp_manager : MCPClient::Manager
    getter tool_registry : ToolRegistry
    getter history : MessageHistory
    getter system_prompt : String?

    @event_handler : EventHandler?

    def initialize(@config : Config, @system_prompt : String? = nil)
      @openai_client = OpenAIApi::Client.new(@config)
      @mcp_manager = MCPClient::Manager.new(@config.mcp_servers)
      @tool_registry = ToolRegistry.new
      @history = MessageHistory.new
    end

    def setup
      server_names = @mcp_manager.clients.keys
      if server_names.empty?
        Log.info { "No MCP servers configured" }
      else
        Log.info { "Configured MCP servers: #{server_names.join(", ")}" }
      end

      Log.info { "Connecting to MCP servers..." }
      connected = @mcp_manager.connect_all

      if connected.empty? && !server_names.empty?
        Log.warn { "No MCP servers connected - agent will run without tools" }
      end

      Log.info { "Registering tools from connected servers..." }
      connected.each do |name|
        client = @mcp_manager.get_client(name)
        next unless client

        begin
          tools = client.list_tools
          @tool_registry.register_mcp_tools(name, tools)
          tool_names = tools.map(&.name).join(", ")
          Log.info { "Server '#{name}': #{tools.size} tools [#{tool_names}]" }
        rescue ex
          Log.warn { "Failed to list tools from '#{name}': #{ex.message}" }
        end
      end

      if @tool_registry.size > 0
        all_tool_names = @tool_registry.tools.keys.join(", ")
        Log.info { "Agent ready with #{@tool_registry.size} tools: #{all_tool_names}" }
      else
        Log.info { "Agent ready without tools" }
      end
    end

    def run(prompt : String, &block : EventHandler) : String
      @event_handler = block
      @history.add_system(build_system_prompt)
      @history.add_user(prompt)

      run_agent_loop
    end

    def run(prompt : String) : String
      run(prompt) { }
    end

    def run_continue(prompt : String, &block : EventHandler) : String
      @event_handler = block
      @history.add_user(prompt)

      run_agent_loop
    end

    def run_continue(prompt : String) : String
      run_continue(prompt) { }
    end

    private def run_agent_loop : String
      Log.info { "Starting agent loop..." }

      iteration = 0
      max_iterations = @config.max_iterations
      while iteration < max_iterations
        iteration += 1
        Log.debug { "Iteration #{iteration}" }

        response = call_llm
        return "" if response.nil?

        choice = response.choices[0]
        message = choice.message
        finish_reason = choice.finish_reason

        case finish_reason
        when "stop"
          Log.info { "Agent completed (stop)" }
          result = message.content || ""
          @history.add_assistant(result)
          emit_completed(result)
          return result
        when "tool_calls"
          return "" unless handle_tool_calls(message)
        else
          Log.warn { "Unknown finish_reason: #{finish_reason}" }
          result = message.content || ""
          @history.add_assistant(result)
          emit_completed(result)
          return result
        end
      end

      Log.error { "Max iterations reached" }
      error_msg = "Error: Maximum iterations (#{max_iterations}) reached"
      emit_event(AgentErrorEvent.new(error_msg))
      error_msg
    end

    def cleanup
      Log.info { "Closing MCP connections..." }
      @mcp_manager.close_all
    end

    private def build_system_prompt : String
      base_prompt = @system_prompt || DEFAULT_SYSTEM_PROMPT

      return base_prompt if @tool_registry.size == 0

      tool_descriptions = @tool_registry.tools.values.map do |t|
        "- #{t.full_name}: #{t.openai_tool.function.description}"
      end.join("\n")

      <<-PROMPT
      #{base_prompt}

      You have access to the following tools:
      #{tool_descriptions}

      Use tools when needed to complete the user's request.
      Always provide a final response after using tools.
      PROMPT
    end

    private def call_llm : OpenAIApi::ChatCompletionResponse?
      tools = @tool_registry.openai_tools
      tool_choice = tools.empty? ? nil : "auto"
      messages = @history.to_messages

      before_event = BeforeLLMCallEvent.new(messages, tools.empty? ? nil : tools)
      emit_event(before_event)
      return nil if before_event.stopped?

      Log.debug { "[LLM REQUEST] messages: #{messages.to_json}" }
      Log.debug { "[LLM REQUEST] tools: #{tools.to_json}" } unless tools.empty?

      response = @openai_client.chat_completion(
        messages: messages,
        tools: tools.empty? ? nil : tools,
        tool_choice: tool_choice
      )

      Log.debug { "[LLM RESPONSE] #{response.to_json}" }

      final = response.choices[0]?.try(&.finish_reason) == "stop"
      after_event = AfterLLMCallEvent.new(response, final)
      emit_event(after_event)
      return nil if after_event.stopped?

      response
    end

    private def handle_tool_calls(message : OpenAIApi::ChatMessage) : Bool
      tool_calls = message.tool_calls
      return true unless tool_calls

      @history.add_assistant_with_tools(tool_calls)

      tool_calls.each do |tool_call|
        result = execute_tool(tool_call)
        return false if result.nil?
        @history.add_tool_result(tool_call.id, result)
      end
      true
    end

    private def execute_tool(tool_call : OpenAIApi::ToolCall) : String?
      tool_name = tool_call.function.name
      arguments = tool_call.function.parsed_arguments

      before_event = BeforeMCPCallEvent.new(tool_name, arguments)
      emit_event(before_event)
      return nil if before_event.stopped?

      resolved = @tool_registry.resolve(tool_name)
      unless resolved
        error_msg = "Unknown tool: #{tool_name}"
        Log.error { error_msg }
        result = JSON.build { |json| json.object { json.field "error", error_msg } }
        emit_event(AfterMCPCallEvent.new(tool_name, result, error: true))
        return result
      end

      server_name, original_name = resolved

      begin
        result = @mcp_manager.call_tool("#{server_name}__#{original_name}", arguments)
        result_str = format_tool_result(result)

        after_event = AfterMCPCallEvent.new(tool_name, result_str, error: result.error?)
        emit_event(after_event)
        return nil if after_event.stopped?

        result_str
      rescue ex : MCPClient::MCPError
        error_msg = "Tool error: #{ex.message}"
        Log.error { error_msg }
        result = JSON.build { |json| json.object { json.field "error", error_msg } }
        emit_event(AfterMCPCallEvent.new(tool_name, result, error: true))
        result
      end
    end

    private def format_tool_result(result : MCPClient::CallToolResult) : String
      if result.error?
        JSON.build { |json| json.object { json.field "error", result.text_content } }
      else
        result.text_content
      end
    end

    private def emit_event(event : AgentEvent)
      @event_handler.try &.call(event)
    end

    private def emit_completed(result : String)
      emit_event(AgentCompletedEvent.new(result))
    end
  end
end
