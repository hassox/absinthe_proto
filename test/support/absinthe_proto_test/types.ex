defmodule AbsintheProtoTest.Types do
  use AbsintheProto

  alias AbsintheProto.Objects.ForeignKey

  # build all proto messages found within a namespace
  build AbsintheProto.Test,
        paths: Path.wildcard("#{__DIR__}/../../protos/absinthe_proto/**/*.ex"),
        id_alias: :token,
        foreign_keys: [user: AbsintheProtoTest.ForeignKeys.User]
  do
    # create input objects when other apis need to use them
    input_objects [AbsintheProto.Test.User, AbsintheProto.Test.Oneof]

    # Modify an object before it's generated. Add/Remove/Update field definitions
    modify AbsintheProto.Test.User do
      exclude_fields [:field_to_remove]

      update_field :extra_field,
                   description: "Here is my extra field",
                   resolve: {__MODULE__, :resolve_extra}

      add_field :another_field, non_null(:string), resolve: {__MODULE__, :resolve_another_field}
    end

    modify AbsintheProto.Test.Oneof do
      exclude_fields [:field_to_remove]
    end

    modify AbsintheProto.Test.Service.Service do
      rpc_queries [:get_basic, :get_oneof]
      service_resolver __MODULE__

      # update_rpc :get_basic, []
      update_rpc :get_oneof, resolve: {__MODULE__, :resolve_get_oneof}
    end
  end

  build Google.Protobuf, otp_app: :protobuf

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
