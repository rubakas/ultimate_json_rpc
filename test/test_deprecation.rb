# frozen_string_literal: true

require "test_helper"
require "support/discover_helper"
require "json"

class TestMethodDeprecation < Minitest::Test
  include DiscoverHelper

  def test_expose_method_deprecated_boolean
    server = Reclamo::Server.new
    server.expose_method("old_add", deprecated: true) { |a, b| a + b }
    method_info = discover_methods(server).find { |m| m["name"] == "old_add" }

    assert_equal true, method_info["deprecated"]
  end

  def test_expose_method_deprecated_string
    server = Reclamo::Server.new
    server.expose_method("old_add", deprecated: "Use add_v2 instead") { |a, b| a + b }
    method_info = discover_methods(server).find { |m| m["name"] == "old_add" }

    assert_equal "Use add_v2 instead", method_info["deprecated"]
  end

  def test_expose_with_deprecated_hash
    server = Reclamo::Server.new
    server.expose(Calculator, deprecated: { add: true, divide: "Use safe_divide" })
    methods = discover_methods(server)

    assert_equal true, methods.find { |m| m["name"] == "add" }["deprecated"]
    assert_equal "Use safe_divide", methods.find { |m| m["name"] == "divide" }["deprecated"]
  end

  def test_expose_with_deprecated_string_keys
    server = Reclamo::Server.new
    server.expose(Calculator, deprecated: { "add" => true })

    assert_equal true, discover_methods(server).find { |m| m["name"] == "add" }["deprecated"]
  end

  def test_expose_with_deprecated_and_namespace
    server = Reclamo::Server.new
    server.expose(Calculator, namespace: "math", deprecated: { add: "Legacy" })
    method_info = discover_methods(server).find { |m| m["name"] == "math.add" }

    assert_equal "Legacy", method_info["deprecated"]
  end

  def test_deprecated_false_omits_key
    server = Reclamo::Server.new
    server.expose_method("m", deprecated: false) { "ok" }

    refute discover_methods(server).find { |m| m["name"] == "m" }.key?("deprecated")
  end

  def test_omits_deprecated_when_not_set
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }

    refute discover_methods(server).find { |m| m["name"] == "ping" }.key?("deprecated")
  end

  def test_deprecated_methods_still_work
    server = Reclamo::Server.new
    server.expose_method("old_add", deprecated: true) { |a, b| a + b }

    request = { "jsonrpc" => "2.0", "method" => "old_add", "params" => [2, 3], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))
    assert_equal 5, response["result"]
  end

  def test_deprecated_survives_freeze
    server = Reclamo::Server.new
    server.expose_method("old", deprecated: true) { "old" }
    server.freeze

    assert_equal true, discover_methods(server).find { |m| m["name"] == "old" }["deprecated"]
  end

  def test_deprecated_with_description_and_returns
    server = Reclamo::Server.new
    server.expose_method("old", description: "Legacy", returns: { "type" => "string" }, deprecated: "Use new") { "x" }
    method_info = discover_methods(server).find { |m| m["name"] == "old" }

    assert_equal "Legacy", method_info["description"]
    assert_equal "string", method_info["result"]["type"]
    assert_equal "Use new", method_info["deprecated"]
  end
end
