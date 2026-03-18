# frozen_string_literal: true

module Reclamo
  # @api private
  VARIADIC_DEFAULTS = { rest: "args", keyrest: "kwargs" }.freeze
  private_constant :VARIADIC_DEFAULTS

  class Handler
    def initialize
      @targets = {}
      @descriptions = {}
    end

    def expose(target, namespace: nil, only: nil, except: nil, descriptions: nil)
      raise ArgumentError, "cannot use both :only and :except" if only && except

      prefix = namespace.to_s.then { |ns| ns.empty? ? "" : "#{ns}." }
      methods = filter_methods(callable_methods(target), only: only, except: except)
      methods.each do |method_name|
        full_name = "#{prefix}#{method_name}"
        validate_method_name!(full_name)
        check_duplicate!(full_name)
        @targets[full_name] = [target, method_name]
        store_description(full_name, method_name, descriptions)
      end
    end

    def expose_method(name, description: nil, &block)
      raise ArgumentError, "block required" unless block

      name = name.to_s
      validate_method_name!(name)
      check_duplicate!(name)
      @targets[name] = block
      @descriptions[name] = description.to_s if description
    end

    def call(method_name, params)
      entry = @targets[method_name]
      raise MethodNotFound, method_name unless entry

      if entry.is_a?(Array)
        target, meth = entry
        invoke(target, meth, params)
      else
        invoke_callable(entry, params)
      end
    end

    def method?(method_name) = @targets.key?(method_name)
    def methods_list = @targets.keys.sort
    def methods_info = @targets.keys.sort.map { |name| method_info(name) }
    def size = @targets.size

    private

    def method_info(name)
      entry = @targets[name]
      callable = entry.is_a?(Array) ? entry[0].method(entry[1].to_sym) : entry
      info = { "name" => name }
      info["description"] = @descriptions[name] if @descriptions.key?(name)
      params = callable.parameters.filter_map { |type, pname| param_descriptor(type, pname) }
      info["params"] = params unless params.empty?
      info
    end

    def param_descriptor(type, pname)
      return if type == :block

      desc = { "name" => pname&.to_s || VARIADIC_DEFAULTS.fetch(type, "arg") }
      desc["required"] = true if %i[req keyreq].include?(type)
      desc["variadic"] = true if %i[rest keyrest].include?(type)
      desc["keyword"] = true if %i[key keyreq keyrest].include?(type)
      desc
    end

    def store_description(full_name, method_name, descriptions)
      return unless descriptions

      desc = descriptions[method_name.to_sym] || descriptions[method_name.to_s]
      @descriptions[full_name] = desc.to_s if desc
    end

    def callable_methods(target)
      case target
      when Module
        (target.public_methods(false) - Module.public_instance_methods).map(&:to_s)
      else
        (target.public_methods(false) - Object.public_instance_methods).map(&:to_s)
      end
    end

    def filter_methods(methods, only:, except:)
      if only
        allowed = Array(only).map(&:to_s)
        methods.select { |m| allowed.include?(m) }
      elsif except
        blocked = Array(except).map(&:to_s)
        methods.reject { |m| blocked.include?(m) }
      else
        methods
      end
    end

    def validate_method_name!(name)
      raise ArgumentError, "method name must not be empty" if name.empty?
      raise ArgumentError, "method names starting with 'rpc.' are reserved" if name.start_with?("rpc.")
    end

    def check_duplicate!(name)
      raise ArgumentError, "method '#{name}' is already registered" if @targets.key?(name)
    end

    def invoke(target, method_name, params)
      invoke_callable(target.method(method_name.to_sym), params)
    end

    def invoke_callable(callable, params)
      case params
      when Array then callable.call(*params)
      when Hash  then callable.call(**params.transform_keys(&:to_sym))
      when nil   then callable.call
      end
    end
  end

  class MethodNotFound < Error; end
end
