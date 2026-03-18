# frozen_string_literal: true

require "test_helper"
require "reclamo/tcp"
require "json"
require "socket"

class TestTCP < Minitest::Test
  def test_handles_request
    with_tcp_server do |port|
      response = tcp_call(port, '{"jsonrpc":"2.0","method":"add","params":[2,3],"id":1}')

      assert_equal 5, response["result"]
    end
  end

  def test_handles_multiple_requests_on_same_connection
    with_tcp_server do |port|
      TCPSocket.open("127.0.0.1", port) do |sock|
        sock.puts('{"jsonrpc":"2.0","method":"add","params":[1,2],"id":1}')
        r1 = JSON.parse(sock.gets.chomp)

        sock.puts('{"jsonrpc":"2.0","method":"add","params":[3,4],"id":2}')
        r2 = JSON.parse(sock.gets.chomp)

        assert_equal 3, r1["result"]
        assert_equal 7, r2["result"]
      end
    end
  end

  def test_notification_returns_no_response
    with_tcp_server do |port|
      TCPSocket.open("127.0.0.1", port) do |sock|
        sock.puts('{"jsonrpc":"2.0","method":"add","params":[1,2]}')
        # Send a regular request to verify the connection is still alive
        sock.puts('{"jsonrpc":"2.0","method":"add","params":[3,4],"id":1}')
        response = JSON.parse(sock.gets.chomp)

        assert_equal 7, response["result"]
      end
    end
  end

  def test_skips_empty_lines
    with_tcp_server do |port|
      TCPSocket.open("127.0.0.1", port) do |sock|
        sock.puts("")
        sock.puts('{"jsonrpc":"2.0","method":"add","params":[5,6],"id":1}')
        response = JSON.parse(sock.gets.chomp)

        assert_equal 11, response["result"]
      end
    end
  end

  def test_multiple_clients
    with_tcp_server do |port|
      threads = 3.times.map do |i|
        Thread.new do
          tcp_call(port, JSON.generate({ "jsonrpc" => "2.0", "method" => "add", "params" => [i, 1], "id" => i }))
        end
      end
      results = threads.map(&:value).map { |r| r["result"] }.sort

      assert_equal [1, 2, 3], results
    end
  end

  def test_parse_error
    with_tcp_server do |port|
      response = tcp_call(port, "not json")

      assert_equal(-32_700, response["error"]["code"])
    end
  end

  def test_stop
    server = Reclamo::Server.new
    server.expose(Calculator)
    tcp = Reclamo::TCP.new(server, port: 0)

    thread = Thread.new { tcp.run }
    deadline = Time.now + 5
    sleep(0.05) until tcp.running? || Time.now > deadline

    assert tcp.running?
    tcp.stop
    thread.join(1)

    refute tcp.running?
  end

  private

  def with_tcp_server
    server = Reclamo::Server.new
    server.expose(Calculator)
    # Port 0 lets the OS assign a free port
    tcp = Reclamo::TCP.new(server, port: 0)

    thread = Thread.new { tcp.run }
    deadline = Time.now + 5
    sleep(0.05) until tcp.running? || Time.now > deadline

    # Get the actual assigned port
    port = tcp.instance_variable_get(:@tcp_server).addr[1]

    yield port
  ensure
    tcp.stop
    thread&.join(1)
  end

  def tcp_call(port, request_json)
    TCPSocket.open("127.0.0.1", port) do |sock|
      sock.puts(request_json)
      JSON.parse(sock.gets.chomp)
    end
  end
end
