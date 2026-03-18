# frozen_string_literal: true

require "test_helper"

class TestRequestValidation < Minitest::Test
  def test_valid_request
    data = { "jsonrpc" => "2.0", "method" => "foo", "id" => 1 }
    request = Reclamo::Request.new(data)

    assert_equal "foo", request.method_name
    assert_equal 1, request.id
    assert_nil request.params
  end

  def test_valid_request_with_array_params
    data = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 }
    request = Reclamo::Request.new(data)

    assert_equal [1, 2], request.params
  end

  def test_valid_request_with_hash_params
    data = { "jsonrpc" => "2.0", "method" => "greet", "params" => { "name" => "World" }, "id" => 1 }
    request = Reclamo::Request.new(data)

    assert_equal({ "name" => "World" }, request.params)
  end

  def test_rejects_non_hash_data
    assert_raises(Reclamo::InvalidRequest) { Reclamo::Request.new("string") }
    assert_raises(Reclamo::InvalidRequest) { Reclamo::Request.new([1, 2]) }
    assert_raises(Reclamo::InvalidRequest) { Reclamo::Request.new(nil) }
    assert_raises(Reclamo::InvalidRequest) { Reclamo::Request.new(42) }
  end

  def test_rejects_missing_jsonrpc
    assert_raises(Reclamo::InvalidRequest) do
      Reclamo::Request.new({ "method" => "foo", "id" => 1 })
    end
  end

  def test_rejects_wrong_jsonrpc_version
    assert_raises(Reclamo::InvalidRequest) do
      Reclamo::Request.new({ "jsonrpc" => "1.0", "method" => "foo", "id" => 1 })
    end
  end

  def test_rejects_non_string_method
    assert_raises(Reclamo::InvalidRequest) do
      Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => 42, "id" => 1 })
    end
  end

  def test_rejects_empty_method
    assert_raises(Reclamo::InvalidRequest) do
      Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => "", "id" => 1 })
    end
  end

  def test_rejects_missing_method
    assert_raises(Reclamo::InvalidRequest) do
      Reclamo::Request.new({ "jsonrpc" => "2.0", "id" => 1 })
    end
  end

  def test_rejects_invalid_params_type
    assert_raises(Reclamo::InvalidRequest) do
      Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => "foo", "params" => "bad", "id" => 1 })
    end

    assert_raises(Reclamo::InvalidRequest) do
      Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => "foo", "params" => 42, "id" => 1 })
    end
  end

  def test_rejects_invalid_id_types
    assert_raises(Reclamo::InvalidRequest) do
      Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => "foo", "id" => [1] })
    end

    assert_raises(Reclamo::InvalidRequest) do
      Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => "foo", "id" => { "x" => 1 } })
    end

    assert_raises(Reclamo::InvalidRequest) do
      Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => "foo", "id" => true })
    end
  end

  def test_accepts_valid_id_types
    %w[string-id].each do |id|
      request = Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => "foo", "id" => id })
      assert_equal id, request.id
    end

    [1, 0, -1, 42, 1.5].each do |id|
      request = Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => "foo", "id" => id })
      assert_equal id, request.id
    end
  end

  def test_accepts_null_id
    request = Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => "foo", "id" => nil })

    assert_nil request.id
    refute_predicate request, :notification?
  end

  def test_invalid_request_includes_descriptive_message
    err = assert_raises(Reclamo::InvalidRequest) { Reclamo::Request.new("string") }
    assert_match(/JSON object/, err.message)
  end

  def test_wrong_version_includes_descriptive_message
    err = assert_raises(Reclamo::InvalidRequest) do
      Reclamo::Request.new({ "jsonrpc" => "1.0", "method" => "foo" })
    end
    assert_match(/2\.0/, err.message)
  end

  def test_invalid_params_type_includes_descriptive_message
    err = assert_raises(Reclamo::InvalidRequest) do
      Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => "foo", "params" => "bad" })
    end
    assert_match(/Array or Object/, err.message)
  end

  def test_invalid_id_type_includes_descriptive_message
    err = assert_raises(Reclamo::InvalidRequest) do
      Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => "foo", "id" => true })
    end
    assert_match(/String, Number, or Null/, err.message)
  end
end

class TestRequestNotification < Minitest::Test
  def test_request_with_id_is_not_notification
    request = Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => "foo", "id" => 1 })

    refute_predicate request, :notification?
  end

  def test_request_without_id_is_notification
    request = Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => "foo" })

    assert_predicate request, :notification?
  end

  def test_request_with_null_id_is_not_notification
    request = Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => "foo", "id" => nil })

    refute_predicate request, :notification?
  end
end

class TestRequestFreezing < Minitest::Test
  def test_method_name_is_frozen
    request = Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => "foo", "id" => 1 })

    assert_predicate request.method_name, :frozen?
  end

  def test_array_params_are_frozen
    request = Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => "foo", "params" => [1, 2], "id" => 1 })

    assert_predicate request.params, :frozen?
  end

  def test_hash_params_are_frozen
    request = Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => "foo", "params" => { "a" => 1 }, "id" => 1 })

    assert_predicate request.params, :frozen?
  end

  def test_id_is_frozen
    request = Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => "foo", "id" => "abc" })

    assert_predicate request.id, :frozen?
  end

  def test_nil_params_remain_nil
    request = Reclamo::Request.new({ "jsonrpc" => "2.0", "method" => "foo", "id" => 1 })

    assert_nil request.params
  end

  def test_nested_array_elements_are_frozen
    data = { "jsonrpc" => "2.0", "method" => "foo", "params" => [{ "a" => 1 }, [2, 3]], "id" => 1 }
    request = Reclamo::Request.new(data)

    assert_predicate request.params[0], :frozen?
    assert_predicate request.params[1], :frozen?
  end

  def test_nested_hash_values_are_frozen
    data = { "jsonrpc" => "2.0", "method" => "foo", "params" => { "nested" => { "deep" => "val" } }, "id" => 1 }
    request = Reclamo::Request.new(data)

    assert_predicate request.params["nested"], :frozen?
  end

  def test_deeply_nested_structures_are_frozen
    data = { "jsonrpc" => "2.0", "method" => "foo",
             "params" => [{ "a" => [{ "b" => "c" }] }], "id" => 1 }
    request = Reclamo::Request.new(data)

    assert_predicate request.params[0]["a"], :frozen?
    assert_predicate request.params[0]["a"][0], :frozen?
  end

  def test_string_values_in_params_are_frozen
    data = { "jsonrpc" => "2.0", "method" => "foo", "params" => ["mutable?"], "id" => 1 }
    request = Reclamo::Request.new(data)

    assert_predicate request.params[0], :frozen?
  end
end
