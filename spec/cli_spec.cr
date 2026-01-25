require "./spec_helper"
require "../src/main"
require "webmock"

describe Agentish::CLI do
  describe "#initialize" do
    it "creates CLI with default values" do
      cli = Agentish::CLI.new

      cli.prompt.should be_nil
      cli.prompt_file.should be_nil
      cli.output_file.should be_nil
      cli.config_file.should be_nil
      cli.interactive?.should be_false
    end
  end

  describe "#parse_args" do
    it "parses -p/--prompt option" do
      cli = Agentish::CLI.new
      cli.parse_args(["-p", "Hello world"])

      cli.prompt.should eq("Hello world")
    end

    it "parses --prompt long option" do
      cli = Agentish::CLI.new
      cli.parse_args(["--prompt", "Test prompt"])

      cli.prompt.should eq("Test prompt")
    end

    it "parses -o/--output option" do
      cli = Agentish::CLI.new
      cli.parse_args(["-o", "output.txt"])

      cli.output_file.should eq("output.txt")
    end

    it "parses -c/--config option" do
      cli = Agentish::CLI.new
      cli.parse_args(["-c", "/path/to/config.json"])

      cli.config_file.should eq("/path/to/config.json")
    end

    it "parses -i/--interactive option" do
      cli = Agentish::CLI.new
      cli.parse_args(["-i"])

      cli.interactive?.should be_true
    end

    it "parses --interactive long option" do
      cli = Agentish::CLI.new
      cli.parse_args(["--interactive"])

      cli.interactive?.should be_true
    end

    it "parses positional argument as prompt file" do
      cli = Agentish::CLI.new
      cli.parse_args(["prompt.txt"])

      cli.prompt_file.should eq("prompt.txt")
    end

    it "parses multiple options together" do
      cli = Agentish::CLI.new
      cli.parse_args(["-c", "config.json", "-i"])

      cli.config_file.should eq("config.json")
      cli.interactive?.should be_true
    end

    it "interactive mode does not require prompt" do
      cli = Agentish::CLI.new
      cli.parse_args(["-i"])

      cli.interactive?.should be_true
      cli.prompt.should be_nil
      cli.prompt_file.should be_nil
    end

    it "exits on --help" do
      io = IO::Memory.new
      status = Process.run(
        "crystal",
        [
          "eval",
          "-Dspec",
          "require \"./src/main\"; Agentish::CLI.new.parse_args([\"--help\"])",
        ],
        output: io,
        error: io
      )

      status.exit_code.should eq(0)
      io.to_s.includes?("Usage:").should be_true
    end

    it "exits on --version" do
      io = IO::Memory.new
      status = Process.run(
        "crystal",
        [
          "eval",
          "-Dspec",
          "require \"./src/main\"; Agentish::CLI.new.parse_args([\"--version\"])",
        ],
        output: io,
        error: io
      )

      status.exit_code.should eq(0)
      io.to_s.includes?("agentish v").should be_true
    end
  end

  describe "#prompt_text" do
    it "returns inline prompt when set" do
      cli = Agentish::CLI.new
      cli.prompt = "Inline prompt"

      cli.prompt_text.should eq("Inline prompt")
    end

    it "reads prompt from file" do
      temp_file = File.tempfile("prompt", ".txt") do |file|
        file.print("Prompt from file")
      end

      begin
        cli = Agentish::CLI.new
        cli.prompt_file = temp_file.path

        cli.prompt_text.should eq("Prompt from file")
      ensure
        temp_file.delete
      end
    end

    it "prefers inline prompt over file" do
      cli = Agentish::CLI.new
      cli.prompt = "Inline"
      cli.prompt_file = "some_file.txt"

      cli.prompt_text.should eq("Inline")
    end
  end

  describe "#find_default_config" do
    it "returns nil when no config files exist" do
      cli = Agentish::CLI.new

      result = cli.find_default_config
      (result.nil? || result.is_a?(String)).should be_true
    end
  end
end

describe AgentKit::Agent do
  describe "#run_continue" do
    it "continues conversation without resetting history" do
      WebMock.reset

      call_count = 0
      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return do |_|
          call_count += 1
          HTTP::Client::Response.new(
            status: :ok,
            headers: HTTP::Headers{"Content-Type" => "application/json"},
            body: {
              id:      "chatcmpl-#{call_count}",
              object:  "chat.completion",
              created: 1699000000,
              model:   "gpt-4o",
              choices: [
                {
                  index:         0,
                  message:       {role: "assistant", content: "Response #{call_count}"},
                  finish_reason: "stop",
                },
              ],
              usage: {prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
            }.to_json
          )
        end

      config = AgentKit::Config.new(openai_api_key: "test-key")
      agent = AgentKit::Agent.new(config)

      result1 = agent.run("First message")
      result1.should eq("Response 1")

      agent.history.size.should eq(3)

      result2 = agent.run_continue("Second message")
      result2.should eq("Response 2")

      agent.history.size.should eq(5)

      result3 = agent.run_continue("Third message")
      result3.should eq("Response 3")

      agent.history.size.should eq(7)

      call_count.should eq(3)
    end

    it "preserves context between messages" do
      WebMock.reset

      messages_received = [] of Array(AgentKit::OpenAIApi::ChatMessage)

      WebMock.stub(:post, "https://api.openai.com/v1/chat/completions")
        .to_return do |request|
          body = if b = request.body
                   JSON.parse(b.gets_to_end)
                 else
                   raise "Request body should not be nil"
                 end
          msgs = body["messages"].as_a.map do |m|
            AgentKit::OpenAIApi::ChatMessage.from_json(m.to_json)
          end
          messages_received << msgs

          HTTP::Client::Response.new(
            status: :ok,
            headers: HTTP::Headers{"Content-Type" => "application/json"},
            body: {
              id:      "chatcmpl-test",
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
              usage: {prompt_tokens: 10, completion_tokens: 5, total_tokens: 15},
            }.to_json
          )
        end

      config = AgentKit::Config.new(openai_api_key: "test-key")
      agent = AgentKit::Agent.new(config)

      agent.run("Hello")
      agent.run_continue("How are you?")

      messages_received[0].size.should eq(2)
      messages_received[0][0].role.should eq("system")
      messages_received[0][1].role.should eq("user")
      messages_received[0][1].content.should eq("Hello")

      messages_received[1].size.should eq(4)
      messages_received[1][0].role.should eq("system")
      messages_received[1][1].role.should eq("user")
      messages_received[1][1].content.should eq("Hello")
      messages_received[1][2].role.should eq("assistant")
      messages_received[1][2].content.should eq("OK")
      messages_received[1][3].role.should eq("user")
      messages_received[1][3].content.should eq("How are you?")
    end
  end
end
