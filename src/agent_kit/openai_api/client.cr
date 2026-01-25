require "http/client"
require "json"
require "./types"

module AgentKit::OpenAIApi
  Log = AgentKit::Log.for("openai")

  class Client
    getter api_host : String
    getter api_key : String
    getter model : String
    getter timeout : Time::Span
    getter max_retries : Int32
    getter base_retry_delay : Time::Span

    DEFAULT_MAX_RETRIES = 5
    DEFAULT_BASE_DELAY  = 1.seconds
    MAX_RETRY_DELAY     = 60.seconds

    def initialize(
      @api_key : String,
      @api_host : String = "https://api.openai.com",
      @model : String = "gpt-4o",
      @timeout : Time::Span = 120.seconds,
      @max_retries : Int32 = DEFAULT_MAX_RETRIES,
      @base_retry_delay : Time::Span = DEFAULT_BASE_DELAY,
    )
    end

    def initialize(config : AgentKit::Config)
      @api_key = config.openai_api_key
      @api_host = config.openai_api_host
      @model = config.openai_model
      @timeout = config.timeout_seconds.seconds
      @max_retries = DEFAULT_MAX_RETRIES
      @base_retry_delay = DEFAULT_BASE_DELAY
    end

    def chat_completion(
      messages : Array(ChatMessage),
      tools : Array(Tool)? = nil,
      tool_choice : String? = nil,
      model : String? = nil,
    ) : ChatCompletionResponse
      request = ChatCompletionRequest.new(
        model: model || @model,
        messages: messages,
        tools: tools,
        tool_choice: tool_choice
      )

      body = request.to_json
      attempt = 0

      loop do
        attempt += 1
        response = post("/v1/chat/completions", body)

        begin
          return handle_response(response)
        rescue ex : RateLimitError
          if attempt >= @max_retries
            Log.error { "Rate limit exceeded after #{attempt} attempts, giving up" }
            raise ex
          end

          delay = calculate_retry_delay(response, attempt)
          Log.warn { "Rate limit hit (attempt #{attempt}/#{@max_retries}), retrying in #{delay.total_seconds.round(1)}s..." }
          sleep(delay)
        end
      end
    end

    private def calculate_retry_delay(response : HTTP::Client::Response, attempt : Int32) : Time::Span
      # Try Retry-After header first (standard HTTP header)
      if retry_after = response.headers["Retry-After"]?
        if seconds = retry_after.to_i?
          return Math.min(seconds.seconds, MAX_RETRY_DELAY)
        end
      end

      # Try OpenAI-specific headers
      # x-ratelimit-reset-requests: time until request limit resets (e.g., "1s", "6m0s")
      # x-ratelimit-reset-tokens: time until token limit resets
      reset_time = parse_reset_header(response.headers["x-ratelimit-reset-requests"]?) ||
                   parse_reset_header(response.headers["x-ratelimit-reset-tokens"]?)

      if reset_time
        return Math.min(reset_time, MAX_RETRY_DELAY)
      end

      # Fallback to exponential backoff: base * 2^(attempt-1) with jitter
      base_delay = @base_retry_delay.total_seconds * (2 ** (attempt - 1))
      jitter = Random.rand * 0.5 * base_delay # 0-50% jitter
      delay = (base_delay + jitter).seconds

      Math.min(delay, MAX_RETRY_DELAY)
    end

    private def parse_reset_header(value : String?) : Time::Span?
      return nil unless value

      # Parse formats like "1s", "6m0s", "1h30m", "500ms"
      total_seconds = 0.0

      # Match hours
      if match = value.match(/(\d+)h/)
        total_seconds += match[1].to_i * 3600
      end

      # Match minutes
      if match = value.match(/(\d+)m(?!s)/)
        total_seconds += match[1].to_i * 60
      end

      # Match seconds
      if match = value.match(/(\d+(?:\.\d+)?)s/)
        total_seconds += match[1].to_f
      end

      # Match milliseconds
      if match = value.match(/(\d+)ms/)
        total_seconds += match[1].to_i / 1000.0
      end

      total_seconds > 0 ? total_seconds.seconds : nil
    end

    private def post(path : String, body : String) : HTTP::Client::Response
      uri = URI.parse(@api_host)

      client = HTTP::Client.new(uri)
      client.read_timeout = @timeout
      client.connect_timeout = 30.seconds

      headers = HTTP::Headers{
        "Content-Type"  => "application/json",
        "Authorization" => "Bearer #{@api_key}",
      }

      client.post(path, headers: headers, body: body)
    ensure
      client.try(&.close)
    end

    private def handle_response(response : HTTP::Client::Response) : ChatCompletionResponse
      case response.status_code
      when 200
        ChatCompletionResponse.from_json(response.body)
      when 400
        raise BadRequestError.new(parse_error_message(response.body))
      when 401
        raise AuthenticationError.new("Invalid API key")
      when 429
        raise RateLimitError.new("Rate limit exceeded")
      when 500, 502, 503
        raise ServerError.new("OpenAI server error: #{response.status_code}")
      else
        raise APIException.new("Unexpected response: #{response.status_code} - #{response.body}")
      end
    end

    private def parse_error_message(body : String) : String
      error = APIError.from_json(body)
      error.error.message
    rescue
      body
    end
  end

  class APIException < Exception
  end

  class BadRequestError < APIException
  end

  class AuthenticationError < APIException
  end

  class RateLimitError < APIException
    getter retry_after : Time::Span?

    def initialize(message : String, @retry_after : Time::Span? = nil)
      super(message)
    end
  end

  class ServerError < APIException
  end
end
