defmodule AbsintheProto.ForeignKey do
  @moduledoc """
  Defines a foreign key to dynamically add foreign keys to objects
  """

  @typedoc "Proto message module "
  @type message :: %{identifier: atom, proto_module: module}

  @typedoc "A minimal field identifier"
  @type field :: %{identifier: atom, list?: boolean, field_props: map}

  @doc "matcher tests a field name to see if it applies to this foreign_key"
  @callback matcher(message, field) :: boolean

  @doc "provides the output field name based on the input field name"
  @callback output_field_name(message, field) :: atom

  @doc "provides the output field type. e.g. `:my_protos__data__user`"
  @callback output_field_type(message, field) :: atom

  @doc "Provides a resolver when the underlying field is not a list"
  @callback one_resolver(message, field) :: (map, map, Absinthe.Resolution.t -> {:ok | :error, any} | :error)

  @doc "Provides a resolver when the underlying field is a list"
  @callback many_resolver(message, field) :: (map, map, Absinthe.Resolution.t -> {:ok, [any]} | :error | {:error, term})

  @doc "Provides a list of arguments to add to the field. Optional"
  @callback attributes(message, field) :: [term]

  defmacro __using__(_opts \\ []) do
    quote do
      @behaviour AbsintheProto.ForeignKey

      def matcher(_, _), do: false
      def attributes(_, _), do: []
      defoverridable matcher: 2, attributes: 2
    end
  end
end
