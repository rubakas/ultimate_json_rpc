# frozen_string_literal: true

require "test_helper"
require "reclamo/transport/tcp"
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

  def test_rejects_connections_beyond_max
    server = Reclamo::Server.new
    server.expose(Calculator)
    tcp = Reclamo::Transport::TCP.new(server, port: 0, max_connections: 1)

    thread = Thread.new { tcp.run }
    deadline = Time.now + 5
    sleep(0.05) until tcp.running? || Time.now > deadline
    port = tcp.port

    # First connection should work
    sock1 = TCPSocket.open("127.0.0.1", port)
    sock1.puts('{"jsonrpc":"2.0","method":"add","params":[1,2],"id":1}')
    assert_equal 3, JSON.parse(sock1.gets.chomp)["result"]

    # Second connection should be rejected (closed by server)
    sock2 = TCPSocket.open("127.0.0.1", port)
    sleep(0.1) # Give server time to reject
    assert_nil sock2.gets, "Second connection should have been closed by server"
  ensure
    sock1&.close
    sock2&.close
    tcp&.stop
    thread&.join(2)
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
    tcp = Reclamo::Transport::TCP.new(server, port: 0)

    thread = Thread.new { tcp.run }
    deadline = Time.now + 5
    sleep(0.05) until tcp.running? || Time.now > deadline

    assert tcp.running?
    tcp.stop
    assert thread.join(2), "TCP thread did not stop"

    refute tcp.running?
  end

  private

  def with_tcp_server
    server = Reclamo::Server.new
    server.expose(Calculator)
    # Port 0 lets the OS assign a free port
    tcp = Reclamo::Transport::TCP.new(server, port: 0)

    thread = Thread.new { tcp.run }
    deadline = Time.now + 5
    sleep(0.05) until tcp.running? || Time.now > deadline

    # Get the actual assigned port
    port = tcp.port

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

class TestTCPConnectionLimit < Minitest::Test
  def test_default_max_connections
    assert_equal 64, Reclamo::Transport::TCP::DEFAULT_MAX_CONNECTIONS
  end
end

class TestTCPStopRace < Minitest::Test
  def test_stop_during_accept_loop_does_not_crash
    server = Reclamo::Server.new
    server.expose(Calculator)
    tcp = Reclamo::Transport::TCP.new(server, port: 0, host: "127.0.0.1")

    thread = Thread.new { tcp.run }
    sleep(0.05)
    tcp.stop
    thread.join(5)

    refute thread.alive?, "TCP thread should have exited cleanly"
  end
end

class TestTCPMaxLineBytes < Minitest::Test
  def test_max_line_bytes_constant
    assert_equal 4 * 1024 * 1024, Reclamo::Transport::TCP::MAX_LINE_BYTES
  end
end

class TestTCPPort < Minitest::Test
  def test_port_returns_nil_before_run
    server = Reclamo::Server.new
    tcp = Reclamo::Transport::TCP.new(server, port: 0)

    assert_nil tcp.port
  end

  def test_port_returns_bound_port_while_running
    server = Reclamo::Server.new
    server.expose(Calculator)
    tcp = Reclamo::Transport::TCP.new(server, port: 0)

    thread = Thread.new { tcp.run }
    deadline = Time.now + 5
    sleep(0.05) until tcp.running? || Time.now > deadline

    assert_kind_of Integer, tcp.port
    assert_operator tcp.port, :>, 0
  ensure
    tcp.stop
    thread&.join(2)
  end
end
