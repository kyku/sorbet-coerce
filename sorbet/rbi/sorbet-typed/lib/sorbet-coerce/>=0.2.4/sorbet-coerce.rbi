# This file is autogenerated. Do not edit it by hand. Regenerate it with:
#   srb rbi sorbet-typed
#
# If you would like to make changes to this file, great! Please upstream any changes you make here:
#
#   https://github.com/sorbet/sorbet-typed/edit/master/lib/sorbet-coerce/>=0.2.4/sorbet-coerce.rbi
#
# typed: false
module SafeType
  class CoercionError < StandardError; end
end

module TypeCoerce
  extend T::Sig
  extend T::Generic

  Elem = type_member

  sig { params(args: T.untyped, raise_coercion_error: T.nilable(T::Boolean)).returns(Elem) }
  def from(args, raise_coercion_error: nil); end

  class CoercionError < SafeType::CoercionError; end
  class ShapeError < SafeType::CoercionError; end
end