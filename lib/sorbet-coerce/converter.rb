# typed: ignore
require 'polyfill'
require 'safe_type'
require 'set'
require 'sorbet-runtime'
require 'sorbet-coerce/configuration'

using Polyfill(Hash: %w[#slice])

module TypeCoerce
  class CoercionError < SafeType::CoercionError; end
  class ShapeError < SafeType::CoercionError; end
end

class TypeCoerce::Converter
  def initialize(type)
    @type = type
  end

  def new
    self
  end

  def to_s
    "#{name}#[#{@type.to_s}]"
  end

  def from(args, raise_coercion_error: nil)
    if raise_coercion_error.nil?
      raise_coercion_error = TypeCoerce::Configuration.raise_coercion_error
    end

    T.let(_convert(args, @type, raise_coercion_error), @type)
  end

  private

  PRIMITIVE_TYPES = T.let(::Set[
    Date,
    DateTime,
    Float,
    Integer,
    String,
    Symbol,
    Time,
  ], T.untyped)

  def _convert(value, type, raise_coercion_error)
    if type.is_a?(T::Types::Untyped)
      value
    elsif type.is_a?(T::Types::TypedArray)
      _convert_to_a(value, type.type, raise_coercion_error)
    elsif type.is_a?(T::Types::TypedSet)
      Set.new(_convert_to_a(value, type.type, raise_coercion_error))
    elsif type.is_a?(T::Types::Simple)
      _convert(value, type.raw_type, raise_coercion_error)
    elsif type.is_a?(T::Types::Union)
      true_idx = T.let(nil, T.nilable(Integer))
      false_idx = T.let(nil, T.nilable(Integer))
      nil_idx = T.let(nil, T.nilable(Integer))

      type.types.each_with_index do |t, i|
        nil_idx = i if t.is_a?(T::Types::Simple) && t.raw_type == NilClass
        true_idx = i if t.is_a?(T::Types::Simple) && t.raw_type == TrueClass
        false_idx = i if t.is_a?(T::Types::Simple) && t.raw_type == FalseClass
      end

      raise ArgumentError.new(
        'the only supported union types are T.nilable and T::Boolean',
      ) unless (
        (!true_idx.nil? && !false_idx.nil? && !nil_idx.nil?) || # T.nilable(T::Boolean)
        (type.types.length == 2 && (
          !nil_idx.nil? || (!true_idx.nil? && !false_idx.nil?) # T.nilable || T::Boolean
        ))
      )

      if !true_idx.nil? && !false_idx.nil?
        _convert_simple(value, T::Boolean, raise_coercion_error)
      else
        _convert(value, type.types[nil_idx == 0 ? 1 : 0], raise_coercion_error)
      end
    elsif type.is_a?(T::Types::TypedHash)
      return {} if _nil_like?(value, type)

      unless value.respond_to?(:map)
        raise TypeCoerce::ShapeError.new(value, type)
      end

      value.map do |k, v|
        [
          _convert(k, type.keys, raise_coercion_error),
          _convert(v, type.values, raise_coercion_error),
        ]
      end.to_h
    elsif Object.const_defined?('T::Private::Types::TypeAlias') &&
          type.is_a?(T::Private::Types::TypeAlias)
      _convert(value, type.aliased_type, raise_coercion_error)
    elsif type.respond_to?(:<) && type < T::Struct
      return value if value.is_a?(type)

      args = _build_args(value, type, raise_coercion_error)
      type.new(args)
    elsif type.respond_to?(:<) && type < T::Enum
      return value if value.is_a?(type)

      _convert_enum(value, type, raise_coercion_error)
    else
      return value if value.is_a?(type)

      _convert_simple(value, type, raise_coercion_error)
    end
  end

  def _convert_enum(value, type, raise_coercion_error)
    if raise_coercion_error
      type.deserialize(value)
    else
      type.try_deserialize(value)
    end
  rescue KeyError
    raise TypeCoerce::CoercionError.new(value, type)
  end

  def _convert_simple(value, type, raise_coercion_error)
    return nil if _nil_like?(value, type)

    safe_type_rule = T.let(nil, T.untyped)

    if type == T::Boolean
      safe_type_rule = SafeType::Boolean.strict
    elsif value.is_a?(type)
      return value
    elsif type == BigDecimal
      return BigDecimal(value, 0)
    elsif PRIMITIVE_TYPES.include?(type)
      safe_type_rule = SafeType.const_get(type.name).strict
    else
      safe_type_rule = type
    end

    if safe_type_rule.is_a?(SafeType::Rule)
      SafeType::coerce(value, safe_type_rule)
    else
      type.new(value)
    end
  rescue SafeType::EmptyValueError, SafeType::CoercionError
    if raise_coercion_error
      raise TypeCoerce::CoercionError.new(value, type)
    else
      nil
    end
  end

  def _convert_to_a(ary, type, raise_coercion_error)
    return [] if _nil_like?(ary, type)

    unless ary.respond_to?(:map)
      raise TypeCoerce::ShapeError.new(ary, type)
    end

    ary.map { |value| _convert(value, type, raise_coercion_error) }
  end

  def _build_args(args, type, raise_coercion_error)
    return {} if _nil_like?(args, Hash)

    unless args.respond_to?(:each_pair)
      raise TypeCoerce::ShapeError.new(args, type)
    end

    props = type.props
    args.map { |name, value|
      key = name.to_sym
      [
        key,
        (!props.include?(key) || value.nil?) ?
          nil : _convert(value, props[key][:type], raise_coercion_error),
      ]
    }.to_h.slice(*props.keys)
  end

  def _nil_like?(value, type)
    value.nil? || (value == '' && type != String)
  end
end
