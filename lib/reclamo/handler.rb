# frozen_string_literal: true

module Reclamo
  # @api private
  VARIADIC_DEFAULTS = { rest: "args", keyrest: "kwargs" }.freeze
  private_constant :VARIADIC_DEFAULTS

  DANGEROUS_METHODS = %w[
    eval instance_eval class_eval module_eval
    send public_send __send__
    system exec spawn
    define_method remove_method
    binding method_missing respond_to_missing?
  ].freeze
  private_constant :DANGEROUS_METHODS

  class Handler
    def initialize
      @targets = {}
      @descriptions = {}
      @returns = {}
      @deprecated = {}
    end

    def expose(target, namespace: nil, only: nil, except: nil, descriptions: nil, returns: nil, deprecated: nil)
      validate_expose_args!(target, only, except)
      prefix = namespace.to_s.then { |ns| ns.empty? ? "" : "#{ns}." }
      methods = filter_methods(callable_methods(target), only: only, except: except)
      Kernel.warn "Reclamo: expose registered 0 methods from #{target.inspect}" if methods.empty?
      methods.each { |m| register_exposed(prefix, m, target, descriptions, returns, deprecated) }
    end

    def expose_method(name, callable = nil, description: nil, returns: nil, deprecated: nil, &block)
      callable = resolve_callable(callable, block)
      name = name.to_s
      validate_method_name!(name)
      @targets[name] = callable
      @descriptions[name] = description.to_s if description
      @returns[name] = returns if returns
      @deprecated[name] = deprecated == true ? true : deprecated.to_s if deprecated
    end

    def call(method_name, params)
      entry = @targets[method_name]
      raise MethodNotFound, method_name unless entry

      invoke_callable(resolve_entry(entry), params)
    end

    def method?(method_name) = @targets.key?(method_name)
    def methods_list = @targets.keys.sort
    def methods_info = @targets.keys.sort.map { |name| method_info(name) }
    def size = @targets.size
    def empty? = @targets.empty?

    def freeze
      [@targets, @descriptions, @returns, @deprecated].each(&:freeze)
      super
    end

    private

    def method_info(name)
      callable = resolve_entry(@targets[name])
      info = { "name" => name }
      add_method_metadata(info, name, callable)
      info
    end

    def add_method_metadata(info, name, callable)
      info["description"] = @descriptions[name] if @descriptions.key?(name)
      add_params(info, callable)
      info["result"] = build_result(@returns[name]) if @returns.key?(name)
      info["deprecated"] = @deprecated[name] if @deprecated.key?(name)
    end

    def add_params(info, callable)
      params = callable.parameters.filter_map { |type, pname| param_descriptor(type, pname) }
      info["params"] = params unless params.empty?
    end

    def build_result(returns)
      returns.is_a?(Hash) ? { "name" => "result" }.merge(returns) : { "name" => "result", "schema" => returns }
    end

    def resolve_entry(entry)
      entry.is_a?(Array) ? entry[0].method(entry[1].to_sym) : entry
    end

    def param_descriptor(type, pname)
      return if type == :block

      desc = { "name" => pname&.to_s || VARIADIC_DEFAULTS.fetch(type, "arg") }
      desc["required"] = true if %i[req keyreq].include?(type)
      desc["variadic"] = true if %i[rest keyrest].include?(type)
      desc["keyword"] = true if %i[key keyreq keyrest].include?(type)
      desc
    end

    def register_exposed(prefix, method_name, target, descriptions, returns, deprecated)
      full_name = "#{prefix}#{method_name}"
      validate_method_name!(full_name)
      @targets[full_name] = [target, method_name]
      store_metadata(full_name, method_name, @descriptions, descriptions, &:to_s)
      store_metadata(full_name, method_name, @returns, returns)
      store_metadata(full_name, method_name, @deprecated, deprecated)
    end

    def store_metadata(full_name, method_name, store, source, &transform)
      return unless source

      value = source[method_name.to_sym] || source[method_name.to_s]
      return unless value

      store[full_name] = transform ? transform.call(value) : value
    end

    def callable_methods(target)
      case target
      when Class
        (target.public_methods(false) - Class.public_instance_methods).map(&:to_s)
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

    def validate_expose_args!(target, only, except)
      raise ArgumentError, "target must not be nil" if target.nil?
      raise ArgumentError, "cannot use both :only and :except" if only && except
    end

    def validate_method_name!(name)
      raise ArgumentError, "method name must not be empty" if name.empty?
      raise ArgumentError, "method names starting with 'rpc.' are reserved" if name.start_with?("rpc.")

      leaf = name.include?(".") ? name.split(".").last : name
      raise ArgumentError, "method name '#{leaf}' is dangerous" if DANGEROUS_METHODS.include?(leaf)
      raise ArgumentError, "method '#{name}' is already registered" if @targets.key?(name)
    end

    def resolve_callable(callable, block)
      raise ArgumentError, "provide either a callable or a block, not both" if callable && block
      raise ArgumentError, "a callable or block is required" unless callable || block

      (callable || block).tap do |resolved|
        raise ArgumentError, "callable must respond to #call" unless resolved.respond_to?(:call)
      end
    end

    def invoke_callable(callable, params)
      case params
      when Array then callable.call(*params)
      when Hash  then callable.call(**params.transform_keys(&:to_sym))
      when nil   then callable.call
      else raise ArgumentError, "params must be an Array, Hash, or nil"
      end
    end
  end
end
