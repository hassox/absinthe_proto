defmodule AbsintheProto.ForeignKey do
  @moduledoc """
  Defines a foreign key to dynamically add foreign keys to objects
  """
  alias AbsintheProto.Objects

  @callback matcher(Objects.GqlObject.t, Objects.GqlObject.GqlField.t) :: boolean
  @callback output_field_name(Objects.GqlObject.t, Objects.GqlObject.GqlField.t) :: atom
  @callback output_field_type(Objects.GqlObject.t, Objects.GqlObject.GqlField.t) :: atom
  @callback one_resolver(Objects.GqlObject.t, Objects.GqlObject.GqlField.t) :: (map, map, Absinthe.Resolution.t -> {:ok | :error, any} | :error)
  @callback many_resolver(Objects.GqlObject.t, Objects.GqlObject.GqlField.t) :: (map, map, Absinthe.Resolution.t -> {:ok, [any]} | :error | {:error, term})

  defmacro __using__(_opts \\ []) do
    quote do
      @behaviour AbsintheProto.ForeignKey

      def matcher(_, _), do: false
      defoverridable matcher: 2
    end
  end
end
