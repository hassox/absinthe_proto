defmodule AbsintheProtoTest.Resolver do
  def resolve_extra(_, _, _), do: {:ok, 77}
  def resolve_another_field(_, _, _), do: {:ok, "Another field yo"}

  def get_basic(_p, _args, _r) do
    {
      :ok,
      AbsintheProto.Test.Basic.new(%{
        name: "Fred",
        enum_value: 0,
      })
    }
  end

  def get_oneof(p, a, r), do: resolve_get_oneof(p, a, r)

  def resolve_get_oneof(_p, _args, _r) do
    {
      :ok,
      AbsintheProto.Test.Oneof.new(%{
        id: "Fred",
        union_enum: {:int_value, 345}
      })
    }
  end


  def test_user_resolver(_, _, _) do
    {
      :ok,
      AbsintheProto.Test.User.new(%{
        token: "ABCDE",
        name: "Bob Belcher",
        extra_field: 34
      })
    }
  end
end
