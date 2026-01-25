require "../spec_helper"
require "../../src/agent_kit/agent_loop"
require "webmock"

describe AgentKit::Agent do
  before_each do
    WebMock.reset
  end

  describe "#initialize" do
    it "creates agent with config" do
      config = AgentKit::Config.new(openai_api_key: "test-key")

      agent = AgentKit::Agent.new(config)

      agent.config.should eq(config)
      agent.tool_registry.size.should eq(0)
      agent.history.size.should eq(0)
    end

    it "creates agent with custom system_prompt" do
      config = AgentKit::Config.new(openai_api_key: "test-key")
      custom_prompt = "You are a specialized assistant."

      agent = AgentKit::Agent.new(config, custom_prompt)

      agent.system_prompt.should eq(custom_prompt)
    end

    it "creates agent with nil system_prompt by default" do
      config = AgentKit::Config.new(openai_api_key: "test-key")

      agent = AgentKit::Agent.new(config)

      agent.system_prompt.should be_nil
    end
  end

  describe "#setup" do
    it "registers tools from MCP manager" do
      config = AgentKit::Config.new(openai_api_key: "test-key")

      agent = AgentKit::Agent.new(config)

      mcp_tools = [
        MCProtocol::Tool.from_json({
          name:        "test_tool",
          description: "A test tool",
          inputSchema: {type: "object"},
        }.to_json),
      ]
      agent.tool_registry.register_mcp_tools("test", mcp_tools)

      agent.tool_registry.size.should eq(1)
      agent.tool_registry.has_tool?("test__test_tool").should be_true
    end
  end

  describe "#run" do
    it "completes simple request without tools" do
      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {
            id:      "chatcmpl-test",
            object:  "chat.completion",
            created: 1699000000,
            model:   "gpt-4o",
            choices: [
              {
                index:         0,
                message:       {role: "assistant", content: "Hello! How can I help?"},
                finish_reason: "stop",
              },
            ],
            usage: {prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
          }.to_json
        )

      config = AgentKit::Config.new(openai_api_key: "test-key")

      agent = AgentKit::Agent.new(config)
      result = agent.run("Hello")

      result.should eq("Hello! How can I help?")
    end

    it "returns response for unknown finish_reason" do
      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {
            id:      "chatcmpl-test",
            object:  "chat.completion",
            created: 1699000000,
            model:   "gpt-4o",
            choices: [
              {
                index:         0,
                message:       {role: "assistant", content: "Partial"},
                finish_reason: "length",
              },
            ],
            usage: {prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
          }.to_json
        )

      config = AgentKit::Config.new(openai_api_key: "test-key")
      agent = AgentKit::Agent.new(config)

      agent.run("Hello").should eq("Partial")
    end

    it "returns error when max iterations reached" do
      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {
            id:      "chatcmpl-test",
            object:  "chat.completion",
            created: 1699000000,
            model:   "gpt-4o",
            choices: [
              {
                index:         0,
                message:       {role: "assistant", content: nil},
                finish_reason: "tool_calls",
              },
            ],
            usage: {prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
          }.to_json
        )

      config = AgentKit::Config.new(openai_api_key: "test-key")
      agent = AgentKit::Agent.new(config)

      agent.run("Hello").should eq("Error: Maximum iterations (10) reached")
    end

    it "returns error JSON for unknown tool" do
      call_count = 0

      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return do
          call_count += 1
          if call_count == 1
            HTTP::Client::Response.new(
              status: :ok,
              headers: HTTP::Headers{"Content-Type" => "application/json"},
              body: {
                id:      "chatcmpl-1",
                object:  "chat.completion",
                created: 1699000000,
                model:   "gpt-4o",
                choices: [
                  {
                    index:   0,
                    message: {
                      role:       "assistant",
                      content:    nil,
                      tool_calls: [
                        {
                          id:       "call_abc",
                          type:     "function",
                          function: {name: "unknown__tool", arguments: %q({})},
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
                usage: {prompt_tokens: 20, completion_tokens: 10, total_tokens: 30},
              }.to_json
            )
          else
            HTTP::Client::Response.new(
              status: :ok,
              headers: HTTP::Headers{"Content-Type" => "application/json"},
              body: {
                id:      "chatcmpl-2",
                object:  "chat.completion",
                created: 1699000000,
                model:   "gpt-4o",
                choices: [
                  {
                    index:         0,
                    message:       {role: "assistant", content: "OK"},
                    finish_reason: "stop",
                  },
                ],
                usage: {prompt_tokens: 30, completion_tokens: 5, total_tokens: 35},
              }.to_json
            )
          end
        end

      config = AgentKit::Config.new(openai_api_key: "test-key")
      agent = AgentKit::Agent.new(config)

      agent.run("Hello").should eq("OK")
      call_count.should eq(2)
    end

    it "handles MCPError raised during tool execution" do
      call_count = 0

      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return do
          call_count += 1
          if call_count == 1
            HTTP::Client::Response.new(
              status: :ok,
              headers: HTTP::Headers{"Content-Type" => "application/json"},
              body: {
                id:      "chatcmpl-1",
                object:  "chat.completion",
                created: 1699000000,
                model:   "gpt-4o",
                choices: [
                  {
                    index:   0,
                    message: {
                      role:       "assistant",
                      content:    nil,
                      tool_calls: [
                        {
                          id:       "call_abc",
                          type:     "function",
                          function: {name: "test__add", arguments: %q({"a": 2, "b": 3})},
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
                usage: {prompt_tokens: 20, completion_tokens: 10, total_tokens: 30},
              }.to_json
            )
          else
            HTTP::Client::Response.new(
              status: :ok,
              headers: HTTP::Headers{"Content-Type" => "application/json"},
              body: {
                id:      "chatcmpl-2",
                object:  "chat.completion",
                created: 1699000000,
                model:   "gpt-4o",
                choices: [
                  {
                    index:         0,
                    message:       {role: "assistant", content: "Done"},
                    finish_reason: "stop",
                  },
                ],
                usage: {prompt_tokens: 30, completion_tokens: 5, total_tokens: 35},
              }.to_json
            )
          end
        end

      WebMock.stub(:post, "http://localhost:8000/mcp")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {
            jsonrpc: "2.0",
            id:      1,
            error:   {
              code:    -32600,
              message: "Invalid Request",
            },
          }.to_json
        )

      servers = {"test" => AgentKit::MCPServerConfig.new(type: "http", url: "http://localhost:8000/mcp")}
      config = AgentKit::Config.new(openai_api_key: "test-key", mcp_servers: servers)
      agent = AgentKit::Agent.new(config)

      mcp_tools = [
        MCProtocol::Tool.from_json({
          name:        "add",
          description: "Add numbers",
          inputSchema: {type: "object"},
        }.to_json),
      ]
      agent.tool_registry.register_mcp_tools("test", mcp_tools)

      agent.run("What is 2 + 3?").should eq("Done")
      call_count.should eq(2)
    end

    it "formats tool error result when MCP returns isError=true" do
      call_count = 0

      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return do
          call_count += 1
          if call_count == 1
            HTTP::Client::Response.new(
              status: :ok,
              headers: HTTP::Headers{"Content-Type" => "application/json"},
              body: {
                id:      "chatcmpl-1",
                object:  "chat.completion",
                created: 1699000000,
                model:   "gpt-4o",
                choices: [
                  {
                    index:   0,
                    message: {
                      role:       "assistant",
                      content:    nil,
                      tool_calls: [
                        {
                          id:       "call_abc",
                          type:     "function",
                          function: {name: "test__add", arguments: %q({"a": 2, "b": 3})},
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
                usage: {prompt_tokens: 20, completion_tokens: 10, total_tokens: 30},
              }.to_json
            )
          else
            HTTP::Client::Response.new(
              status: :ok,
              headers: HTTP::Headers{"Content-Type" => "application/json"},
              body: {
                id:      "chatcmpl-2",
                object:  "chat.completion",
                created: 1699000000,
                model:   "gpt-4o",
                choices: [
                  {
                    index:         0,
                    message:       {role: "assistant", content: "Done"},
                    finish_reason: "stop",
                  },
                ],
                usage: {prompt_tokens: 30, completion_tokens: 5, total_tokens: 35},
              }.to_json
            )
          end
        end

      WebMock.stub(:post, "http://localhost:8000/mcp")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {
            jsonrpc: "2.0",
            id:      1,
            result:  {
              content: [{type: "text", text: "bad"}],
              isError: true,
            },
          }.to_json
        )

      servers = {"test" => AgentKit::MCPServerConfig.new(type: "http", url: "http://localhost:8000/mcp")}
      config = AgentKit::Config.new(openai_api_key: "test-key", mcp_servers: servers)
      agent = AgentKit::Agent.new(config)

      mcp_tools = [
        MCProtocol::Tool.from_json({
          name:        "add",
          description: "Add numbers",
          inputSchema: {type: "object"},
        }.to_json),
      ]
      agent.tool_registry.register_mcp_tools("test", mcp_tools)

      agent.run("What is 2 + 3?").should eq("Done")
      call_count.should eq(2)
    end

    it "handles tool calls and returns final response" do
      call_count = 0

      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return do |_|
          call_count += 1
          if call_count == 1
            HTTP::Client::Response.new(
              status: :ok,
              headers: HTTP::Headers{"Content-Type" => "application/json"},
              body: {
                id:      "chatcmpl-1",
                object:  "chat.completion",
                created: 1699000000,
                model:   "gpt-4o",
                choices: [
                  {
                    index:   0,
                    message: {
                      role:       "assistant",
                      content:    nil,
                      tool_calls: [
                        {
                          id:       "call_abc",
                          type:     "function",
                          function: {name: "test__add", arguments: %q({"a": 2, "b": 3})},
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
                usage: {prompt_tokens: 20, completion_tokens: 10, total_tokens: 30},
              }.to_json
            )
          else
            HTTP::Client::Response.new(
              status: :ok,
              headers: HTTP::Headers{"Content-Type" => "application/json"},
              body: {
                id:      "chatcmpl-2",
                object:  "chat.completion",
                created: 1699000000,
                model:   "gpt-4o",
                choices: [
                  {
                    index:         0,
                    message:       {role: "assistant", content: "The result is 5"},
                    finish_reason: "stop",
                  },
                ],
                usage: {prompt_tokens: 30, completion_tokens: 5, total_tokens: 35},
              }.to_json
            )
          end
        end

      WebMock.stub(:post, "http://localhost:8000/mcp")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {jsonrpc: "2.0", id: 1, result: {content: [{type: "text", text: "5"}], isError: false}}.to_json
        )

      servers = {"test" => AgentKit::MCPServerConfig.new(type: "http", url: "http://localhost:8000/mcp")}
      config = AgentKit::Config.new(
        openai_api_key: "test-key",
        mcp_servers: servers
      )

      agent = AgentKit::Agent.new(config)

      mcp_tools = [
        MCProtocol::Tool.from_json({
          name:        "add",
          description: "Add numbers",
          inputSchema: {type: "object"},
        }.to_json),
      ]
      agent.tool_registry.register_mcp_tools("test", mcp_tools)

      result = agent.run("What is 2 + 3?")

      result.should eq("The result is 5")
      call_count.should eq(2)
    end

    it "emits events during execution" do
      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {
            id:      "chatcmpl-test",
            object:  "chat.completion",
            created: 1699000000,
            model:   "gpt-4o",
            choices: [
              {
                index:         0,
                message:       {role: "assistant", content: "Hello!"},
                finish_reason: "stop",
              },
            ],
            usage: {prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
          }.to_json
        )

      config = AgentKit::Config.new(openai_api_key: "test-key")
      agent = AgentKit::Agent.new(config)

      events = [] of AgentKit::AgentEvent
      result = agent.run("Hello") do |event|
        events << event
      end

      result.should eq("Hello!")
      events.size.should eq(3) # BeforeLLM, AfterLLM, Completed
      events[0].should be_a(AgentKit::BeforeLLMCallEvent)
      events[1].should be_a(AgentKit::AfterLLMCallEvent)
      events[2].should be_a(AgentKit::AgentCompletedEvent)
    end

    it "allows stopping via event" do
      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {
            id:      "chatcmpl-test",
            object:  "chat.completion",
            created: 1699000000,
            model:   "gpt-4o",
            choices: [
              {
                index:         0,
                message:       {role: "assistant", content: "Hello!"},
                finish_reason: "stop",
              },
            ],
            usage: {prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
          }.to_json
        )

      config = AgentKit::Config.new(openai_api_key: "test-key")
      agent = AgentKit::Agent.new(config)

      result = agent.run("Hello") do |event|
        event.stop! # Stop on first event
      end

      result.should eq("") # Stopped before completion
    end

    it "emits MCP events during tool execution" do
      call_count = 0

      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return do
          call_count += 1
          if call_count == 1
            HTTP::Client::Response.new(
              status: :ok,
              headers: HTTP::Headers{"Content-Type" => "application/json"},
              body: {
                id:      "chatcmpl-1",
                object:  "chat.completion",
                created: 1699000000,
                model:   "gpt-4o",
                choices: [
                  {
                    index:   0,
                    message: {
                      role:       "assistant",
                      content:    nil,
                      tool_calls: [
                        {
                          id:       "call_abc",
                          type:     "function",
                          function: {name: "test__add", arguments: %q({"a": 2, "b": 3})},
                        },
                      ],
                    },
                    finish_reason: "tool_calls",
                  },
                ],
                usage: {prompt_tokens: 20, completion_tokens: 10, total_tokens: 30},
              }.to_json
            )
          else
            HTTP::Client::Response.new(
              status: :ok,
              headers: HTTP::Headers{"Content-Type" => "application/json"},
              body: {
                id:      "chatcmpl-2",
                object:  "chat.completion",
                created: 1699000000,
                model:   "gpt-4o",
                choices: [
                  {
                    index:         0,
                    message:       {role: "assistant", content: "Result is 5"},
                    finish_reason: "stop",
                  },
                ],
                usage: {prompt_tokens: 30, completion_tokens: 5, total_tokens: 35},
              }.to_json
            )
          end
        end

      WebMock.stub(:post, "http://localhost:8000/mcp")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {jsonrpc: "2.0", id: 1, result: {content: [{type: "text", text: "5"}], isError: false}}.to_json
        )

      servers = {"test" => AgentKit::MCPServerConfig.new(type: "http", url: "http://localhost:8000/mcp")}
      config = AgentKit::Config.new(openai_api_key: "test-key", mcp_servers: servers)
      agent = AgentKit::Agent.new(config)

      mcp_tools = [
        MCProtocol::Tool.from_json({
          name:        "add",
          description: "Add numbers",
          inputSchema: {type: "object"},
        }.to_json),
      ]
      agent.tool_registry.register_mcp_tools("test", mcp_tools)

      events = [] of AgentKit::AgentEvent
      result = agent.run("What is 2 + 3?") do |event|
        events << event
      end

      result.should eq("Result is 5")

      event_types = events.map(&.class.name)
      event_types.should contain("AgentKit::BeforeMCPCallEvent")
      event_types.should contain("AgentKit::AfterMCPCallEvent")

      before_mcp = events.find { |e| e.is_a?(AgentKit::BeforeMCPCallEvent) }.as(AgentKit::BeforeMCPCallEvent)
      before_mcp.tool_name.should eq("test__add")

      after_mcp = events.find { |e| e.is_a?(AgentKit::AfterMCPCallEvent) }.as(AgentKit::AfterMCPCallEvent)
      after_mcp.tool_name.should eq("test__add")
      after_mcp.result.should eq("5")
      after_mcp.error?.should be_false
    end
  end

  describe "max_iterations from config" do
    it "respects max_iterations from config and returns error when exceeded" do
      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {
            id:      "chatcmpl-loop",
            object:  "chat.completion",
            created: 1699000000,
            model:   "gpt-4o",
            choices: [
              {
                index:   0,
                message: {
                  role:       "assistant",
                  content:    nil,
                  tool_calls: [
                    {
                      id:       "call_loop",
                      type:     "function",
                      function: {name: "test__echo", arguments: %q({"text": "loop"})},
                    },
                  ],
                },
                finish_reason: "tool_calls",
              },
            ],
            usage: {prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
          }.to_json
        )

      WebMock.stub(:post, "http://localhost:8000/mcp")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: {jsonrpc: "2.0", id: 1, result: {content: [{type: "text", text: "echoed"}], isError: false}}.to_json
        )

      servers = {"test" => AgentKit::MCPServerConfig.new(type: "http", url: "http://localhost:8000/mcp")}
      config = AgentKit::Config.new(
        openai_api_key: "test-key",
        mcp_servers: servers,
        max_iterations: 3
      )
      agent = AgentKit::Agent.new(config)

      mcp_tools = [
        MCProtocol::Tool.from_json({
          name:        "echo",
          description: "Echo text",
          inputSchema: {type: "object"},
        }.to_json),
      ]
      agent.tool_registry.register_mcp_tools("test", mcp_tools)

      error_event_received = false
      result = agent.run("Loop forever") do |event|
        if event.is_a?(AgentKit::AgentErrorEvent)
          error_event_received = true
        end
      end

      result.should eq("Error: Maximum iterations (3) reached")
      error_event_received.should be_true
    end

    it "uses default max_iterations (10) when not specified in config" do
      config = AgentKit::Config.new(openai_api_key: "test-key")
      config.max_iterations.should eq(10)
    end
  end

  describe "#cleanup" do
    it "closes MCP connections" do
      config = AgentKit::Config.new(openai_api_key: "test-key")

      agent = AgentKit::Agent.new(config)
      agent.cleanup

      agent.mcp_manager.clients.each_value do |client|
        client.connected?.should be_false
      end
    end
  end
end
