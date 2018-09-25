defmodule AbsintheProtoTest.ForeignKeys.User do
  use AbsintheProto.ForeignKey

  def matcher(_obj, field) do
    field.identifier |> to_string() |> String.match?(~r/(user_token|user_id|user_uuid|_by_token|_by_id|_by_uuid)$/)
  end

  def output_field_name(obj, field) do
    case Regex.run(~r/.+(_token|_id|_uuid)$/, to_string(field.identifier)) do
      [full, suffix] ->
        full
        |> String.replace(~r|#{suffix}$|, "")
        |> String.to_atom()
      _ ->
        raise "could not find output_field_name for foreign key #{__MODULE__} #{inspect(obj.identifier)} - #{inspect(field.identifier)}"
    end
  end

  def output_field_type(_, _), do: :absinthe_proto__test__user

  def one_resolver(_obj, field) do
    field_identifier = field.identifier

    quote do
      fn
        %{unquote(field_identifier) => val}, _, r ->
          AbsintheProtoTest.ForeignKeys.User.resolve_user(%{}, %{id: val}, r)
        _, _, r ->
          AbsintheProtoTest.ForeignKeys.User.resolve_user(%{}, %{}, r)
      end
    end
  end

  def many_resolver(_obj, field) do
    field_identifier = field.identifier

    quote do
      fn
        %{unquote(field_identifier) => val}, _, r ->
          AbsintheProtoTest.ForeignKeys.User.resolve_users(%{}, %{ids: val}, r)
        _, _, r ->
          AbsintheProtoTest.ForeignKeys.User.resolve_users(%{}, %{}, r)
      end
    end
  end

  def resolve_user(_, _args, _r) do
    {:ok,
      AbsintheProto.Test.User.new(%{
        token: "ABCDE",
        name: "Bob Belcher",
        extra_field: 34
      })
    }
  end

  def resolve_users(_, _args, _r) do
    {:ok,
      [
        AbsintheProto.Test.User.new(%{
          token: "ABCDE",
          name: "Bob Belcher",
          extra_field: 34
        })
      ]
    }
  end
end
