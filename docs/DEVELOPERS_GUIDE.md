# AgentKit — Developer Guide

Documentation for contributors and developers working on the library.

## Architecture

```
src/
├── agent_kit.cr          # Library entry point
├── logger.cr             # Logging
├── agent_kit/
│   ├── config.cr         # Configuration
│   ├── events.cr         # Agent events
│   ├── agent_loop.cr     # Agent main class
│   ├── tool_registry.cr  # Tool registry
│   ├── message_history.cr # Message history
│   ├── openai_api/       # OpenAI API client
│   │   ├── client.cr     # HTTP client
│   │   └── types.cr      # Data types
│   └── mcp_client/       # MCP client
│       ├── client.cr     # Single server client
│       ├── manager.cr    # Server management
│       ├── transport.cr  # Transport interface + HTTP transport
│       ├── sse_parser.cr # SSE parser
│       └── types.cr      # Data types
```

---

## Main Components

### Config (`src/agent_kit/config.cr`)

Configuration management.

- **`Config`** — main configuration class
- **`MCPServerConfig`** — MCP server configuration:
  - http: `type: "http"`, `url`, `headers`
  - stdio: `command`, `args`, `env`
- **`LogLevel`** — log level enum
- **`ConfigError`** — configuration error exception

### OpenAI (`src/agent_kit/openai_api/`)

Client for OpenAI-compatible API.

- **`Client`** — HTTP client with `chat_completion` method
- **`ChatMessage`** — message in conversation (system/user/assistant/tool)
- **`Tool`**, **`FunctionDef`** — tool definition for API
- **`ToolCall`**, **`FunctionCall`** — tool call from LLM
- **`ChatCompletionRequest/Response`** — API request/response

**Exceptions:** `AuthenticationError`, `RateLimitError`, `BadRequestError`, `ServerError`

### MCP (`src/agent_kit/mcp_client/`)

Client for MCP servers (HTTP Streamable transport + stdio transport).

- **`Transport`** — MCP transport abstraction
- **`HttpTransport`** — transport for Streamable HTTP (supports `application/json` and `text/event-stream` response formats)
- **`StdioTransport`** — transport for JSON-RPC over stdin/stdout (JSONL)
- **`SSEParser`** — Server-Sent Events parser
- **`Client`** — client for single MCP server
- **`Manager`** — multiple server management
- **`StdioSupervisor`** — supervisor for stdio servers (auto-restart)
- **`CallToolResult`** — tool call result

**Protocol:**
1. `initialize` handshake → get `Mcp-Session-Id`
2. `notifications/initialized` notification
3. `tools/list`, `tools/call` and other methods

**Stdio:** JSON-RPC over stdin/stdout (JSONL), auto-restart via `StdioSupervisor`.

### Agent (`src/agent_kit/`)

Main agent combining LLM and MCP.

- **`Agent`** (`agent_loop.cr`) — main class with `setup`, `run`, `run_continue`, `cleanup` methods
- **`AgentEvent`** (`events.cr`) — base event class (and subclasses: `BeforeMCPCallEvent`, `AfterMCPCallEvent`, etc.)
- **`ToolRegistry`** (`tool_registry.cr`) — MCP tools to OpenAI format conversion
- **`MessageHistory`** (`message_history.cr`) — message history management

**Agent Loop:**
1. Emit `BeforeLLMCallEvent`
2. Send messages to LLM
3. Emit `AfterLLMCallEvent`
4. If `finish_reason == "tool_calls"`:
   - Emit `BeforeMCPCallEvent` for each tool
   - Execute tool
   - Emit `AfterMCPCallEvent`
5. Add results to history
6. Repeat until `finish_reason == "stop"` or max iterations
7. Emit `AgentCompletedEvent`

**Events:** Auto-continue by default. Call `event.stop!` to halt the agent.

---

## Dependencies

### shard.yml

```yaml
dependencies:
  mcprotocol:
    github: nobodywasishere/mcprotocol

development_dependencies:
  webmock:
    github: manastech/webmock.cr
```

| Shard | Purpose |
|-------|---------|
| `mcprotocol` | MCP data types and serialization |
| `webmock` | HTTP mocking for unit tests |

### Standard Library

- `HTTP::Client` — HTTP requests
- `JSON` — serialization
- `Log` — logging

---

## Testing

### Test Structure

```
spec/
├── spec_helper.cr
├── config_spec.cr
├── openai/
│   ├── types_spec.cr
│   ├── client_spec.cr
│   └── integration_spec.cr    # tag: integration
├── mcp/
│   ├── sse_parser_spec.cr
│   ├── transport_spec.cr
│   ├── client_spec.cr
│   └── manager_spec.cr
└── agent/
    ├── agent_spec.cr
    ├── events_spec.cr
    ├── tool_registry_spec.cr
    └── message_history_spec.cr
```

### Commands

```bash
# Unit tests
just test

# Integration tests (requires MCP server)
just test-integration

# All tests
just test-all
```

### Unit Tests

Use WebMock for HTTP mocking:

```crystal
WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
  .to_return(status: 200, body: response.to_json)
```

### Integration Tests

Require running MCP server at `http://localhost:8000/mcp`:

```bash
# Start test MCP server
just mcp-test-server

# Or automatically via just
just test-integration-http

# Stdio integration tests (spawn stdio server as subprocess)
just test-integration-stdio
```

---

## Development

### justfile Commands

```bash
just test           # Unit tests
just test-all       # All tests
just fmt            # Format
just fmt-check      # Check formatting
just check          # Type check
just deps           # Install dependencies
just clean          # Clean artifacts
```

### Adding New MCP Method

1. Add method to `src/mcp/client.cr`
2. Use types from `mcprotocol` for deserialization
3. Add unit test in `spec/mcp/client_spec.cr`
4. Add integration test in `spec/mcp_integration/`

### Adding New OpenAI Parameter

1. Add field to `ChatCompletionRequest` (`src/openai/types.cr`)
2. Add parameter to `Client#chat_completion` (`src/openai/client.cr`)
3. Add tests

---

## Code Conventions

- **Formatting:** `crystal tool format`
- **Naming:** snake_case for methods/variables, PascalCase for types
- **Logging:** use `AgentKit::Log`
- **Errors:** create specific Exception classes
- **JSON:** use `JSON::Serializable` for types

---

## Git Workflow

```bash
# Before commit
just fmt
just test

# Commit
git add .
git commit -m "feat: description"
```

### Commit Format

- `feat:` — new feature
- `fix:` — bug fix
- `docs:` — documentation
- `test:` — tests
- `refactor:` — refactoring

---

## Known Limitations

1. **mcprotocol URI bug** — `MCProtocol::Resource` uses `URI` type which doesn't deserialize from JSON. Methods `list_resources`, `read_resource` may not work.

2. **No streaming** — LLM responses are received in full, without streaming.
