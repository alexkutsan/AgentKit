# AgentKit - AI agent library with MCP support
#
# This is the main entry point for using AgentKit as a library.
# For CLI usage, see src/main.cr

require "./agent_kit/config"
require "./logger"
require "./agent_kit/openai_api/types"
require "./agent_kit/openai_api/client"
require "./agent_kit/mcp_client/sse_parser"
require "./agent_kit/mcp_client/transport"
require "./agent_kit/mcp_client/client"
require "./agent_kit/mcp_client/manager"
require "./agent_kit/tool_registry"
require "./agent_kit/message_history"
require "./agent_kit/events"
require "./agent_kit/agent_loop"

module AgentKit
  VERSION = "0.1.0"
end
