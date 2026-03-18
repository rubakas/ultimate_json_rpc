# frozen_string_literal: true

require "test_helper"
require "json"

class TestParamValidationType < Minitest::Test
  def test_string_type_passes
    server = build_server("greet", params_schema: { name: { "type" => "string" } }) { |name| "Hi #{name}" }

    assert_success server, "greet", ["Alice"]
  end

  def test_string_type_fails
    server = build_server("greet", params_schema: { name: { "type" => "string" } }) { |name| "Hi #{name}" }

    assert_invalid_params server, "greet", [42], /parameter 'name' must be string, got integer/
  end

  def test_number_type_accepts_integer
    server = build_server("double", params_schema: { n: { "type" => "number" } }) { |n| n * 2 }

    assert_success server, "double", [5]
  end

  def test_number_type_accepts_float
    server = build_server("double", params_schema: { n: { "type" => "number" } }) { |n| n * 2 }

    assert_success server, "double", [3.14]
  end

  def test_number_type_fails
    server = build_server("double", params_schema: { n: { "type" => "number" } }) { |n| n * 2 }

    assert_invalid_params server, "double", ["five"], /parameter 'n' must be number, got string/
  end

  def test_integer_type_passes
    server = build_server("inc", params_schema: { n: { "type" => "integer" } }) { |n| n + 1 }

    assert_success server, "inc", [5]
  end

  def test_integer_type_rejects_float
    server = build_server("inc", params_schema: { n: { "type" => "integer" } }) { |n| n + 1 }

    assert_invalid_params server, "inc", [3.14], /parameter 'n' must be integer, got number/
  end

  def test_boolean_type_passes
    server = build_server("toggle", params_schema: { flag: { "type" => "boolean" } }) { |flag| !flag } # rubocop:disable Style/SymbolProc

    assert_success server, "toggle", [true]
  end

  def test_boolean_type_fails
    server = build_server("toggle", params_schema: { flag: { "type" => "boolean" } }) { |flag| !flag } # rubocop:disable Style/SymbolProc

    assert_invalid_params server, "toggle", [1], /parameter 'flag' must be boolean, got integer/
  end

  def test_array_type_passes
    server = build_server("sum", params_schema: { nums: { "type" => "array" } }) { |nums| nums.sum } # rubocop:disable Style/SymbolProc

    assert_success server, "sum", [[1, 2, 3]]
  end

  def test_array_type_fails
    server = build_server("sum", params_schema: { nums: { "type" => "array" } }) { |nums| nums.sum } # rubocop:disable Style/SymbolProc

    assert_invalid_params server, "sum", ["oops"], /parameter 'nums' must be array, got string/
  end

  def test_object_type_passes
    server = build_server("keys", params_schema: { obj: { "type" => "object" } }) { |obj| obj.keys } # rubocop:disable Style/SymbolProc

    assert_success server, "keys", [{ "a" => 1 }]
  end

  def test_object_type_fails
    server = build_server("keys", params_schema: { obj: { "type" => "object" } }) { |obj| obj.keys } # rubocop:disable Style/SymbolProc

    assert_invalid_params server, "keys", [[1]], /parameter 'obj' must be object, got array/
  end

  def test_null_type_passes
    server = build_server("check", params_schema: { val: { "type" => "null" } }) { |val| val.nil? } # rubocop:disable Style/SymbolProc

    assert_success server, "check", [nil]
  end

  def test_null_type_fails
    server = build_server("check", params_schema: { val: { "type" => "null" } }) { |val| val.nil? } # rubocop:disable Style/SymbolProc

    assert_invalid_params server, "check", [0], /parameter 'val' must be null, got integer/
  end

  private

  def build_server(name, **, &)
    server = Reclamo::Server.new
    server.expose_method(name, **, &)
    server
  end

  def call(server, method, params)
    request = { "jsonrpc" => "2.0", "method" => method, "params" => params, "id" => 1 }
    JSON.parse(server.handle(JSON.generate(request)))
  end

  def assert_success(server, method, params)
    response = call(server, method, params)

    assert response.key?("result"), "expected success, got: #{response.inspect}"
  end

  def assert_invalid_params(server, method, params, message_pattern)
    response = call(server, method, params)

    assert_equal Reclamo::INVALID_PARAMS, response.dig("error", "code")
    assert_match message_pattern, response.dig("error", "data")
  end
