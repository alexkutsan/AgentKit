# Crystal Agent — User Guide

LLM agent written in Crystal with MCP (Model Context Protocol) server support.

## Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/your-org/crystal_agent.git
cd crystal_agent

# Install dependencies and build
shards install
shards build --release
```

### Create Configuration

Create file `~/.config/agentish/config.json`:

```json
{
  "openaiApiKey": "sk-your-api-key",
  "openaiModel": "gpt-4o",
  "mcpServers": {
    "my-server": {
      "type": "http",
      "url": "http://localhost:8000/mcp"
    }
  }
}
```

### Run

```bash
# Prompt from file
./bin/agentish prompt.txt

# Inline prompt
./bin/agentish -p "Hello, how are you?"
```

---

## CLI Usage

```
Usage: agentish [options] [prompt_file]

Arguments:
  prompt_file    Path to prompt file

Options:
  -p, --prompt PROMPT    Prompt text (inline)
  -o, --output FILE      Output file (default: stdout)
  -c, --config FILE      Config file
  -i, --interactive      Interactive mode (REPL)
  -h, --help             Show help
  -v, --version          Show version
```

### Examples

```bash
# Basic usage
./bin/agentish prompt.txt

# Inline prompt
./bin/agentish -p "Add 15 and 27"

# Output to file
./bin/agentish prompt.txt -o result.txt

# Interactive mode
./bin/agentish -i

# Custom config
./bin/agentish prompt.txt -c ~/my_config.json
```

### Interactive Mode

Run the agent with `-i` flag to enter interactive mode:

```bash
./bin/agentish -i
```

On startup the agent:
1. Connects to configured MCP servers
2. Displays list of connected servers and their tools
3. Enters prompt input loop

```
=== Connected MCP Servers ===
  [✓] filesystem
      - read_file: Read file contents
      - write_file: Write to file
  [✓] database
      - query: Execute SQL query
=============================

Crystal Agent v0.1.0 - Interactive Mode
Type your prompts below. Press Ctrl-C to exit.

> Read file /etc/hostname
[MCP CALL] filesystem__read_file({"path": "/etc/hostname"})
[MCP RESULT] filesystem__read_file => myhost

The hostname is: myhost

> 
```

Press **Ctrl-C** to exit.

---

## Configuration

### Config Location

Agent looks for config in the following locations (in priority order):

1. `~/.config/agentish/config.json` — recommended
2. `~/.agentish.json` — alternative
3. `~/Library/Application Support/Claude/claude_desktop_config.json` — Claude Desktop compatibility

### Configuration Parameters

```json
{
  "openaiApiKey": "sk-...",
  "openaiApiHost": "https://api.openai.com",
  "openaiModel": "gpt-4o",
  "maxIterations": 10,
  "timeoutSeconds": 120,
  "mcpServers": {
    "server-name": {
      "type": "http",
      "url": "http://localhost:8000/mcp",
      "headers": {
        "Authorization": "Bearer token"
      }
    }
  }
}
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `openaiApiKey` | OpenAI API key (required) | — |
| `openaiApiHost` | API URL | `https://api.openai.com` |
| `openaiModel` | LLM model | `gpt-4o` |
| `maxIterations` | Max agent iterations | `10` |
| `timeoutSeconds` | Request timeout (sec) | `120` |
| `mcpServers` | MCP servers | `{}` |

---

## MCP Servers

Crystal Agent connects to MCP servers via HTTP Streamable transport or stdio transport and automatically registers available tools.
Legacy `/sse` and `type: "sse"` variants are not supported.

### MCP Server Configuration

```json
{
  "mcpServers": {
    "filesystem": {
      "type": "http",
      "url": "http://localhost:8000/mcp"
    },
    "database": {
      "type": "http",
      "url": "http://localhost:8001/mcp",
      "headers": {
        "Authorization": "Bearer secret-token"
      }
    }
  }
}
```

### Stdio MCP Server (local process)

```json
{
  "mcpServers": {
    "local-tools": {
      "command": "python3",
      "args": ["-u", "/path/to/mcp_server.py"],
      "env": {
        "MY_TOKEN": "${MY_TOKEN:-default}"
      }
    }
  }
}
```

Stdio servers are automatically restarted on crash (with backoff and restart limit).

Environment variables in config can be used as `${VAR}` or `${VAR:-default}` — they are expanded in `url`, `headers` values, `env` values, and each element of `args`.

### Tool Naming

Tools from MCP servers get a prefix with the server name:
- Server `filesystem` with tool `read_file` → `filesystem__read_file`
- Server `database` with tool `query` → `database__query`

### Tool Call Output

When calling tools, the agent outputs information to stdout:

```
[MCP CALL] filesystem__read_file({"path": "/etc/hosts"})
[MCP RESULT] filesystem__read_file => 127.0.0.1 localhost
```

---

## Provider Compatibility

Crystal Agent is compatible with any OpenAI-compatible API:

| Provider | `openaiApiHost` |
|----------|-----------------|
| OpenAI | `https://api.openai.com` |
| Azure OpenAI | `https://{resource}.openai.azure.com` |
| Ollama | `http://localhost:11434` |
| OpenRouter | `https://openrouter.ai/api` |
| Together AI | `https://api.together.xyz` |

---

## Logging

Logging is configured via environment variables (not via config file):

| Variable | Description | Default |
|----------|-------------|---------|
| `CRYSTAL_AGENT_LOG_LEVEL` | Log level: debug, info, warn, error | `warn` |
| `CRYSTAL_AGENT_LOG_FILE` | Log file | stderr |

### Log Levels

| Level | Description |
|-------|-------------|
| `debug` | Detailed debug information |
| `info` | Main events (connection, tools) |
| `warn` | Warnings |
| `error` | Errors |

### Examples

```bash
# Enable debug logging
CRYSTAL_AGENT_LOG_LEVEL=debug ./bin/agentish prompt.txt

# Output logs to file
CRYSTAL_AGENT_LOG_FILE=/var/log/crystal_agent.log ./bin/agentish prompt.txt

# Combination
CRYSTAL_AGENT_LOG_LEVEL=debug CRYSTAL_AGENT_LOG_FILE=agent.log ./bin/agentish -i
```

---

## Usage Examples

### Simple Prompt

```bash
echo "What's the weather in Rio de Janeiro?" > prompt.txt
./bin/agentish prompt.txt
```

### With MCP Server for File Operations

```bash
# Config with filesystem MCP server
cat > config.json << 'EOF'
{
  "openaiApiKey": "sk-...",
  "mcpServers": {
    "fs": {"type": "http", "url": "http://localhost:8000/mcp"}
  }
}
EOF

# Prompt
echo "Read file /etc/hostname and tell me the hostname" > prompt.txt

./bin/agentish prompt.txt -c config.json
```

### Automation with File Output

```bash
./bin/agentish -p "Generate 5 random names" -o names.txt
cat names.txt
```

---

## Troubleshooting

### Error "No config file found"

Create config in one of the standard locations or specify path via `-c`.

### Error "Invalid API key"

Check `openaiApiKey` in config.

### MCP Server Not Connecting

1. Make sure the server is running and accessible at the specified URL
2. Check logs with `CRYSTAL_AGENT_LOG_LEVEL=debug`
3. Check headers if authorization is required

### Request Timeout

Increase `timeoutSeconds` in config for long-running operations.
