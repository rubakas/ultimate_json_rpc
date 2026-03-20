# frozen_string_literal: true

require "json"
require_relative "ultimate_json_rpc/version"

module UltimateJsonRpc
  module Core
    class Error < StandardError; end
  end
end

require_relative "ultimate_json_rpc/core/errors"
require_relative "ultimate_json_rpc/core/request"
require_relative "ultimate_json_rpc/core/response"
require_relative "ultimate_json_rpc/core/handler"
require_relative "ultimate_json_rpc/server"
