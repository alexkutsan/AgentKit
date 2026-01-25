# Crystal Agent — Integration Guide

Using Crystal Agent as a library in your projects.

## Installation

### Adding to shard.yml

```yaml
dependencies:
  crystal_agent:
    github: your-org/crystal_agent
    version: ~> 0.1.0
```

```bash
shards install
```

---

## Quick Start

```crystal
require "agent_kit"

# Load configuration (you own parsing/loading; AgentKit doesn't read files)
config = AgentKit::Config.new(
  openai_api_key: ENV["OPENAI_API_KEY"],
  mcp_servers: {
    "test" => AgentKit::MCPServerConfig.new(type: "http", url: "http://localhost:8000/mcp")
  }
)

# Create and run agent
agent = AgentKit::Agent.new(config)

begin
  agent.setup
  result = agent.run("Add numbers 15 and 27")
  puts result
ensure
  agent.cleanup
end
```

### With Event Handling

```crystal
require "agent_kit"

config = AgentKit::Config.new(openai_api_key: ENV["OPENAI_API_KEY"])
agent = AgentKit::Agent.new(config, "You are a helpful assistant.")  # optional system prompt

begin
  agent.setup
  
  result = agent.run("Add numbers 15 and 27") do |event|
    case event
    when AgentKit::BeforeMCPCallEvent
      puts "Calling tool: #{event.tool_name}"
      puts "Arguments: #{event.arguments}"
    when AgentKit::AfterMCPCallEvent
      puts "Tool result: #{event.result}"
      puts "Error: #{event.error?}"
    when AgentKit::BeforeLLMCallEvent
      puts "Sending #{event.messages.size} messages to LLM"
    when AgentKit::AfterLLMCallEvent
      puts "LLM responded, final: #{event.final?}"
    when AgentKit::AgentCompletedEvent
      puts "Agent completed with result: #{event.result}"
    when AgentKit::AgentErrorEvent
      puts "Agent error: #{event.message}"
    end
    
    # Events auto-continue by default
    # Call event.stop! to halt the agent
  end
  
  puts result
ensure
  agent.cleanup
end
```

---

## Components

### Config

```crystal
# Programmatic creation
config = AgentKit::Config.new(
  openai_api_key: "sk-...",
  openai_model: "gpt-4o",
  mcp_servers: {
    "my-server" => AgentKit::MCPServerConfig.new(type: "http", url: "http://localhost:8000/mcp")
  }
)

# Validation
config.validate!  # Raises ConfigError if invalid
```

### OpenAI Client

```crystal
client = CrystalAgent::OpenAIApi::Client.new(
  api_key: "sk-...",
  api_host: "https://api.openai.com",
  model: "gpt-4o"
)

# Simple request
messages = [
  CrystalAgent::OpenAIApi::ChatMessage.system("You are a helpful assistant."),
  CrystalAgent::OpenAIApi::ChatMessage.user("Hello!")
]

response = client.chat_completion(messages: messages)
puts response.choices[0].message.content
```

#### With Tools

```crystal
tool = CrystalAgent::OpenAIApi::Tool.new(
  type: "function",
  function: CrystalAgent::OpenAIApi::FunctionDef.new(
    name: "get_weather",
    description: "Get weather for a location",
    parameters: JSON.parse(%q({
      "type": "object",
      "properties": {"location": {"type": "string"}},
      "required": ["location"]
    }))
  )
)

response = client.chat_completion(
  messages: messages,
  tools: [tool],
  tool_choice: "auto"
)

# Handle tool calls
if response.choices[0].finish_reason == "tool_calls"
  response.choices[0].message.tool_calls.try &.each do |tc|
    puts "Tool: #{tc.function.name}, Args: #{tc.function.arguments}"
  end
end
```

### MCP Client

```crystal
# Connect to MCP server
config = CrystalAgent::MCPServerConfig.new(type: "http", url: "http://localhost:8000/mcp")
client = CrystalAgent::MCPClient::Client.new("my-server", config)
client.connect

# Get list of tools
tools = client.list_tools
tools.each { |t| puts "#{t.name}: #{t.description}" }

# Call tool
result = client.call_tool("add_numbers", JSON.parse(%q({"a": 5, "b": 3})))
puts result.text_content  # "8"

# Check for error
puts "Error!" if result.error?

client.close
```

#### Stdio MCP Client

