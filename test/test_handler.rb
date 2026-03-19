# frozen_string_literal: true

require "test_helper"
require "json"

class TestHandler < Minitest::Test
  def test_method_query
    handler = Reclamo::Handler.new
    handler.expose(Calculator)

    assert handler.method?("add")
    refute handler.method?("nonexistent")
  end

  def test_handler_size
    handler = Reclamo::Handler.new
    assert_equal 0, handler.size

    handler.expose(Calculator)
    assert_equal 2, handler.size

    handler.expose_method("ping") { "pong" }
    assert_equal 3, handler.size
  end

  def test_expose_rejects_rpc_namespace
    handler = Reclamo::Handler.new

    assert_raises(ArgumentError) { handler.expose(Calculator, namespace: "rpc") }
  end

  def test_does_not_expose_inherited_object_methods
    handler = Reclamo::Handler.new
    handler.expose(Greeter.new("Hi"))

    refute handler.method?("class")
    refute handler.method?("object_id")
  end

  def test_duplicate_expose_raises
    handler = Reclamo::Handler.new
    handler.expose(Calculator)

    assert_raises(ArgumentError) { handler.expose(Calculator) }
  end

  def test_duplicate_expose_method_raises
    handler = Reclamo::Handler.new
    handler.expose_method("foo") { "bar" }

    assert_raises(ArgumentError) { handler.expose_method("foo") { "baz" } }
  end

  def test_duplicate_across_expose_and_expose_method
    handler = Reclamo::Handler.new
    handler.expose(Calculator)

    assert_raises(ArgumentError) { handler.expose_method("add") { 1 } }
  end

  def test_same_method_name_different_namespace_ok
    handler = Reclamo::Handler.new
    handler.expose(Calculator, namespace: "a")
    handler.expose(Calculator, namespace: "b")

    assert handler.method?("a.add")
    assert handler.method?("b.add")
  end

  def test_empty_string_namespace_treated_as_no_namespace
    handler = Reclamo::Handler.new
    handler.expose(Calculator, namespace: "")

    assert handler.method?("add")
    refute handler.method?(".add")
  end

  def test_symbol_namespace
    handler = Reclamo::Handler.new
    handler.expose(Calculator, namespace: :math)

    assert handler.method?("math.add")
    assert handler.method?("math.divide")
  end

  def test_expose_target_with_no_methods
    handler = Reclamo::Handler.new
    _, err = capture_io { handler.expose(Object.new) }

    assert_equal 0, handler.size
    assert_empty handler.methods_list
    assert_match(/registered 0 methods/, err)
  end

  def test_expose_nil_raises
    handler = Reclamo::Handler.new

    assert_raises(ArgumentError) { handler.expose(nil) }
  end

  def test_methods_list_is_sorted
    handler = Reclamo::Handler.new
    handler.expose_method("zebra") { nil }
    handler.expose_method("alpha") { nil }
    handler.expose_method("middle") { nil }

    assert_equal %w[alpha middle zebra], handler.methods_list
  end

  def test_methods_info_for_required_positional_params
    handler = Reclamo::Handler.new
    handler.expose(Calculator)
    add_info = handler.methods_info.find { |m| m["name"] == "add" }

    assert_equal(%w[left right], add_info["params"].map { |p| p["name"] })
    assert(add_info["params"].all? { |p| p["required"] })
  end

  def test_methods_info_marks_keyword_params
    handler = Reclamo::Handler.new
    handler.expose(Greeter.new("Hi"))
    greet_info = handler.methods_info.find { |m| m["name"] == "greet" }

    assert_equal true, greet_info["params"][0]["keyword"]
  end

  def test_methods_info_omits_params_when_none
    handler = Reclamo::Handler.new
    handler.expose_method("ping") { "pong" }

    refute handler.methods_info[0].key?("params")
  end

  def test_methods_info_block_params_are_optional
    handler = Reclamo::Handler.new
    handler.expose_method("greet") { |name, greeting| "#{greeting}, #{name}!" }
    greet_info = handler.methods_info[0]

    assert_equal 2, greet_info["params"].size
    refute greet_info["params"][0].key?("required")
  end
end

class TestHandlerEdgeCases < Minitest::Test
  def test_method_not_found_exposes_method_name
    handler = Reclamo::Handler.new
    err = assert_raises(Reclamo::MethodNotFound) { handler.call("missing", nil) }

    assert_equal "missing", err.method_name
    assert_equal "Method not found: missing", err.message
  end

  def test_invoke_with_invalid_params_type_raises
    handler = Reclamo::Handler.new
    handler.expose(Calculator)

    assert_raises(ArgumentError) { handler.call("add", "not valid") }
  end

  def test_call_with_hash_params_converts_keys_to_symbols
    handler = Reclamo::Handler.new
    handler.expose(Greeter.new("Hi"))
    result = handler.call("greet", { "name" => "World" })

    assert_equal "Hi, World!", result
  end

  def test_call_with_nil_params
    handler = Reclamo::Handler.new
    handler.expose(Greeter.new("Hi"))
    result = handler.call("hello", nil)

    assert_equal "hello", result
  end
