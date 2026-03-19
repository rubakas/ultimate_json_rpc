# frozen_string_literal: true

require "test_helper"
require "reclamo/extras/docs"
require "json"

class TestDocs < Minitest::Test
  def test_title_from_server_name
    server = Reclamo::Server.new(name: "Calculator API")
    server.expose(Calculator)
    md = Reclamo::Extras::Docs.new(server).to_markdown

    assert_match(/^# Calculator API/, md)
  end

  def test_default_title
    server = Reclamo::Server.new
    server.expose(Calculator)
    md = Reclamo::Extras::Docs.new(server).to_markdown

    assert_match(/^# API Reference/, md)
  end

  def test_includes_version
    server = Reclamo::Server.new(name: "API", version: "2.0")
    server.expose(Calculator)
    md = Reclamo::Extras::Docs.new(server).to_markdown

    assert_match(/\*\*Version:\*\* 2\.0/, md)
  end

  def test_includes_description
    server = Reclamo::Server.new(name: "API", description: "A math service")
    server.expose(Calculator)
    md = Reclamo::Extras::Docs.new(server).to_markdown

    assert_match(/A math service/, md)
  end

  def test_lists_methods
    server = Reclamo::Server.new
    server.expose(Calculator)
    md = Reclamo::Extras::Docs.new(server).to_markdown

    assert_match(/### `add`/, md)
    assert_match(/### `divide`/, md)
  end

  def test_method_description
    server = Reclamo::Server.new
    server.expose_method("ping", description: "Health check") { "pong" }
    md = Reclamo::Extras::Docs.new(server).to_markdown

    assert_match(/Health check/, md)
  end

  def test_params_table
    server = Reclamo::Server.new
    server.expose(Calculator)
    md = Reclamo::Extras::Docs.new(server).to_markdown

    assert_match(/\| `left` \| Yes \|/, md)
    assert_match(/\| `right` \| Yes \|/, md)
  end

  def test_params_with_schema_type
    server = Reclamo::Server.new
    server.expose_method("double", params_schema: { n: { "type" => "number" } }) { |n| n * 2 }
    md = Reclamo::Extras::Docs.new(server).to_markdown

    assert_match(/\| `n` \| No \| number \|/, md)
  end

  def test_return_type
    server = Reclamo::Server.new
    server.expose_method("add", returns: { "type" => "number" }) { |a, b| a + b }
    md = Reclamo::Extras::Docs.new(server).to_markdown

    assert_match(/\*\*Returns:\*\* `number`/, md)
  end

  def test_return_type_from_string_value
    server = Reclamo::Server.new
    server.expose_method("greet", returns: "string") { "hi" }
    assert_match(/\*\*Returns:\*\* `string`/, Reclamo::Extras::Docs.new(server).to_markdown)
  end

  def test_deprecated_method
    server = Reclamo::Server.new
    server.expose_method("old", deprecated: "Use new_method instead") { "old" }
    md = Reclamo::Extras::Docs.new(server).to_markdown

    assert_match(/Deprecated.*Use new_method instead/, md)
  end

  def test_deprecated_boolean
    server = Reclamo::Server.new
    server.expose_method("old", deprecated: true) { "old" }
    md = Reclamo::Extras::Docs.new(server).to_markdown

    assert_match(/Deprecated.*deprecated/, md)
  end

  def test_error_catalog
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }
    server.register_error(code: 42, message: "InsufficientFunds", description: "Account balance too low")
    md = Reclamo::Extras::Docs.new(server).to_markdown

    assert_match(/## Error Codes/, md)
    assert_match(/\| 42 \| InsufficientFunds \| Account balance too low \|/, md)
  end

  def test_pipe_in_error_description_is_escaped
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }
    server.register_error(code: 42, message: "Pipe|Error", description: "Contains | chars")
    md = Reclamo::Extras::Docs.new(server).to_markdown

    assert_match(/Pipe\\|Error/, md)
    assert_match(/Contains \\| chars/, md)
  end

  def test_newline_in_table_cell_is_escaped
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }
    server.register_error(code: 99, message: "Multi\nLine", description: "Desc\r\nHere")
    md = Reclamo::Extras::Docs.new(server).to_markdown

    assert_match(/Multi Line/, md)
    assert_match(/Desc Here/, md)
  end

  def test_no_errors_section_when_empty
    server = Reclamo::Server.new
    server.expose(Calculator)
    md = Reclamo::Extras::Docs.new(server).to_markdown

    refute_match(/Error Codes/, md)
  end

  def test_empty_server
    server = Reclamo::Server.new
    md = Reclamo::Extras::Docs.new(server).to_markdown

    assert_match(/# API Reference/, md)
    refute_match(/## Methods/, md)
  end

  def test_custom_json_adapter
    adapter = Module.new do
      def self.parse(str) = JSON.parse(str)
      def self.generate(obj) = JSON.generate(obj)
    end
    server = Reclamo::Server.new(json: adapter)
    server.expose(Calculator)
    md = Reclamo::Extras::Docs.new(server, json: adapter).to_markdown

    assert_match(/### `add`/, md)
  end

  def test_full_document_structure
    server = Reclamo::Server.new(name: "Math API", version: "1.0", description: "A math service")
    server.expose(Calculator, descriptions: { add: "Add two numbers" },
                              params_schema: { add: { left: { "type" => "number" }, right: { "type" => "number" } } },
                              returns: { add: { "type" => "number" } })
    server.register_error(code: 42, message: "Overflow", description: "Result too large")
    md = Reclamo::Extras::Docs.new(server).to_markdown

    assert_match(/# Math API/, md)
    assert_match(/A math service/, md)
    assert_match(/Version.*1\.0/, md)
    assert_match(/## Methods/, md)
    assert_match(/### `add`/, md)
    assert_match(/Add two numbers/, md)
    assert_match(/number/, md)
    assert_match(/## Error Codes/, md)
    assert_match(/42.*Overflow/, md)
  end
end

class TestDocsDiscoverGuard < Minitest::Test
  def test_docs_raises_when_discover_blocked_by_middleware
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.use(only: "rpc.discover") { |_req, _nxt| raise Reclamo::Core::InvalidRequest, "blocked" }

    error = assert_raises(RuntimeError) { Reclamo::Extras::Docs.new(server).to_markdown }
    assert_match(/rpc\.discover returned an error/, error.message)
  end
end