```crystal
config = CrystalAgent::MCPServerConfig.new(
  command: "python3",
  args: ["-u", "/path/to/mcp_server.py"],
  env: {"TOKEN" => "${TOKEN:-default}"}
)

client = CrystalAgent::MCPClient::Client.new("local-tools", config)
client.connect
tools = client.list_tools
client.close
```

### MCP Manager

Managing multiple MCP servers:

```crystal
manager = CrystalAgent::MCPClient::Manager.new

manager.add_server("filesystem", "http://localhost:8000/mcp")
manager.add_server("database", "http://localhost:8001/mcp", {
  "Authorization" => "Bearer token"
})

manager.add_stdio_server("local-tools", "python3", ["-u", "/path/to/mcp_server.py"], {
  "TOKEN" => "${TOKEN:-default}"
})

connected = manager.connect_all
puts "Connected: #{connected.join(", ")}"

# All tools from all servers
all_tools = manager.all_tools
all_tools.each { |info| puts info.full_name }

# Call tool (format: server__tool)
result = manager.call_tool("filesystem__read_file", JSON.parse(%q({"path": "/etc/hosts"})))

manager.close_all
```

### Tool Registry

Converting MCP tools to OpenAI format:

```crystal
registry = CrystalAgent::ToolRegistry.new

# Register tools
mcp_tools = client.list_tools
registry.register_mcp_tools("my-server", mcp_tools)

# Get in OpenAI format
openai_tools = registry.openai_tools

# Resolve name
if resolved = registry.resolve("my-server__add_numbers")
  server_name, original_name = resolved
end

# Check existence
registry.has_tool?("my-server__add_numbers")  # => true
```

### Message History

```crystal
history = CrystalAgent::MessageHistory.new

history.add_system("You are a helpful assistant.")
history.add_user("Hello!")
history.add_assistant("Hi there!")

# Tool calls
tool_calls = [
  CrystalAgent::OpenAIApi::ToolCall.new(
    id: "call_123",
    function: CrystalAgent::OpenAIApi::FunctionCall.new(
      name: "get_weather",
      arguments: %q({"location": "Moscow"})
    )
  )
]
history.add_assistant_with_tools(tool_calls)
history.add_tool_result("call_123", "Sunny, 25°C")

# Get messages
messages = history.to_messages
```

### Agent

```crystal
config = CrystalAgent::Config.from_file("config.json")

# With custom system prompt (optional)
agent = CrystalAgent::Agent.new(config, "You are a specialized assistant.")

# Or without system prompt (uses default)
agent = CrystalAgent::Agent.new(config)

begin
  agent.setup  # Connect to MCP, register tools
  
  # Simple run
  result = agent.run("Your prompt here")
  
  # Or with event handling
  result = agent.run("Your prompt here") do |event|
    # Handle events (see Events section)
  end
  
  puts result
ensure
  agent.cleanup  # Close connections
end
```

#### Continuing Conversation

```crystal
agent.setup

# First request
result1 = agent.run("Hello! My name is Alex.")
puts result1

# Continue conversation (history is preserved)
result2 = agent.run_continue("What's my name?")
puts result2  # Agent remembers the name

agent.cleanup
```

---

## Error Handling

### OpenAI

```crystal
begin
  response = client.chat_completion(messages: messages)
rescue ex : CrystalAgent::OpenAIApi::AuthenticationError
  puts "Invalid API key"
rescue ex : CrystalAgent::OpenAIApi::RateLimitError
  puts "Rate limit exceeded"
rescue ex : CrystalAgent::OpenAIApi::BadRequestError
  puts "Bad request: #{ex.message}"
rescue ex : CrystalAgent::OpenAIApi::ServerError
  puts "Server error"
end
```

### MCP

```crystal
begin
  result = client.call_tool("my_tool", args)
rescue ex : CrystalAgent::MCPClient::MCPError
  puts "MCP error: #{ex.message}"
end
```

### Config

```crystal
begin
  config = CrystalAgent::Config.from_file("config.json")
  config.validate!
rescue ex : CrystalAgent::ConfigError
  puts "Config error: #{ex.message}"
end
```

---

## Logging

When using Crystal Agent as a library, you manage logging yourself:

```crystal
# Setup log level
CrystalAgent.setup_logging(CrystalAgent::LogLevel::Debug)

# With file output
CrystalAgent.setup_logging(CrystalAgent::LogLevel::Info, "/var/log/agent.log")

# Using the logger
CrystalAgent::Log.info { "Starting agent" }
CrystalAgent::Log.debug { "Debug info" }

# Close (important to call on shutdown)
CrystalAgent.close_logging
```