end

class TestHandlerFreeze < Minitest::Test
  def test_frozen_handler_rejects_expose
    handler = Reclamo::Handler.new
    handler.freeze

    assert_raises(FrozenError) { handler.expose(Calculator) }
  end

  def test_frozen_handler_rejects_expose_method
    handler = Reclamo::Handler.new
    handler.freeze

    assert_raises(FrozenError) { handler.expose_method("foo") { "bar" } }
  end

  def test_frozen_handler_allows_calls
    handler = Reclamo::Handler.new
    handler.expose(Calculator)
    handler.freeze

    assert_equal 5, handler.call("add", [2, 3])
  end

  def test_frozen_handler_allows_queries
    handler = Reclamo::Handler.new
    handler.expose(Calculator)
    handler.freeze

    assert handler.method?("add")
    assert_equal 2, handler.size
    refute_predicate handler, :empty?
    assert_equal %w[add divide], handler.methods_list
  end
end

class TestHandlerParamDescriptors < Minitest::Test
  def test_variadic_keyword_params
    handler = Reclamo::Handler.new
    handler.expose_method("flexible") { |**opts| opts }
    info = handler.methods_info.find { |m| m["name"] == "flexible" }

    assert_equal 1, info["params"].size
    assert_equal true, info["params"][0]["variadic"]
    assert_equal true, info["params"][0]["keyword"]
    assert_equal "opts", info["params"][0]["name"]
  end

  def test_mixed_positional_and_keyword_params
    handler = Reclamo::Handler.new
    handler.expose_method("mixed") { |a, b:, c: nil| [a, b, c] }
    info = handler.methods_info.find { |m| m["name"] == "mixed" }

    assert_equal 3, info["params"].size
    refute info["params"][0].key?("keyword")
    assert_equal true, info["params"][1]["keyword"]
    assert_equal true, info["params"][1]["required"]
    assert_equal true, info["params"][2]["keyword"]
    refute info["params"][2].key?("required")
  end

  def test_variadic_positional_params
    handler = Reclamo::Handler.new
    handler.expose_method("varargs") { |*args| args }
    info = handler.methods_info.find { |m| m["name"] == "varargs" }

    assert_equal 1, info["params"].size
    assert_equal true, info["params"][0]["variadic"]
    assert_equal "args", info["params"][0]["name"]
    refute info["params"][0].key?("keyword")
  end
end

class TestHandlerDangerousMethods < Minitest::Test
  %w[eval instance_eval class_eval module_eval send public_send __send__ system exec spawn fork
     define_method remove_method binding method_missing respond_to_missing?
     exit exit! abort require require_relative load open].each do |name|
    safe_name = name.tr("?", "_q")
    define_method("test_expose_rejects_#{safe_name}") do
      handler = Reclamo::Handler.new
      err = assert_raises(ArgumentError) { handler.expose_method(name) { nil } }
      assert_match(/dangerous/, err.message)
    end
  end

  def test_expose_rejects_namespaced_dangerous_method
    handler = Reclamo::Handler.new
    err = assert_raises(ArgumentError) { handler.expose_method("ns.eval") { nil } }
    assert_match(/dangerous/, err.message)
  end

  def test_expose_rejects_dangerous_from_target
    target = Object.new
    target.define_singleton_method(:eval) { "nope" }
    handler = Reclamo::Handler.new
    assert_raises(ArgumentError) { handler.expose(target) }
  end

  def test_expose_rejects_dangerous_namespace
    handler = Reclamo::Handler.new
    target = Object.new
    target.define_singleton_method(:safe) { "ok" }
    err = assert_raises(ArgumentError) { handler.expose(target, namespace: "eval") }
    assert_match(/dangerous/, err.message)
  end

  def test_expose_allows_safe_name_evaluate
    handler = Reclamo::Handler.new
    handler.expose_method("evaluate") { "ok" }
    assert handler.method?("evaluate")
  end

  %w[instance_variable_get instance_variable_set const_get const_set method].each do |dangerous|
    define_method("test_expose_method_#{dangerous}_is_blocked") do
      handler = Reclamo::Handler.new
      assert_raises(ArgumentError) { handler.expose_method(dangerous) { nil } }
    end
  end
end

class TestHandlerFreezeTargetArrays < Minitest::Test
  def test_target_arrays_frozen_after_freeze
    handler = Reclamo::Handler.new
    handler.expose(Calculator)
    handler.freeze

    assert_predicate handler, :frozen?
  end
end
