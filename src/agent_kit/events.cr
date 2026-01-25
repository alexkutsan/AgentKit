require "json"
require "./openai_api/types"

module AgentKit
  # By default, events auto-continue. Call stop! to halt the agent.
  abstract class AgentEvent
    @stopped : Bool = false

    def stop!
      @stopped = true
    end

    def stopped? : Bool
      @stopped
    end

    def continue? : Bool
      !@stopped
    end
  end

  class BeforeMCPCallEvent < AgentEvent
    getter tool_name : String
    getter arguments : JSON::Any?

    def initialize(@tool_name : String, @arguments : JSON::Any?)
    end
  end

  class AfterMCPCallEvent < AgentEvent
    getter tool_name : String
    getter result : String
    getter? error : Bool

    def initialize(@tool_name : String, @result : String, @error : Bool = false)
    end
  end

  class BeforeLLMCallEvent < AgentEvent
    getter messages : Array(OpenAIApi::ChatMessage)
    getter tools : Array(OpenAIApi::Tool)?

    def initialize(@messages : Array(OpenAIApi::ChatMessage), @tools : Array(OpenAIApi::Tool)?)
    end
  end

  class AfterLLMCallEvent < AgentEvent
    getter response : OpenAIApi::ChatCompletionResponse
    getter? final : Bool

    def initialize(@response : OpenAIApi::ChatCompletionResponse, @final : Bool)
    end
  end

  # This is the final event - client must explicitly continue to keep the conversation going
  class AgentCompletedEvent < AgentEvent
    getter result : String

    def initialize(@result : String)
    end
  end

  class AgentErrorEvent < AgentEvent
    getter error : Exception
    getter message : String

    def initialize(@error : Exception)
      @message = @error.message || "Unknown error"
    end

    def initialize(message : String)
      @message = message
      @error = Exception.new(message)
    end
  end

  alias EventHandler = AgentEvent ->
end
