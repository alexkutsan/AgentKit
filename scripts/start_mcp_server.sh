#!/bin/bash
# Start MCP test server for development/testing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Starting MCP server on http://localhost:8000/mcp ..."
cd "$SCRIPT_DIR/mcp_test_server"
uv run mcp_server.py
