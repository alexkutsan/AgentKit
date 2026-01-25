require "./openai_api/types"

module AgentKit
  class MessageHistory
    getter messages : Array(OpenAIApi::ChatMessage)

    def initialize
      @messages = [] of OpenAIApi::ChatMessage
    end

    def add_system(content : String)
      @messages << OpenAIApi::ChatMessage.system(content)
    end

    def add_user(content : String)
      @messages << OpenAIApi::ChatMessage.user(content)
    end

    def add_assistant(content : String)
      @messages << OpenAIApi::ChatMessage.assistant(content)
    end

    def add_assistant_with_tools(tool_calls : Array(OpenAIApi::ToolCall))
      @messages << OpenAIApi::ChatMessage.assistant_with_tools(tool_calls)
    end

    def add_tool_result(tool_call_id : String, content : String)
      @messages << OpenAIApi::ChatMessage.tool_result(tool_call_id, content)
    end

    def to_messages : Array(OpenAIApi::ChatMessage)
      @messages.dup
    end

    def size : Int32
      @messages.size
    end

    def clear
      @messages.clear
    end

    def last_message : OpenAIApi::ChatMessage?
      @messages.last?
    end
  end
end
