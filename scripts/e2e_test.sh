#!/bin/bash
# E2E Test Script for Crystal Agent
# This script runs the compiled binary against a real MCP server
# and verifies the expected output.
# Note: MCP server is started by justfile (_with-mcp-server recipe)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

BIN="$PROJECT_DIR/bin/crystal_agent"
TEST_CONFIG="$PROJECT_DIR/config/test_mcp_servers.json"
TEMP_CONFIG=""
PROMPTS_DIR="$PROJECT_DIR/scripts/test_prompts"
RESULTS_DIR="/tmp/crystal_agent_e2e_results"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED++))
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if [ ! -f "$BIN" ]; then
        echo -e "${RED}ERROR: Binary not found: $BIN${NC}"
        echo "Run 'just build' first"
        exit 1
    fi
    
    # Prefer OPENAI_API_KEY to generate temp config (ensures type:"http")
    if [ -n "${OPENAI_API_KEY}" ]; then
        local api_host
        local model
        api_host="${OPENAI_API_HOST:-https://api.openai.com}"
        model="${OPENAI_MODEL:-gpt-4o}"

        TEMP_CONFIG="/tmp/crystal_agent_e2e_config.json"
        cat > "$TEMP_CONFIG" << EOF
{
  "openaiApiKey": "${OPENAI_API_KEY}",
  "openaiApiHost": "${api_host}",
  "openaiModel": "${model}",
  "mcpServers": {
    "test": {
      "type": "http",
      "url": "http://localhost:8000/mcp"
    }
  }
}
EOF
        TEST_CONFIG="$TEMP_CONFIG"
    fi

    # Check config file exists and has required fields
    if [ ! -f "$TEST_CONFIG" ]; then
        echo -e "${YELLOW}SKIP: Config file not found and OPENAI_API_KEY not set${NC}"
        exit 0
    fi

    # Extract openaiApiKey from JSON config using grep/sed (no jq dependency)
    local api_key
    api_key=$(grep -o '"openaiApiKey"[[:space:]]*:[[:space:]]*"[^"]*"' "$TEST_CONFIG" | sed 's/.*: *"\([^"]*\)".*/\1/')

    if [ -z "$api_key" ] || [ "$api_key" = "YOUR_API_KEY_HERE" ]; then
        echo -e "${YELLOW}SKIP: openaiApiKey not set in $TEST_CONFIG${NC}"
        exit 0
    fi

    # Ensure MCP HTTP config includes type:"http" (breaking change)
    if ! grep -q '"type"[[:space:]]*:[[:space:]]*"http"' "$TEST_CONFIG"; then
        echo -e "${YELLOW}SKIP: MCP config missing type=\"http\" in $TEST_CONFIG${NC}"
        exit 0
    fi
    
    mkdir -p "$PROMPTS_DIR"
    mkdir -p "$RESULTS_DIR"
    
    log_info "Prerequisites OK"
}

# Test 1: Simple prompt without tool calls
test_simple_prompt() {
    log_info "Test 1: Simple prompt without tool calls"
    
    local prompt_file="$PROMPTS_DIR/simple.txt"
    local output_file="$RESULTS_DIR/simple_output.txt"
    
    echo "Say exactly 'Hello World' and nothing else." > "$prompt_file"
    
    if "$BIN" "$prompt_file" --config "$TEST_CONFIG" --output "$output_file"; then
        if grep -qi "hello" "$output_file"; then
            log_pass "Simple prompt returned expected greeting"
        else
            log_fail "Simple prompt did not contain 'hello'"
            echo "Output was: $(cat "$output_file")"
        fi
    else
        log_fail "Binary execution failed"
    fi
}

