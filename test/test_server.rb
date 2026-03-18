# frozen_string_literal: true

require "test_helper"
require "json"

class TestServerCalls < Minitest::Test
  def setup
    @server = Reclamo::Server.new
    @server.expose(Calculator)
    @server.expose(Greeter.new("Hi"), namespace: "greeter")
  end

  def test_successful_method_call
    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [2, 3], "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal "2.0", response["jsonrpc"]
    assert_equal 5, response["result"]
    assert_equal 1, response["id"]
  end

  def test_namespaced_method_call
    request = { "jsonrpc" => "2.0", "method" => "greeter.greet",
                "params" => { "name" => "World" }, "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal "Hi, World!", response["result"]
  end

  def test_method_call_without_params
    request = { "jsonrpc" => "2.0", "method" => "greeter.hello", "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal "hello", response["result"]
  end

  def test_method_call_with_keyword_params
    request = { "jsonrpc" => "2.0", "method" => "greeter.greet",
                "params" => { "name" => "Alice" }, "id" => 1 }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal "Hi, Alice!", response["result"]
  end

  def test_string_id
    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => "abc" }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_equal "abc", response["id"]
    assert_equal 3, response["result"]
  end

  def test_null_id
    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => nil }
    response = JSON.parse(@server.handle(JSON.generate(request)))

    assert_nil response["id"]
    assert_equal 3, response["result"]
  end

  def test_result_can_be_nil
    server = Reclamo::Server.new
    target = Object.new
    def target.noop; end
    server.expose(target)

    request = { "jsonrpc" => "2.0", "method" => "noop", "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_nil response["result"]
    assert_equal 1, response["id"]
  end

  def test_methods_list
    methods = @server.methods_list

    assert_includes methods, "add"
    assert_includes methods, "divide"
    assert_includes methods, "greeter.greet"
    assert_includes methods, "greeter.hello"
  end

  def test_expose_returns_self
    server = Reclamo::Server.new

    assert_equal server, server.expose(Calculator)
  end

  def test_server_method_query
    assert @server.method?("add")
    refute @server.method?("nonexistent")
  end

  def test_server_size
    assert_equal 4, @server.size
  end

  def test_server_empty
    empty_server = Reclamo::Server.new
    assert_predicate empty_server, :empty?
    refute_predicate @server, :empty?
  end

  def test_server_methods_info
    info = @server.methods_info
    add_info = info.find { |m| m["name"] == "add" }

    assert_equal 4, info.size
    assert_equal "add", add_info["name"]
    assert add_info.key?("params")
  end
end

class TestServerNotifications < Minitest::Test
  def setup
    @server = Reclamo::Server.new
    @server.expose(Calculator)
  end

  def test_notification_returns_nil
    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2] }

    assert_nil @server.handle(JSON.generate(request))
  end

  def test_notification_error_returns_nil
    request = { "jsonrpc" => "2.0", "method" => "divide", "params" => [1, 0] }

    assert_nil @server.handle(JSON.generate(request))
  end

  def test_notification_method_not_found_returns_nil
    request = { "jsonrpc" => "2.0", "method" => "nonexistent" }

    assert_nil @server.handle(JSON.generate(request))
  end
end