end

class TestParamValidationEnum < Minitest::Test
  def test_enum_passes
    server = Reclamo::Server.new
    server.expose_method("color", params_schema: { c: { "enum" => %w[red green blue] } }) { |c| c }
    response = call(server, "color", ["red"])

    assert_equal "red", response["result"]
  end

  def test_enum_fails
    server = Reclamo::Server.new
    server.expose_method("color", params_schema: { c: { "enum" => %w[red green blue] } }) { |c| c }
    response = call(server, "color", ["yellow"])

    assert_equal Reclamo::INVALID_PARAMS, response.dig("error", "code")
    assert_match(/parameter 'c' must be one of/, response.dig("error", "data"))
  end

  def test_enum_with_type
    server = Reclamo::Server.new
    server.expose_method("level", params_schema: { n: { "type" => "integer", "enum" => [1, 2, 3] } }) { |n| n }
    response = call(server, "level", ["not_int"])

    assert_equal Reclamo::INVALID_PARAMS, response.dig("error", "code")
    assert_match(/must be integer/, response.dig("error", "data"))
  end

  def test_type_passes_but_enum_fails
    server = Reclamo::Server.new
    server.expose_method("level", params_schema: { n: { "type" => "integer", "enum" => [1, 2, 3] } }) { |n| n }
    response = call(server, "level", [99])

    assert_equal Reclamo::INVALID_PARAMS, response.dig("error", "code")
    assert_match(/must be one of/, response.dig("error", "data"))
  end

  private

  def call(server, method, params)
    request = { "jsonrpc" => "2.0", "method" => method, "params" => params, "id" => 1 }
    JSON.parse(server.handle(JSON.generate(request)))
  end
end

class TestParamValidationKeywordParams < Minitest::Test
  def test_keyword_params_pass
    server = Reclamo::Server.new
    server.expose_method("greet", params_schema: { name: { "type" => "string" } }) { |name:| "Hi #{name}" }
    response = call(server, "greet", { "name" => "Alice" })

    assert_equal "Hi Alice", response["result"]
  end

  def test_keyword_params_fail
    server = Reclamo::Server.new
    server.expose_method("greet", params_schema: { name: { "type" => "string" } }) { |name:| "Hi #{name}" }
    response = call(server, "greet", { "name" => 123 })

    assert_equal Reclamo::INVALID_PARAMS, response.dig("error", "code")
    assert_match(/parameter 'name' must be string/, response.dig("error", "data"))
  end

  private

  def call(server, method, params)
    request = { "jsonrpc" => "2.0", "method" => method, "params" => params, "id" => 1 }
    JSON.parse(server.handle(JSON.generate(request)))
  end
end

class TestParamValidationExpose < Minitest::Test
  def test_expose_with_params_schema
    server = Reclamo::Server.new
    server.expose(Calculator, params_schema: {
                    add: { left: { "type" => "number" }, right: { "type" => "number" } }
                  })
    response = call(server, "add", ["not_a_number", 2])

    assert_equal Reclamo::INVALID_PARAMS, response.dig("error", "code")
    assert_match(/parameter 'left' must be number/, response.dig("error", "data"))
  end

  def test_expose_with_params_schema_passes
    server = Reclamo::Server.new
    server.expose(Calculator, params_schema: {
                    add: { left: { "type" => "number" }, right: { "type" => "number" } }
                  })
    response = call(server, "add", [2, 3])

    assert_equal 5, response["result"]
  end

  def test_expose_with_namespace
    server = Reclamo::Server.new
    server.expose(Calculator, namespace: "math", params_schema: {
                    add: { left: { "type" => "number" }, right: { "type" => "number" } }
                  })
    response = call(server, "math.add", ["bad", 2])

    assert_equal Reclamo::INVALID_PARAMS, response.dig("error", "code")
  end

  def test_expose_string_keys
    server = Reclamo::Server.new
    server.expose(Calculator, params_schema: {
                    "add" => { "left" => { "type" => "number" }, "right" => { "type" => "number" } }
                  })
    response = call(server, "add", ["nope", 2])

    assert_equal Reclamo::INVALID_PARAMS, response.dig("error", "code")
  end

  private

  def call(server, method, params)
    request = { "jsonrpc" => "2.0", "method" => method, "params" => params, "id" => 1 }
    JSON.parse(server.handle(JSON.generate(request)))
  end
