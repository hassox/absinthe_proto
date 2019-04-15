defmodule AbsintheProtoTest.Types do
  use AbsintheProto

  alias AbsintheProto.Objects.ForeignKey

  # build all proto messages found within a namespace
  build paths: Path.wildcard("#{__DIR__}/../../protos/**/*.pb.ex"),
        id_alias: ~r/^token$/,
        foreign_keys: [user: AbsintheProtoTest.ForeignKeys.User],
        namespace: AbsintheProto.Test

  do

    # create input objects when other apis need to use them
    input_objects [AbsintheProto.Test.User, AbsintheProto.Test.Oneof]

    # Modify an object before it's generated. Add/Remove/Update field definitions
    modify AbsintheProto.Test.User do
      exclude_fields [:field_to_remove]

      add_field :another_field, non_null(:string), resolve: {AbsintheProtoTest.Resolver, :resolve_another_field}
    end

    modify AbsintheProto.Test.Oneof do
      exclude_fields [:field_to_remove]
    end

    modify AbsintheProto.Test.Service.Service do
      rpc_queries [:get_basic, :get_oneof]

      # update_rpc :get_basic, []
      update_rpc :get_oneof, resolve: {AbsintheProtoTest.Resolver, :resolve_get_oneof}
    end
  end

  build namespace: Google.Protobuf, otp_app: :protobuf
end
