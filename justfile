# Crystal Agent - Development Recipes
# Usage: just <recipe>

# Default recipe - show help
default:
    @just --list

# ============================================
# Build & Run
# ============================================

# Build the project
build:
    shards build

# Build in release mode
build-release:
    shards build --release

# ============================================
# Testing
# ============================================

# Run all tests (excluding integration)
test:
    crystal spec --tag '~integration' --verbose --fail-fast -Dspec

# Run integration tests (starts MCP server automatically)
test-integration: test-integration-http test-integration-stdio

# Run integration tests (http streamable; starts MCP server automatically)
test-integration-http: (_with-mcp-test-server "crystal spec --tag integration --fail-fast -Dspec")

# Run integration tests (stdio; spawns server as subprocess inside specs)
test-integration-stdio:
    crystal spec --tag integration_stdio --fail-fast -Dspec

# Run E2E tests (starts MCP server automatically)
test-e2e: build (_with-mcp-test-server "./scripts/e2e_test.sh")

# Run all tests
test-all: test test-integration test-e2e

# Run tests with code coverage (requires kcov)
# Note: In containers, requires --cap-add=SYS_PTRACE (see devcontainer.json)
test-coverage:
    #!/bin/bash
    set -e
    
    # Check if kcov is installed
    if ! command -v kcov &> /dev/null; then
        echo "Error: kcov is not installed."
        echo "Install with: sudo apt-get install kcov"
        echo "Or build from source: https://github.com/SimonKagstrom/kcov"
        exit 1
    fi
    
    echo "Building spec binary with debug info..."
    crystal build spec/spec_runner.cr -o bin/spec_runner -Dspec --debug
    
    echo "Running tests with kcov..."
    rm -rf coverage
    
    # Try to run kcov, provide helpful error if ptrace fails
    if ! kcov --include-path=src coverage bin/spec_runner 2>&1; then
        echo ""
        echo "Error: kcov failed. If you see 'Can't set personality' error,"
        echo "you need to rebuild the devcontainer to enable SYS_PTRACE."
        echo "Run: 'Rebuild Container' from VS Code command palette."
        exit 1
    fi
    
    echo ""
    echo "Coverage report generated in coverage/index.html"
    echo "Open: file://$(pwd)/coverage/index.html"

# View coverage report (opens in browser if available)
coverage-report:
    @if [ -f coverage/index.html ]; then \
        echo "Coverage report: file://$(pwd)/coverage/index.html"; \
        which xdg-open > /dev/null && xdg-open coverage/index.html || true; \
    else \
        echo "No coverage report found. Run 'just test-coverage' first."; \
    fi 
    
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
    crystal build --no-codegen src/main.cr

# ============================================
# Git Workflow (Stage Commits)
# ============================================

# Clean build artifacts
clean:
    rm -rf bin/
    rm -rf lib/
    rm -rf .shards/

# Clean and rebuild
rebuild: clean deps build
