# AgentKit - Development Recipes
# Usage: just <recipe>

# Default recipe - show help
default:
    @just --list

# ============================================
# Testing
# ============================================

# Run all unit tests
test:
    crystal spec --tag '~integration' --tag '~integration_stdio' --verbose --fail-fast

# Run integration tests (starts MCP server automatically)
test-integration: test-integration-http test-integration-stdio

# Run integration tests (http streamable; starts MCP server automatically)
test-integration-http: (_with-mcp-test-server "crystal spec --tag integration --fail-fast")

# Run integration tests (stdio; spawns server as subprocess inside specs)
test-integration-stdio:
    crystal spec --tag integration_stdio --fail-fast

# Run all tests
test-all: test test-integration

# Start test MCP server (for development)
mcp-test-server:
    #!/bin/bash
    cd "{{justfile_directory()}}/scripts/mcp_test_server"
    uv run mcp_server.py

# Internal: Run command with test MCP server (uses existing if available)
_with-mcp-test-server cmd:
    #!/bin/bash
    set -e
    MCP_PID=""
    
    if [ -f "{{justfile_directory()}}/.env" ]; then
        set -a
        . "{{justfile_directory()}}/.env"
        set +a
    fi
    
    if [ -n "${API_KEY:-}" ] && [ -z "${OPENAI_API_KEY:-}" ]; then
        export OPENAI_API_KEY="$API_KEY"
    fi
    
    # Check if MCP server is already running
    if curl -s http://localhost:8000/mcp -X POST \
        -H "Content-Type: application/json" \
        -H "Accept: application/json, text/event-stream" \
        -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' \
        | grep -q "protocolVersion" 2>/dev/null; then
        echo "Test MCP server already running, using existing instance"
    else
        # Start MCP server in background
        echo "Starting test MCP server..."
        cd "{{justfile_directory()}}/scripts/mcp_test_server"
        uv run mcp_server.py > /tmp/mcp-server.log 2>&1 &
        MCP_PID=$!
        
        # Wait for server to be ready (up to 30 seconds)
        echo "Waiting for test MCP server to start..."
        for i in {1..30}; do
            if curl -s http://localhost:8000/mcp -X POST \
                -H "Content-Type: application/json" \
                -H "Accept: application/json, text/event-stream" \
                -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' \
                | grep -q "protocolVersion" 2>/dev/null; then
                echo "Test MCP server is ready!"
                break
            fi
            sleep 1
        done
    fi
    
    # Run the command
    cd "{{justfile_directory()}}"
    {{cmd}} || TEST_RESULT=$?
    
    # Stop MCP server only if we started it
    if [ -n "$MCP_PID" ]; then
        echo "Stopping test MCP server (PID: $MCP_PID)..."
        kill $MCP_PID 2>/dev/null || true
    fi
    
    exit ${TEST_RESULT:-0}

# ============================================
# Development
# ============================================

# Install dependencies
deps:
    shards install

# Update dependencies
deps-update:
    shards update

# Format code
fmt:
    crystal tool format src spec

# Check code formatting
fmt-check:
    crystal tool format --check src spec

# Run static analysis (Ameba)
lint:
    bin/ameba

# Type check without building
check:
    crystal build --no-codegen src/agent_kit.cr

# ============================================
# Git Workflow (Stage Commits)
# ============================================

# Clean build artifacts
clean:
    rm -rf bin/
    rm -rf lib/
    rm -rf .shards/

# Clean and rebuild
rebuild: clean deps
