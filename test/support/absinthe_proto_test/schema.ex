defmodule AbsintheProtoTest.Schema do
  use Absinthe.Schema

  require AbsintheProtoTest.Types

  import_types AbsintheProto.Scalars
  import_types AbsintheProto.GoogleTypes
  import_types AbsintheProtoTest.Types

  query do
    field :basic, :absinthe_proto__test__basic, resolve: &test_basic_resolver/3
    field :oneof, :absinthe_proto__test__oneof, resolve: &test_oneof_resolver/3
    field :user, :absinthe_proto__test__user, resolve: &test_user_resolver/3
    field :repeated_nested, :absinthe_proto__test__repeated_nested, resolve: &test_repeated_nested_resolver/3
    field :file_descriptor_set, :google__protobuf__file_descriptor_set, resolve: &descriptor_resolver/3

    import_fields :absinthe_proto__test__service__service__queries
  end

  def noop_resolver(_, _, _), do: {:ok, nil}

  def descriptor_resolver(_, _, _) do
    IO.puts("Loading proto bundle")
    set =
      "#{__DIR__}/../../protos/bundle"
      |> File.read!()
      |> Google.Protobuf.FileDescriptorSet.decode()

    IO.puts("Finished Loading proto bundle")
    {:ok, set}
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

  def test_repeated_nested_resolver(_, _, _) do
    {:ok, basic} = test_basic_resolver(:a, :a, :a)
    {:ok, %{basics: [basic, basic, basic]}}
  end
end
