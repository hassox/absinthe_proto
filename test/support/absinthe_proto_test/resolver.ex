defmodule AbsintheProtoTest.Resolver do
  def resolve_another_field(_, _, _), do: {:ok, "Another field yo"}

  def resolve_get_oneof(_p, _args, _r) do
    {
      :ok,
      AbsintheProto.Test.Oneof.new(%{
        id: "Fred",
        union_enum: {:int_value, 345}
      })
    }
  end
end
