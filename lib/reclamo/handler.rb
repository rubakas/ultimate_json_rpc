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

  TYPE_CHECKS = {
    "string" => String, "number" => Numeric, "integer" => Integer,
    "boolean" => [TrueClass, FalseClass], "array" => Array,
    "object" => Hash, "null" => NilClass
  }.freeze
  private_constant :TYPE_CHECKS

  JSON_TYPE_NAMES = {
    String => "string", Integer => "integer", Float => "number",
    TrueClass => "boolean", FalseClass => "boolean",
    Array => "array", Hash => "object", NilClass => "null"
  }.freeze
  private_constant :JSON_TYPE_NAMES

  PARAM_FLAGS = {
    req: { "required" => true }, keyreq: { "required" => true, "keyword" => true },
    opt: {}, key: { "keyword" => true },
    rest: { "variadic" => true }, keyrest: { "variadic" => true, "keyword" => true }
  }.freeze
  private_constant :PARAM_FLAGS

  module ParamValidator
    private

    def validate_params!(callable, params, schema)
      return unless schema

      case params
      when Array then validate_positional!(callable, params, schema)
      when Hash then validate_keyword!(params, schema)
      end
    end

    def validate_positional!(callable, params, schema)
      names = callable.parameters.filter_map { |type, pname| pname&.to_s unless type == :block }
      params.each_with_index do |value, index|
        validate_value!(names[index], value, schema[names[index]]) if names[index] && schema[names[index]]
      end
    end

    def validate_keyword!(params, schema)
      params.each { |k, v| validate_value!(k.to_s, v, schema[k.to_s]) if schema.key?(k.to_s) }
    end

    def validate_value!(name, value, pschema)
      check_param_type!(name, value, pschema)
      check_param_enum!(name, value, pschema)
    end

    def check_param_type!(name, value, pschema)
      type = pschema["type"]
      return unless type

      expected = TYPE_CHECKS[type]
      return unless expected
      return unless Array(expected).none? { |k| value.is_a?(k) }

      raise InvalidParams, "parameter '#{name}' must be #{type}, " \
                           "got #{JSON_TYPE_NAMES.fetch(value.class, value.class.name)}"
    end

    def check_param_enum!(name, value, pschema)
      return unless (enum = pschema["enum"]) && !enum.include?(value)

      raise InvalidParams, "parameter '#{name}' must be one of: #{enum.map(&:inspect).join(", ")}"
    end
  end
  private_constant :ParamValidator

  class Handler
    include ParamValidator

    def initialize
      @targets = {}
      @descriptions = {}
      @returns = {}
      @deprecated = {}
      @params_schemas = {}
    end

    def expose(target, namespace: nil, only: nil, except: nil, descriptions: nil, returns: nil, deprecated: nil,
               params_schema: nil)
      validate_expose_args!(target, only, except)
      prefix = namespace.to_s.then { |ns| ns.empty? ? "" : "#{ns}." }
      methods = filter_methods(callable_methods(target), only: only, except: except)
      Kernel.warn "Reclamo: expose registered 0 methods from #{target.inspect}" if methods.empty?
      methods.each { |m| register_exposed(prefix, m, target, descriptions, returns, deprecated, params_schema) }
    end

    def expose_method(name, callable = nil, description: nil, returns: nil, deprecated: nil, params_schema: nil,
                      &block)
      callable = resolve_callable(callable, block)
      name = name.to_s
      validate_method_name!(name)
      @targets[name] = callable
      @descriptions[name] = description.to_s if description
      @returns[name] = returns if returns
      @deprecated[name] = deprecated == true ? true : deprecated.to_s if deprecated
      @params_schemas[name] = params_schema.transform_keys(&:to_s) if params_schema
    end

    def call(method_name, params)
      entry = @targets[method_name]
      raise MethodNotFound, method_name unless entry

      callable = resolve_entry(entry)
      validate_params!(callable, params, @params_schemas[method_name])
      invoke_callable(callable, params)
    end

    def method?(method_name) = @targets.key?(method_name)
    def methods_list = @targets.keys.sort
    def methods_info = @targets.keys.sort.map { |name| method_info(name) }
    def size = @targets.size
    def empty? = @targets.empty?

    def freeze
      [@targets, @descriptions, @returns, @deprecated, @params_schemas].each(&:freeze)
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
      add_params(info, name, callable)
      info["result"] = build_result(@returns[name]) if @returns.key?(name)
      info["deprecated"] = @deprecated[name] if @deprecated.key?(name)
    end

    def add_params(info, name, callable)
      schema = @params_schemas[name]
      params = callable.parameters.filter_map { |type, pname| param_descriptor(type, pname, schema) }
      info["params"] = params unless params.empty?
    end

    def build_result(returns)
      returns.is_a?(Hash) ? { "name" => "result" }.merge(returns) : { "name" => "result", "schema" => returns }
    end

    def resolve_entry(entry)
      entry.is_a?(Array) ? entry[0].method(entry[1].to_sym) : entry
    end

    def param_descriptor(type, pname, method_schema)
      return if type == :block

      name = pname&.to_s || VARIADIC_DEFAULTS.fetch(type, "arg")
      desc = { "name" => name }.merge(PARAM_FLAGS.fetch(type, {}))
      desc["schema"] = method_schema[name] if method_schema&.key?(name)
      desc
    end

    def register_exposed(prefix, method_name, target, descriptions, returns, deprecated, params_schema)
      full_name = "#{prefix}#{method_name}"
      validate_method_name!(full_name)
      @targets[full_name] = [target, method_name]
      store_metadata(full_name, method_name, @descriptions, descriptions, &:to_s)
      store_metadata(full_name, method_name, @returns, returns)
      store_metadata(full_name, method_name, @deprecated, deprecated)
      store_metadata(full_name, method_name, @params_schemas, params_schema) { |v| v.transform_keys(&:to_s) }
    end

    def store_metadata(full_name, method_name, store, source, &transform)
      return unless source

      value = source[method_name.to_sym] || source[method_name.to_s]
      return unless value

      store[full_name] = transform ? transform.call(value) : value
    end

    def callable_methods(target)
      base = if target.is_a?(Class) then Class
             elsif target.is_a?(Module) then Module
             else Object
             end
      (target.public_methods(false) - base.public_instance_methods).map(&:to_s)
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
