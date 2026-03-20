# frozen_string_literal: true

require "test_helper"
require "support/discover_helper"
require "json"

class TestMethodDeprecation < Minitest::Test
  include DiscoverHelper

  def test_expose_method_deprecated_boolean
    server = UltimateJsonRpc::Server.new
    server.expose_method("old_add", deprecated: true) { |a, b| a + b }
    method_info = discover_methods(server).find { |m| m["name"] == "old_add" }

    assert_equal true, method_info["deprecated"]
  end

  def test_expose_method_deprecated_string
    server = UltimateJsonRpc::Server.new
    server.expose_method("old_add", deprecated: "Use add_v2 instead") { |a, b| a + b }
    method_info = discover_methods(server).find { |m| m["name"] == "old_add" }

    assert_equal "Use add_v2 instead", method_info["deprecated"]
  end

  def test_expose_with_deprecated_hash
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator, deprecated: { add: true, divide: "Use safe_divide" })
    methods = discover_methods(server)

    assert_equal true, methods.find { |m| m["name"] == "add" }["deprecated"]
    assert_equal "Use safe_divide", methods.find { |m| m["name"] == "divide" }["deprecated"]
  end

  def test_expose_with_deprecated_string_keys
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator, deprecated: { "add" => true })

    assert_equal true, discover_methods(server).find { |m| m["name"] == "add" }["deprecated"]
  end

  def test_expose_with_deprecated_and_namespace
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator, namespace: "math", deprecated: { add: "Legacy" })
    method_info = discover_methods(server).find { |m| m["name"] == "math.add" }

    assert_equal "Legacy", method_info["deprecated"]
  end

  def test_deprecated_false_omits_key
    server = UltimateJsonRpc::Server.new
    server.expose_method("m", deprecated: false) { "ok" }

    refute discover_methods(server).find { |m| m["name"] == "m" }.key?("deprecated")
  end

  def test_omits_deprecated_when_not_set
    server = UltimateJsonRpc::Server.new
    server.expose_method("ping") { "pong" }

    refute discover_methods(server).find { |m| m["name"] == "ping" }.key?("deprecated")
  end

  def test_deprecated_methods_still_work
    server = UltimateJsonRpc::Server.new
    server.expose_method("old_add", deprecated: true) { |a, b| a + b }

    request = { "jsonrpc" => "2.0", "method" => "old_add", "params" => [2, 3], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))
    assert_equal 5, response["result"]
  end

  def test_deprecated_survives_freeze
    server = UltimateJsonRpc::Server.new
    server.expose_method("old", deprecated: true) { "old" }
    server.freeze

    assert_equal true, discover_methods(server).find { |m| m["name"] == "old" }["deprecated"]
  end

  def test_deprecated_with_description_and_returns
    server = UltimateJsonRpc::Server.new
    server.expose_method("old", description: "Legacy", returns: { "type" => "string" }, deprecated: "Use new") { "x" }
    method_info = discover_methods(server).find { |m| m["name"] == "old" }

    assert_equal "Legacy", method_info["description"]
    assert_equal "string", method_info["result"]["type"]
    assert_equal "Use new", method_info["deprecated"]
  end
end

class TestStoreMetadataScalarGuard < Minitest::Test
  def test_expose_with_scalar_deprecated_does_not_crash
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator, deprecated: true)

    assert server.method?("add")
  end

  def test_expose_with_string_deprecated_does_not_crash
    server = UltimateJsonRpc::Server.new
    server.expose(Calculator, deprecated: "use v2")

    assert server.method?("add")
  end
end

class TestDeprecatedNormalizationViaExpose < Minitest::Test
  include DiscoverHelper

  def test_deprecated_hash_string_values_normalized
    mod = Module.new do
      def self.alpha
        "a"
      end

      def self.beta
        "b"
      end
    end

    server = UltimateJsonRpc::Server.new
    server.expose(mod, deprecated: { alpha: true, beta: :use_gamma })

    methods = discover_methods(server)
    alpha = methods.find { |m| m["name"] == "alpha" }
    beta = methods.find { |m| m["name"] == "beta" }

    assert_equal true, alpha["deprecated"]
    assert_equal "use_gamma", beta["deprecated"]
  end
end
