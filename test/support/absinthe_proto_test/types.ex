defmodule AbsintheProtoTest.Types do
  use AbsintheProto

  # build all proto messages found within a namespace
  build AbsintheProto.Test, paths: Path.wildcard("#{__DIR__}/../../protos/absinthe_proto/**/*.ex") do
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
  end

  build Google.Protobuf, otp_app: :protobuf

  def resolve_extra(_, _, _), do: {:ok, 77}
  def resolve_another_field(_, _, _), do: {:ok, "Another field yo"}
end
