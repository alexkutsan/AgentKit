module AgentKit::MCPClient
  struct SSEEvent
    property event : String
    property data : String
    property id : String?
    property retry : Int32?

    def initialize(
      @event : String = "message",
      @data : String = "",
      @id : String? = nil,
      @retry : Int32? = nil,
    )
    end
  end

  class SSEParser
    @buffer : String = ""
    @current_event : String = "message"
    @current_data : Array(String) = [] of String
    @current_id : String? = nil
    @current_retry : Int32? = nil

    def parse(chunk : String) : Array(SSEEvent)
      @buffer += chunk
      events = [] of SSEEvent

      while idx = @buffer.index("\n\n")
        raw_event = @buffer[0...idx]
        @buffer = @buffer[(idx + 2)..]

        if event = parse_event(raw_event)
          events << event
        end
      end

      events
    end

    def reset
      @buffer = ""
      @current_event = "message"
      @current_data.clear
      @current_id = nil
      @current_retry = nil
    end

    private def parse_event(raw : String) : SSEEvent?
      event_type = "message"
      data_lines = [] of String
      event_id : String? = nil
      retry_ms : Int32? = nil

      raw.each_line do |line|
        next if line.starts_with?(":")

        if line.includes?(":")
          field, _, value = line.partition(":")
          value = value.lstrip

          case field
          when "event"
            event_type = value
          when "data"
            data_lines << value
          when "id"
            event_id = value
          when "retry"
            retry_ms = value.to_i?
          end
        end
      end

      return nil if data_lines.empty?

      SSEEvent.new(
        event: event_type,
        data: data_lines.join("\n"),
        id: event_id,
        retry: retry_ms
      )
    end
  end
end
