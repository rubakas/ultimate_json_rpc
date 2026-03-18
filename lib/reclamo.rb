# frozen_string_literal: true

require "json"
require_relative "reclamo/version"

module Reclamo
  class Error < StandardError; end
end

require_relative "reclamo/errors"
require_relative "reclamo/request"
require_relative "reclamo/response"
require_relative "reclamo/handler"
require_relative "reclamo/server"
