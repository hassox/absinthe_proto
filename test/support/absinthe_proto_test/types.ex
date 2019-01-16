defmodule AbsintheProtoTest.Types do
  use AbsintheProto

  alias AbsintheProto.Objects.ForeignKey

  # build all proto messages found within a namespace
  build AbsintheProto.Test,
        paths: Path.wildcard("#{__DIR__}/../../protos/**/*.pb.ex"),
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
                   resolve: {AbsintheProtoTest.Resolver, :resolve_extra}

      add_field :another_field, non_null(:string), resolve: {AbsintheProtoTest.Resolver, :resolve_another_field}
    end

    modify AbsintheProto.Test.Oneof do
      exclude_fields [:field_to_remove]
    end

    modify AbsintheProto.Test.Service.Service do
      rpc_queries [:get_basic, :get_oneof]
      service_resolver AbsintheProtoTest.Resolver

      # update_rpc :get_basic, []
      update_rpc :get_oneof, resolve: {AbsintheProtoTest.Resolver, :resolve_get_oneof}
    end
  end

  build Google.Protobuf, otp_app: :protobuf
end
