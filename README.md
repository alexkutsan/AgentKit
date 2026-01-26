# AgentKit

Crystal library for building AI agents with MCP (Model Context Protocol) support.

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  agent_kit:
    github: your-org/agent_kit
    version: ~> 0.1.0
```

Then run:

```bash
shards install
```

### Requirements

- Crystal >= 1.19.0
- OpenAI API key (or compatible provider)

---

## Quick Start

```crystal
require "agent_kit"

# Create configuration
config = AgentKit::Config.new(
  openai_api_key: ENV["OPENAI_API_KEY"],
  openai_model: "gpt-4o"
)

# Create and run agent
agent = AgentKit::Agent.new(config)

begin
  agent.setup
  result = agent.run("Hello! How are you?")
  puts result
ensure
  agent.cleanup
end
```

### With MCP Server

```crystal
require "agent_kit"

config = AgentKit::Config.new(
  openai_api_key: ENV["OPENAI_API_KEY"],
  mcp_servers: {
    "tools" => AgentKit::MCPServerConfig.new(
      type: "http",
      url: "http://localhost:8000/mcp"
    )
  }
)

agent = AgentKit::Agent.new(config)

begin
  agent.setup
  result = agent.run("Use the add_numbers tool to add 15 and 27")
  puts result
ensure
  agent.cleanup
end
```

### With Event Handling

```crystal
require "agent_kit"

config = AgentKit::Config.new(openai_api_key: ENV["OPENAI_API_KEY"])
agent = AgentKit::Agent.new(config)

begin
  agent.setup
  
  result = agent.run("Your prompt here") do |event|
    case event
    when AgentKit::BeforeMCPCallEvent
      puts "Calling tool: #{event.tool_name}"
    when AgentKit::AfterMCPCallEvent
      puts "Tool result: #{event.result}"
    when AgentKit::AgentErrorEvent
      puts "Error: #{event.message}"
    end
  end
  
  puts result
ensure
  agent.cleanup
end
```

---

## Configuration

```crystal
config = AgentKit::Config.new(
  openai_api_key: "sk-...",           # Required
  openai_api_host: "https://api.openai.com",  # Default
  openai_model: "gpt-4o",             # Default
  max_iterations: 10,                 # Default
  timeout_seconds: 120,               # Default
  mcp_servers: {} of String => AgentKit::MCPServerConfig
)

config.validate!  # Raises ConfigError if invalid
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `openai_api_key` | API key (required) | — |
| `openai_api_host` | API URL | `https://api.openai.com` |
| `openai_model` | Model | `gpt-4o` |
| `max_iterations` | Max agent iterations | `10` |
| `timeout_seconds` | Request timeout (sec) | `120` |
| `mcp_servers` | MCP servers | `{}` |

---

## MCP Servers

### HTTP Transport

```crystal
config = AgentKit::Config.new(
  openai_api_key: "sk-...",
  mcp_servers: {
    "filesystem" => AgentKit::MCPServerConfig.new(
      type: "http",
      url: "http://localhost:8000/mcp"
    ),
    "database" => AgentKit::MCPServerConfig.new(
      type: "http",
      url: "http://localhost:8001/mcp",
      headers: {"Authorization" => "Bearer token"}
    )
  }
)
```

### Stdio Transport (local process)

```crystal
config = AgentKit::Config.new(
  openai_api_key: "sk-...",
  mcp_servers: {
    "local-tools" => AgentKit::MCPServerConfig.new(
      command: "python3",
      args: ["-u", "/path/to/mcp_server.py"],
      env: {"TOKEN" => "secret"}
    )
  }
)
```

---

## Events

| Event | Description | Fields |
|-------|-------------|--------|
| `BeforeMCPCallEvent` | Before MCP tool call | `tool_name`, `arguments` |
| `AfterMCPCallEvent` | After MCP tool call | `tool_name`, `result`, `error?` |
| `BeforeLLMCallEvent` | Before LLM request | `messages`, `tools` |
| `AfterLLMCallEvent` | After LLM response | `response`, `final?` |
| `AgentCompletedEvent` | Agent finished | `result` |
| `AgentErrorEvent` | Error occurred | `error`, `message` |

Events auto-continue by default. Call `event.stop!` to halt the agent.

---

## Provider Compatibility

Compatible with any OpenAI-compatible API:

| Provider | `openai_api_host` |
|----------|-----------------|
| OpenAI | `https://api.openai.com` |
| Azure OpenAI | `https://{resource}.openai.azure.com` |
| Ollama | `http://localhost:11434` |
| OpenRouter | `https://openrouter.ai/api` |
| Together AI | `https://api.together.xyz` |

---

## Documentation

- [INTEGRATION_GUIDE.md](docs/INTEGRATION_GUIDE.md) — detailed API reference
- [DEVELOPERS_GUIDE.md](docs/DEVELOPERS_GUIDE.md) — for library contributors

---

## License

MIT
