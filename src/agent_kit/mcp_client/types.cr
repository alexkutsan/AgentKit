require "json"

module AgentKit::MCPClient
  # Content item in tool result (can be text, image, etc.)
  class ContentItem
    include JSON::Serializable

    getter type : String
    getter text : String?

    def initialize(@type : String, @text : String? = nil)
    end

    def to_s : String
      text || ""
    end
  end

  class CallToolResult
    include JSON::Serializable

    getter content : Array(ContentItem)?
    @[JSON::Field(key: "isError")]
    getter is_error : Bool?
    @[JSON::Field(key: "structuredContent")]
    getter structured_content : JSON::Any?

    def initialize(@content : Array(ContentItem)? = nil, @is_error : Bool? = nil, @structured_content : JSON::Any? = nil)
    end

    def error? : Bool
      is_error == true
    end

    def text_content : String
      # Prefer structuredContent if available, fall back to content array
      if sc = structured_content
        sc.to_json
      elsif c = content
        c.map(&.to_s).join("\n")
      else
        ""
      end
    end
  end
end
