require "json"

module AgentKit::OpenAIApi
  struct ChatMessage
    include JSON::Serializable

    property role : String
    property content : String?

    @[JSON::Field(key: "tool_calls")]
    property tool_calls : Array(ToolCall)?

    @[JSON::Field(key: "tool_call_id")]
    property tool_call_id : String?

    def initialize(
      @role : String,
      @content : String? = nil,
      @tool_calls : Array(ToolCall)? = nil,
      @tool_call_id : String? = nil,
    )
    end

    def self.system(content : String) : ChatMessage
      new(role: "system", content: content)
    end

    def self.user(content : String) : ChatMessage
      new(role: "user", content: content)
    end

    def self.assistant(content : String) : ChatMessage
      new(role: "assistant", content: content)
    end

    def self.assistant_with_tools(tool_calls : Array(ToolCall)) : ChatMessage
      new(role: "assistant", tool_calls: tool_calls)
    end

    def self.tool_result(tool_call_id : String, content : String) : ChatMessage
      new(role: "tool", content: content, tool_call_id: tool_call_id)
    end
  end

  struct ToolCall
    include JSON::Serializable

    property id : String
    property type : String
    property function : FunctionCall

    def initialize(@id : String, @type : String = "function", @function : FunctionCall = FunctionCall.new)
    end
  end

  struct FunctionCall
    include JSON::Serializable

    property name : String
    property arguments : String

    def initialize(@name : String = "", @arguments : String = "{}")
    end

    def parsed_arguments : JSON::Any
      JSON.parse(arguments)
    end
  end

  struct Tool
    include JSON::Serializable

    property type : String
    property function : FunctionDef

    def initialize(@type : String = "function", @function : FunctionDef = FunctionDef.new)
    end
  end

  struct FunctionDef
    include JSON::Serializable

    property name : String
    property description : String
    property parameters : JSON::Any

    def initialize(
      @name : String = "",
      @description : String = "",
      @parameters : JSON::Any = JSON::Any.new({} of String => JSON::Any),
    )
    end
  end

  struct ChatCompletionRequest
    include JSON::Serializable

    property model : String
    property messages : Array(ChatMessage)
    property tools : Array(Tool)?

    @[JSON::Field(key: "tool_choice")]
    property tool_choice : String?

    @[JSON::Field(key: "max_tokens")]
    property max_tokens : Int32?

    property temperature : Float64?

    def initialize(
      @model : String,
      @messages : Array(ChatMessage),
      @tools : Array(Tool)? = nil,
      @tool_choice : String? = nil,
      @max_tokens : Int32? = nil,
      @temperature : Float64? = nil,
    )
    end
  end

  struct ChatCompletionResponse
    include JSON::Serializable

    property id : String
    property object : String
    property created : Int64
    property model : String
    property choices : Array(Choice)
    property usage : Usage

    def initialize(
      @id : String = "",
      @object : String = "chat.completion",
      @created : Int64 = 0_i64,
      @model : String = "",
      @choices : Array(Choice) = [] of Choice,
      @usage : Usage = Usage.new,
    )
    end
  end

  struct Choice
    include JSON::Serializable

    property index : Int32
    property message : ChatMessage

    @[JSON::Field(key: "finish_reason")]
    property finish_reason : String

    def initialize(
      @index : Int32 = 0,
      @message : ChatMessage = ChatMessage.new(role: "assistant"),
      @finish_reason : String = "stop",
    )
    end
  end

  struct Usage
    include JSON::Serializable

    @[JSON::Field(key: "prompt_tokens")]
    property prompt_tokens : Int32

    @[JSON::Field(key: "completion_tokens")]
    property completion_tokens : Int32

    @[JSON::Field(key: "total_tokens")]
    property total_tokens : Int32

    def initialize(
      @prompt_tokens : Int32 = 0,
      @completion_tokens : Int32 = 0,
      @total_tokens : Int32 = 0,
    )
    end
  end

  struct APIError
    include JSON::Serializable

    property error : APIErrorDetails

    def initialize(@error : APIErrorDetails = APIErrorDetails.new)
    end
  end

  struct APIErrorDetails
    include JSON::Serializable

    property message : String
    property type : String
    property code : String?

    def initialize(@message : String = "", @type : String = "", @code : String? = nil)
    end
  end
end