> **Note**: Logging is not part of the agent configuration (`Config`).
> CLI uses environment variables `CRYSTAL_AGENT_LOG_LEVEL` and `CRYSTAL_AGENT_LOG_FILE`.
> When using as a library — call `setup_logging` yourself.

---

## Extension

### Custom Agent

```crystal
class MyAgent < CrystalAgent::Agent
  private def build_system_prompt : String
    "You are a specialized assistant. Always respond in JSON."
  end

  def run(prompt : String) : String
    result = super(prompt)
    result.upcase  # Post-processing
  end
end
```

---

## Events

The agent emits events during execution. By default, events automatically continue execution.
Call `event.stop!` to halt the agent.

### Event Types

| Event | Description | Fields |
|-------|-------------|--------|
| `BeforeMCPCallEvent` | Before MCP tool call | `tool_name`, `arguments` |
| `AfterMCPCallEvent` | After MCP tool call | `tool_name`, `result`, `error?` |
| `BeforeLLMCallEvent` | Before LLM request | `messages`, `tools` |
| `AfterLLMCallEvent` | After LLM response | `response`, `final?` |
| `AgentCompletedEvent` | Agent finished | `result` |
| `AgentErrorEvent` | Error occurred | `error`, `message` |

### Example: Logging All Events

```crystal
result = agent.run(prompt) do |event|
  case event
  when CrystalAgent::BeforeMCPCallEvent
    Log.info { "[MCP CALL] #{event.tool_name}(#{event.arguments})" }
  when CrystalAgent::AfterMCPCallEvent
    if event.error?
      Log.error { "[MCP ERROR] #{event.tool_name}: #{event.result}" }
    else
      Log.info { "[MCP RESULT] #{event.tool_name}: #{event.result}" }
    end
  when CrystalAgent::AgentCompletedEvent
    Log.info { "Agent completed" }
  when CrystalAgent::AgentErrorEvent
    Log.error { "Agent error: #{event.message}" }
  end
end
```

### Example: Stopping the Agent

```crystal
result = agent.run(prompt) do |event|
  case event
  when CrystalAgent::BeforeMCPCallEvent
    if event.tool_name.includes?("dangerous")
      puts "Blocking dangerous tool call!"
      event.stop!  # Stop the agent
    end
  end
end
```

---

## Data Types

### OpenAI

| Type | Description |
|------|-------------|
| `ChatMessage` | Message (system/user/assistant/tool) |
| `ToolCall` | Tool call from LLM |
| `FunctionCall` | Function call details |
| `Tool` | Tool definition |
| `FunctionDef` | Function definition |
| `ChatCompletionRequest` | API request |
| `ChatCompletionResponse` | API response |
| `Choice` | Response choice |
| `Usage` | Token usage |

### MCP

| Type | Description |
|------|-------------|
| `SSEEvent` | Server-Sent Events event |
| `ContentItem` | Content item |
| `CallToolResult` | Tool call result |
| `ToolInfo` | Tool with server info |

### Config

| Type | Description |
|------|-------------|
| `Config` | Main configuration |
| `MCPServerConfig` | MCP server configuration |
| `LogLevel` | Log level |

### Events

| Type | Description |
|------|-------------|
| `AgentEvent` | Base event class |
| `BeforeMCPCallEvent` | Before MCP tool call |
| `AfterMCPCallEvent` | After MCP tool call |
| `BeforeLLMCallEvent` | Before LLM request |
| `AfterLLMCallEvent` | After LLM response |
| `AgentCompletedEvent` | Agent finished |
| `AgentErrorEvent` | Error occurred |

---

## Example: Unit Test with WebMock

```crystal
require "spec"
require "webmock"
require "crystal_agent"

describe "MyApp" do
  before_each { WebMock.reset }

  it "uses OpenAI client" do
    WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
      .to_return(body: {
        id: "chatcmpl-123",
        object: "chat.completion",
        created: 1699000000,
        model: "gpt-4o",
        choices: [{
          index: 0,
          message: {role: "assistant", content: "Hello!"},
          finish_reason: "stop"
        }],
        usage: {prompt_tokens: 10, completion_tokens: 5, total_tokens: 15}
      }.to_json)

    client = CrystalAgent::OpenAIApi::Client.new(api_key: "test")
    messages = [CrystalAgent::OpenAIApi::ChatMessage.user("Hi")]
    
    response = client.chat_completion(messages: messages)
    response.choices[0].message.content.should eq("Hello!")
  end
end
```
