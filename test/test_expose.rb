# frozen_string_literal: true

require "test_helper"
require "json"

class TestServerExposeMethod < Minitest::Test
  def test_expose_block_as_method
    server = Reclamo::Server.new
    server.expose_method("double") { |num| num * 2 }

    request = { "jsonrpc" => "2.0", "method" => "double", "params" => [5], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal 10, response["result"]
  end

  def test_expose_block_with_keyword_params
    server = Reclamo::Server.new
    server.expose_method("greet") { |name:, greeting: "Hello"| "#{greeting}, #{name}!" }

    request = { "jsonrpc" => "2.0", "method" => "greet",
                "params" => { "name" => "World" }, "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal "Hello, World!", response["result"]
  end

  def test_expose_method_returns_self
    server = Reclamo::Server.new

    assert_equal server, server.expose_method("noop") { nil }
  end

  def test_expose_method_rejects_rpc_prefix
    server = Reclamo::Server.new

    assert_raises(ArgumentError) do
      server.expose_method("rpc.foo") { "bar" }
    end
  end

  def test_expose_method_without_block_raises
    handler = Reclamo::Core::Handler.new

    assert_raises(ArgumentError) { handler.expose_method("foo") }
  end

  def test_expose_method_with_symbol_name
    server = Reclamo::Server.new
    server.expose_method(:double) { |n| n * 2 }

    request = { "jsonrpc" => "2.0", "method" => "double", "params" => [5], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal 10, response["result"]
    assert_includes server.methods_list, "double"
  end

  def test_expose_method_rejects_empty_name
    server = Reclamo::Server.new

    assert_raises(ArgumentError) do
      server.expose_method("") { "hidden" }
    end
  end

  def test_expose_method_with_lambda
    server = Reclamo::Server.new
    doubler = ->(n) { n * 2 }
    server.expose_method("double", doubler)

    request = { "jsonrpc" => "2.0", "method" => "double", "params" => [5], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal 10, response["result"]
  end

  def test_expose_method_with_method_object
    server = Reclamo::Server.new
    server.expose_method("add", Calculator.method(:add))

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [2, 3], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal 5, response["result"]
  end

  def test_expose_method_rejects_both_callable_and_block
    server = Reclamo::Server.new

    assert_raises(ArgumentError) do
      server.expose_method("double", ->(n) { n * 2 }) { |n| n * 3 }
    end
  end

  def test_expose_method_rejects_neither_callable_nor_block
    server = Reclamo::Server.new

    assert_raises(ArgumentError) { server.expose_method("empty") }
  end

  def test_expose_method_rejects_non_callable
    server = Reclamo::Server.new

    assert_raises(ArgumentError) { server.expose_method("bad", "not callable") }
  end
end

class TestServerMethodFiltering < Minitest::Test
  def test_expose_only
    server = Reclamo::Server.new
    server.expose(Calculator, only: [:add])

    assert_includes server.methods_list, "add"
    refute_includes server.methods_list, "divide"
  end

  def test_expose_except
    server = Reclamo::Server.new
    server.expose(Calculator, except: [:divide])

    assert_includes server.methods_list, "add"
    refute_includes server.methods_list, "divide"
  end

  def test_expose_only_with_strings
    server = Reclamo::Server.new
    server.expose(Calculator, only: ["add"])

    assert_includes server.methods_list, "add"
    refute_includes server.methods_list, "divide"
  end

  def test_expose_only_and_except_raises
    server = Reclamo::Server.new

    assert_raises(ArgumentError) do
      server.expose(Calculator, only: [:add], except: [:divide])
    end
  end

  def test_expose_only_with_namespace
    server = Reclamo::Server.new
    server.expose(Calculator, namespace: "math", only: [:add])

    assert_includes server.methods_list, "math.add"
    refute_includes server.methods_list, "math.divide"
  end

  def test_filtered_method_returns_not_found
    server = Reclamo::Server.new
    server.expose(Calculator, only: [:add])

    request = { "jsonrpc" => "2.0", "method" => "divide", "params" => [10, 2], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_601, response["error"]["code"])
  end

  def test_expose_only_with_single_symbol
    server = Reclamo::Server.new
    server.expose(Calculator, only: :add)

    assert_includes server.methods_list, "add"
    refute_includes server.methods_list, "divide"
  end

  def test_expose_only_with_no_matches
    server = Reclamo::Server.new
    _, err = capture_io { server.expose(Calculator, only: [:nonexistent]) }

    assert_equal 0, server.size
    assert_match(/registered 0 methods/, err)
  end

  def test_expose_except_with_single_symbol
    server = Reclamo::Server.new
    server.expose(Calculator, except: :divide)

    assert_includes server.methods_list, "add"
    refute_includes server.methods_list, "divide"
  end
end

class TestCallableMethodsNameOverride < Minitest::Test
  def test_module_with_self_name_is_exposed
    mod = Module.new do
      def self.name
        "CustomModule"
      end

      def self.greet
        "hello"
      end
    end

    server = Reclamo::Server.new
    server.expose(mod)

    assert server.method?("name"), "Module.name should be exposed"
    assert server.method?("greet"), "Module.greet should be exposed"
  end

  def test_class_with_self_name_is_exposed
    klass = Class.new do
      def self.name
        "CustomClass"
      end

      def self.compute
        42
      end
    end

    server = Reclamo::Server.new
    server.expose(klass)

    assert server.method?("name"), "Class.name should be exposed"
    assert server.method?("compute"), "Class.compute should be exposed"
  end
end
