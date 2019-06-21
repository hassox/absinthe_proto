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

  def field_datatype({:enum, type}, opts),
    do: field_datatype(type, Keyword.drop(opts, [:name_parts]))

  def field_datatype(type, opts) do
    dt_name =
      case AbsintheProto.Scalars.proto_to_gql_scalar(type) do
        :error ->
          gql_object_name(type, Keyword.get(opts, :name_parts, []))
        scalar ->
          scalar
      end

    opts |> Enum.into(%{}) |> quoted_field_datatype(dt_name)
  end

  def quoted_field_datatype(%{required?: true, repeated?: true}, dt_name) do
    quote do
      Absinthe.Schema.Notation.non_null(Absinthe.Schema.Notation.list_of(Absinthe.Schema.Notation.non_null(unquote(dt_name))))
    end
  end

  def quoted_field_datatype(%{repeated?: true}, dt_name) do
    quote do
      Absinthe.Schema.Notation.list_of(Absinthe.Schema.Notation.non_null(unquote(dt_name)))
    end
  end

  def quoted_field_datatype(%{required?: true}, dt_name) do
    quote do
      Absinthe.Schema.Notation.non_null(unquote(dt_name))
    end
  end

  def quoted_field_datatype(_, dt_name) do
    quote do
      unquote(dt_name)
    end
  end

  def enum_resolver_for_props(attrs, %{name_atom: name, enum?: true, type: {:enum, type}}) do
    res =
      quote do
        fn
          %{unquote(name) => value}, _, _ when is_integer(value) ->
            {:ok, unquote(type).key(value)}
          %{unquote(name) => value}, _, _ when is_atom(value) ->
            {:ok, value |> unquote(type).value() |> unquote(type).key()}
          %{unquote(name) => value}, _, _ when is_binary(value) ->
            valid_value? =
              unquote(type).__message_props__.field_props
              |> Enum.map(fn {_, f} -> to_string(f.name_atom) end)
              |> Enum.member?(value)

            if valid_value? do
              {:ok, String.to_atom(value)}
            else
              {:error, :invalid_enum_value}
            end
          %{unquote(name) => values}, _, _ when is_list(values) ->
            possible_values =
              unquote(type).__message_props__.field_props
              |> Enum.map(fn {_, f} -> to_string(f.name_atom) end)

            standardized_values =
              Enum.map(values, fn(val) ->
                cond do
                  is_integer(val) ->
                    unquote(type).key(val)
                  is_atom(val) ->
                    val |> unquote(type).value() |> unquote(type).key()
                  is_binary(val) ->
                    String.to_atom(val)
                  true ->
                    nil
                end
              end)

            valid_values? =
              Enum.all?(standardized_values, &(Enum.member?(possible_values, to_string(&1))))

            if valid_values? do
              {:ok, standardized_values }
            else
              {:error, :invalid_enum_values}
            end
          _, _, _ ->
            {:ok, nil}
        end
      end

    Keyword.put(attrs, :resolve, res)
  end

  def enum_resolver_for_props(attrs, _), do: attrs
end
