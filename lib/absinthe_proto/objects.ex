defmodule AbsintheProto.ObjectFields do
  @moduledoc false
  def object_fields,
    do: [:gql_type, :identifier, :attrs, fields: %{}, module: nil]
end

defmodule AbsintheProto.Objects do
  require AbsintheProto.ObjectFields

  defmodule AbsinthProto.Objects.ForeignKey do
    @type t :: %__MODULE__.t{
      required(:matcher) => fn(mod, Protobuf.FieldProps.t) :: bool,
      required(:output_field_name) => fn(mod, Protobuf.FieldProps.t) :: atom,
      required(:output_field_type) => fn(mod, Protobuf.FieldProps.t) :: atom,
      required(:one_resolver) => fn(mod, Protobuf.FieldProps.t) :: (fn(map, map, Absinthe.Resolution.t) :: {:ok | :error, any})
      required(:many_resolver) => fn(mod, Protobuf.FieldProps.t) :: (fn(map, map, Absinthe.Resolution.t) :: {:ok | :error, any})
    }

    defstruct [
      :matcher,
      :output_field_name,
      :output_field_type,
      :one_resolver,
      :many_resolver,
    ]
  end

  defmodule GqlInputObject do
    defstruct AbsintheProto.ObjectFields.object_fields()
  end

  defmodule GqlService do
    defstruct AbsintheProto.ObjectFields.object_fields()
  end

  defmodule GqlObject do
    defstruct AbsintheProto.ObjectFields.object_fields()

    defmodule GqlField do
      defstruct [:identifier, :attrs, :orig?]
    end
  end

  defmodule GqlEnum do
    defstruct [:gql_type, :identifier, :attrs, values: [], module: nil]
    defmodule GqlValue do
      defstruct [:identifier, attrs: []]
    end
  end
end