end

class TestParamValidationEdgeCases < Minitest::Test
  def test_no_schema_no_validation
    server = Reclamo::Server.new
    server.expose_method("echo") { |x| x }
    response = call(server, "echo", ["anything"])

    assert_equal "anything", response["result"]
  end

  def test_partial_schema_only_validates_specified
    server = Reclamo::Server.new
    server.expose_method("pair", params_schema: { a: { "type" => "string" } }) { |a, b| [a, b] }
    response = call(server, "pair", ["hello", 42])

    assert_equal ["hello", 42], response["result"]
  end

  def test_partial_schema_catches_violation
    server = Reclamo::Server.new
    server.expose_method("pair", params_schema: { a: { "type" => "string" } }) { |a, b| [a, b] }
    response = call(server, "pair", [42, "hello"])

    assert_equal Reclamo::INVALID_PARAMS, response.dig("error", "code")
  end

  def test_nil_params_skips_validation
    server = Reclamo::Server.new
    server.expose_method("ping", params_schema: { x: { "type" => "string" } }) { "pong" }
    response = call(server, "ping", nil)

    assert_equal "pong", response["result"]
  end

  def test_unknown_type_in_schema_skips_check
    server = Reclamo::Server.new
    server.expose_method("echo", params_schema: { x: { "type" => "custom" } }) { |x| x }
    response = call(server, "echo", [42])

    assert_equal 42, response["result"]
  end

  def test_validation_with_callable
    doubler = ->(n) { n * 2 }
    server = Reclamo::Server.new
    server.expose_method("double", doubler, params_schema: { n: { "type" => "number" } })
    response = call(server, "double", ["bad"])

    assert_equal Reclamo::INVALID_PARAMS, response.dig("error", "code")
  end

  def test_schema_survives_freeze
    server = Reclamo::Server.new
    server.expose_method("add", params_schema: { a: { "type" => "number" } }) { |a| a }
    server.freeze
    response = call(server, "add", ["bad"])

    assert_equal Reclamo::INVALID_PARAMS, response.dig("error", "code")
  end

  private

  def call(server, method, params)
    req = { "jsonrpc" => "2.0", "method" => method, "id" => 1 }
    req["params"] = params if params
    JSON.parse(server.handle(JSON.generate(req)))
  end
end

class TestParamValidationDiscover < Minitest::Test
  include DiscoverHelper

  def test_schema_appears_in_discover
    server = Reclamo::Server.new
    server.expose_method("add", params_schema: {
                           a: { "type" => "number" }, b: { "type" => "number" }
                         }) { |a, b| a + b }
    method_info = discover_methods(server).find { |m| m["name"] == "add" }

    assert_equal({ "type" => "number" }, method_info["params"][0]["schema"])
    assert_equal({ "type" => "number" }, method_info["params"][1]["schema"])
  end

  def test_schema_omitted_when_not_set
    server = Reclamo::Server.new
    server.expose_method("ping") { "pong" }
    method_info = discover_methods(server).find { |m| m["name"] == "ping" }

    assert_nil method_info["params"]
  end

  def test_partial_schema_in_discover
    server = Reclamo::Server.new
    server.expose_method("pair", params_schema: { a: { "type" => "string" } }) { |a, b| [a, b] }
    method_info = discover_methods(server).find { |m| m["name"] == "pair" }

    assert_equal({ "type" => "string" }, method_info["params"][0]["schema"])
    refute method_info["params"][1].key?("schema")
  end

  def test_expose_schema_in_discover
    server = Reclamo::Server.new
    server.expose(Calculator, params_schema: {
                    add: { left: { "type" => "number" }, right: { "type" => "number" } }
                  })
    method_info = discover_methods(server).find { |m| m["name"] == "add" }

    assert_equal({ "type" => "number" }, method_info["params"][0]["schema"])
  end

  def test_schema_with_enum_in_discover
    server = Reclamo::Server.new
    server.expose_method("color", params_schema: {
                           c: { "type" => "string", "enum" => %w[red green blue] }
                         }) { |c| c }
    param = discover_methods(server).find { |m| m["name"] == "color" }["params"][0]

    assert_equal "string", param["schema"]["type"]
    assert_equal %w[red green blue], param["schema"]["enum"]
  end
end
