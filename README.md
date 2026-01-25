# Crystal Agent

LLM agent with MCP (Model Context Protocol) server support.

## Installation

### Requirements

- Crystal >= 1.19.0
- OpenAI API key (or compatible provider)

### Build from source

```bash
git clone https://github.com/your-org/crystal_agent.git
cd crystal_agent
shards install
shards build --release
```

Binary will be at `./bin/crystal_agent`.

---

## Quick Start

### 1. Create configuration

```bash
mkdir -p ~/.config/crystal_agent
cat > ~/.config/crystal_agent/config.json << 'EOF'
{
  "openaiApiKey": "sk-your-api-key-here",
  "openaiModel": "gpt-4o"
}
EOF
```

### 2. Run the agent

```bash
./bin/crystal_agent -p "Hello! How are you?"
```

---

## Usage

```bash
# Direct prompt
./bin/crystal_agent -p "Your question"

# Prompt from file
./bin/crystal_agent prompt.txt

# Output to file
./bin/crystal_agent -p "Generate a list" -o result.txt

# Interactive mode
./bin/crystal_agent -i

# Specify config
./bin/crystal_agent -p "Question" -c /path/to/config.json
```

### Options

| Option | Description |
|--------|-------------|
| `-p, --prompt` | Prompt text |
| `-o, --output` | Output file (default: stdout) |
| `-c, --config` | Config file path |
| `-i, --interactive` | Interactive mode (REPL) |
| `-h, --help` | Show help |
| `-v, --version` | Show version |

---

## Configuration

Agent looks for config in:
1. `~/.config/crystal_agent/config.json`
2. `~/.crystal_agent.json`

### Minimal config

```json
{
  "openaiApiKey": "sk-..."
}
```

### Full config

```json
{
  "openaiApiKey": "sk-...",
  "openaiApiHost": "https://api.openai.com",
  "openaiModel": "gpt-4o",
  "maxIterations": 10,
  "timeoutSeconds": 120,
  "mcpServers": {
    "my-server": {
      "type": "http",
      "url": "http://localhost:8000/mcp"
    }
  }
}
```

| Parameter | Description | Default |
|-----------|-------------|---------|
| `openaiApiKey` | API key (required) | — |
| `openaiApiHost` | API URL | `https://api.openai.com` |
| `openaiModel` | Model | `gpt-4o` |
| `maxIterations` | Max iterations | `10` |
| `timeoutSeconds` | Timeout (sec) | `120` |
| `mcpServers` | MCP servers | `{}` |

**Logging** is configured via ENV: `CRYSTAL_AGENT_LOG_LEVEL` (debug/info/warn/error, default `warn`) and `CRYSTAL_AGENT_LOG_FILE`.

---

## MCP Servers

Agent can connect to MCP servers to use external tools.

HTTP config without `"type": "http"` is considered invalid. Environment variables can be used as `${VAR}` or `${VAR:-default}`.

```json
{
  "openaiApiKey": "sk-...",
  "mcpServers": {
    "filesystem": {
      "type": "http",
      "url": "http://localhost:8000/mcp"
    },
    "database": {
      "type": "http",
      "url": "http://localhost:8001/mcp",
      "headers": {
        "Authorization": "Bearer token"
      }
    }
  }
}
```

### Stdio MCP server (local process)

```json
{
  "openaiApiKey": "sk-...",
  "mcpServers": {
    "local-tools": {
      "command": "python3",
      "args": ["-u", "/path/to/mcp_server.py"]
    }
  }
}
```

On startup, the agent automatically connects to servers and registers available tools.

---

## Documentation

- [USER_GUIDE.md](docs/USER_GUIDE.md) — detailed user guide
- [DEVELOPERS_GUIDE.md](docs/DEVELOPERS_GUIDE.md) — for project contributors
- [INTEGRATION_GUIDE.md](docs/INTEGRATION_GUIDE.md) — using as a library

---

## License

MIT
