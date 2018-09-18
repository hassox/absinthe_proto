defmodule AbsintheProtoTest.Schema do
  use Absinthe.Schema

  require AbsintheProtoTest.Types

  import_types AbsintheProto.Scalars
  import_types AbsintheProtoTest.Types

  query do
    field :basic, :absinthe_proto__test__basic, resolve: &test_basic_resolver/3
    field :oneof, :absinthe_proto__test__oneof, resolve: &test_oneof_resolver/3
    field :string, :string
  end

  def test_basic_resolver(_, _, _) do
    {
      :ok,
      AbsintheProto.Test.Basic.new(%{
        name: "Fred",
        enum_value: 0,
      })
    }
  end

  def test_oneof_resolver(_, _, _) do
    result =
      {
        :ok,
        AbsintheProto.Test.Oneof.new(%{
          id: "Fred",
          union_enum: {:enum_value, 1}
        })
      }
    IO.inspect(result)
    result
  end
end