class TestServerHandleParsed < Minitest::Test
  def setup
    @server = Reclamo::Server.new
    @server.expose(Calculator)
  end

  def test_handle_parsed_single_request
    data = { "jsonrpc" => "2.0", "method" => "add", "params" => [2, 3], "id" => 1 }
    response = JSON.parse(@server.handle_parsed(data))

    assert_equal 5, response["result"]
  end

  def test_handle_parsed_batch
    data = [
      { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 },
      { "jsonrpc" => "2.0", "method" => "add", "params" => [3, 4], "id" => 2 }
    ]
    responses = JSON.parse(@server.handle_parsed(data))

    assert_equal 2, responses.size
    assert_equal 3, responses[0]["result"]
  end

  def test_handle_parsed_notification
    data = { "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2] }

    assert_nil @server.handle_parsed(data)
  end

  def test_handle_parsed_invalid_request
    data = { "jsonrpc" => "1.0", "method" => "add", "id" => 1 }
    response = JSON.parse(@server.handle_parsed(data))

    assert_equal(-32_600, response["error"]["code"])
  end

  def test_handle_parsed_non_hash_non_array
    response = JSON.parse(@server.handle_parsed("a string"))

    assert_equal(-32_600, response["error"]["code"])
  end

  def test_handle_parsed_nil
    response = JSON.parse(@server.handle_parsed(nil))

    assert_equal(-32_600, response["error"]["code"])
  end
end

class TestServerCallable < Minitest::Test
  def test_call_is_alias_for_handle
    server = Reclamo::Server.new
    server.expose(Calculator)

    request = JSON.generate({ "jsonrpc" => "2.0", "method" => "add", "params" => [2, 3], "id" => 1 })
    assert_equal server.handle(request), server.call(request)
  end

  def test_call_with_method_object
    server = Reclamo::Server.new
    server.expose(Calculator)
    callable = server.method(:call)

    request = JSON.generate({ "jsonrpc" => "2.0", "method" => "add", "params" => [2, 3], "id" => 1 })
    response = JSON.parse(callable.call(request))

    assert_equal 5, response["result"]
  end

  def test_to_proc_enables_map
    server = Reclamo::Server.new
    server.expose(Calculator)

    requests = [
      JSON.generate({ "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2], "id" => 1 }),
      JSON.generate({ "jsonrpc" => "2.0", "method" => "add", "params" => [3, 4], "id" => 2 })
    ]
    results = requests.map(&server).map { |r| JSON.parse(r)["result"] }

    assert_equal [3, 7], results
  end

  def test_to_proc_with_notifications
    server = Reclamo::Server.new
    server.expose(Calculator)

    requests = [
      JSON.generate({ "jsonrpc" => "2.0", "method" => "add", "params" => [1, 2] }),
      JSON.generate({ "jsonrpc" => "2.0", "method" => "add", "params" => [3, 4], "id" => 1 })
    ]
    results = requests.map(&server)

    assert_nil results[0]
    assert_equal 7, JSON.parse(results[1])["result"]
  end

  def test_encoding_error_returns_parse_error
    server = Reclamo::Server.new
    server.expose(Calculator)

    bad_string = "\xFF\xFE".dup.force_encoding("UTF-8")
    response = JSON.parse(server.handle(bad_string))

    assert_equal(-32_700, response["error"]["code"])
    assert_nil response["id"]
  end

  def test_method_not_found_includes_method_name_in_data
    server = Reclamo::Server.new
    server.expose(Calculator)

    request = { "jsonrpc" => "2.0", "method" => "nonexistent", "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal(-32_601, response["error"]["code"])
    assert_equal "nonexistent", response["error"]["data"]
  end

  def test_inspect
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.use { |_req, next_call| next_call.call }

    assert_equal "#<Reclamo::Server methods=2 middleware=1>", server.inspect
  end

  def test_inspect_empty_server
    server = Reclamo::Server.new

    assert_equal "#<Reclamo::Server methods=0 middleware=0>", server.inspect
  end

  def test_inspect_with_name
    server = Reclamo::Server.new(name: "My API")
    server.expose(Calculator)

    assert_equal "#<Reclamo::Server name=\"My API\" methods=2 middleware=0>", server.inspect
  end
end

class TestServerEdgeCases < Minitest::Test
  def test_expose_class_with_singleton_methods
    klass = Class.new do
      def self.class_method
        "from class"
      end
    end
    server = Reclamo::Server.new
    server.expose(klass)

    request = { "jsonrpc" => "2.0", "method" => "class_method", "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal "from class", response["result"]
  end

  def test_method_with_default_params
    server = Reclamo::Server.new
    server.expose_method("greet") { |name, greeting = "Hi"| "#{greeting}, #{name}!" }

    with_default = { "jsonrpc" => "2.0", "method" => "greet", "params" => ["World"], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(with_default)))
    assert_equal "Hi, World!", response["result"]

    with_override = { "jsonrpc" => "2.0", "method" => "greet", "params" => %w[World Hey], "id" => 2 }
    response = JSON.parse(server.handle(JSON.generate(with_override)))
    assert_equal "Hey, World!", response["result"]
  end

  def test_method_returning_complex_structure
    server = Reclamo::Server.new
    server.expose_method("data") { { "users" => [{ "name" => "Alice" }], "count" => 1 } }

    request = { "jsonrpc" => "2.0", "method" => "data", "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal({ "users" => [{ "name" => "Alice" }], "count" => 1 }, response["result"])
  end

  def test_chained_setup
    server = Reclamo::Server.new
    result = server
             .expose(Calculator)
             .expose_method("ping") { "pong" }
             .use { |_req, next_call| next_call.call }

    assert_equal server, result
    assert server.method?("add")
    assert server.method?("ping")
  end
end

class TestServerFreeze < Minitest::Test
  def test_frozen_server_handles_requests
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.freeze

    request = { "jsonrpc" => "2.0", "method" => "add", "params" => [2, 3], "id" => 1 }
    response = JSON.parse(server.handle(JSON.generate(request)))

    assert_equal 5, response["result"]
  end

  def test_frozen_server_rejects_expose
    server = Reclamo::Server.new
    server.freeze

    assert_raises(FrozenError) { server.expose(Calculator) }
  end

  def test_frozen_server_rejects_expose_method
    server = Reclamo::Server.new
    server.freeze

    assert_raises(FrozenError) { server.expose_method("ping") { "pong" } }
  end

  def test_frozen_server_rejects_use
    server = Reclamo::Server.new
    server.freeze

    assert_raises(FrozenError) { server.use { |_req, n| n.call } }
  end

  def test_frozen_server_is_frozen
    server = Reclamo::Server.new
    server.expose(Calculator)
    server.freeze

    assert server.frozen?
  end
end
