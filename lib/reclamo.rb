# frozen_string_literal: true

require "json"
require_relative "reclamo/version"

module Reclamo
  module Core
    class Error < StandardError; end
  end
end

require_relative "reclamo/core/errors"
require_relative "reclamo/core/request"
require_relative "reclamo/core/response"
require_relative "reclamo/core/handler"
require_relative "reclamo/server"
