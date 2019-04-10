defmodule AbsintheProto.Utils do

  @spec rpc_name_to_gql_name(atom) :: atom
  @doc "Converts a raw RPC name to the gql equivelant"
  def rpc_name_to_gql_name(raw_name),
    do: raw_name |> to_string() |> Macro.underscore() |> String.to_atom()

  def gql_object_name(mod, other_parts \\ []) do
    [Macro.underscore(mod) | other_parts]
    |> Enum.map(fn i ->
      i |> to_string() |> Macro.underscore() |> String.replace("/", "__")
    end)
    |> Enum.join("__")
    |> String.to_atom()
  end
end