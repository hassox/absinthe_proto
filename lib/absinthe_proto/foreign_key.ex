defmodule AbsintheProto.ForeignKey do
  @moduledoc """
  Defines a foreign key to dynamically add foreign keys to objects
  """
  @type message :: %{identifier: atom, proto_module: module}
  @type field :: %{identifier: atom, list?: boolean, field_props: map}

  @callback matcher(message, field) :: boolean
  @callback output_field_name(message, field) :: atom
  @callback output_field_type(message, field) :: atom
  @callback one_resolver(message, field) :: (map, map, Absinthe.Resolution.t -> {:ok | :error, any} | :error)
  @callback many_resolver(message, field) :: (map, map, Absinthe.Resolution.t -> {:ok, [any]} | :error | {:error, term})
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