# Test 2: Prompt with tool call (add_numbers)
test_add_numbers_tool() {
    log_info "Test 2: Prompt with add_numbers tool"
    
    local prompt_file="$PROMPTS_DIR/add_numbers.txt"
    local output_file="$RESULTS_DIR/add_numbers_output.txt"
    
    echo "Use the add_numbers tool to add 15 and 27. Tell me just the result." > "$prompt_file"
    
    if "$BIN" "$prompt_file" --config "$TEST_CONFIG" --output "$output_file"; then
        if grep -q "42" "$output_file"; then
            log_pass "add_numbers tool returned correct result (42)"
        else
            log_fail "add_numbers tool did not return 42"
            echo "Output was: $(cat "$output_file")"
        fi
    else
        log_fail "Binary execution failed"
    fi
}

# Test 3: Prompt with hello_world tool
test_hello_world_tool() {
    log_info "Test 3: Prompt with hello_world tool"
    
    local prompt_file="$PROMPTS_DIR/hello_world.txt"
    local output_file="$RESULTS_DIR/hello_world_output.txt"
    
    echo "Use the hello_world tool with name 'CrystalAgent'. Tell me what it says." > "$prompt_file"
    
    if "$BIN" "$prompt_file" --config "$TEST_CONFIG" --output "$output_file"; then
        if grep -qi "crystal" "$output_file"; then
            log_pass "hello_world tool returned response with 'Crystal'"
        else
            log_fail "hello_world tool did not mention 'Crystal'"
            echo "Output was: $(cat "$output_file")"
        fi
    else
        log_fail "Binary execution failed"
    fi
}

# Test 4: Multiple tool calls
test_multiple_tools() {
    log_info "Test 4: Multiple tool calls"
    
    local prompt_file="$PROMPTS_DIR/multiple_tools.txt"
    local output_file="$RESULTS_DIR/multiple_tools_output.txt"
    
    cat > "$prompt_file" << 'EOF'
I need you to do two things:
1. Use add_numbers to add 10 and 5
2. Use hello_world with name "Test"
Tell me both results.
EOF
    
    if "$BIN" "$prompt_file" --config "$TEST_CONFIG" --output "$output_file"; then
        if grep -q "15" "$output_file"; then
            log_pass "Multiple tools: add_numbers returned 15"
        else
            log_fail "Multiple tools: add_numbers did not return 15"
            echo "Output was: $(cat "$output_file")"
        fi
    else
        log_fail "Binary execution failed"
    fi
}

# Test 5: Output to stdout (no --output flag)
test_stdout_output() {
    log_info "Test 5: Output to stdout"
    
    local prompt_file="$PROMPTS_DIR/stdout.txt"
    
    echo "Say 'stdout works' and nothing else." > "$prompt_file"
    
    local output
    output=$("$BIN" "$prompt_file" --config "$TEST_CONFIG")
    
    if echo "$output" | grep -qi "stdout"; then
        log_pass "stdout output works"
    else
        log_fail "stdout output did not contain expected text"
        echo "Output was: $output"
    fi
}

# Test 6: Help flag
test_help_flag() {
    log_info "Test 6: Help flag"
    
    local output
    output=$("$BIN" --help 2>&1 || true)
    
    if echo "$output" | grep -qi "prompt\|usage\|options"; then
        log_pass "Help flag shows usage information"
    else
        log_fail "Help flag did not show expected usage"
        echo "Output was: $output"
    fi
}

# Main
main() {
    echo "========================================"
    echo "Crystal Agent E2E Tests"
    echo "========================================"
    echo ""
    
    check_prerequisites
    cd "$PROJECT_DIR"
    
    echo ""
    echo "Running tests..."
    echo ""
    
    test_help_flag
    test_simple_prompt
    test_add_numbers_tool
    test_hello_world_tool
    test_multiple_tools
    test_stdout_output
    
    echo ""
    echo "========================================"
    printf "Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}\n" "$PASSED" "$FAILED"
    echo "========================================"
    
    if [ $FAILED -gt 0 ]; then
        exit 1
    fi

    if [ -n "$TEMP_CONFIG" ] && [ -f "$TEMP_CONFIG" ]; then
        rm -f "$TEMP_CONFIG"
    fi
}

main "$@"
