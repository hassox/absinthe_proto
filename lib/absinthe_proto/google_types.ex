defmodule AbsintheProto.GoogleTypes do
  use AbsintheProto

  # build Google, otp_app: :protobuf do
  #   input_objects [
  #     Google.Protobuf.StringValue
  #   ]
  # end

  build Google, otp_app: :google_protos do
    input_objects [
      Google.Protobuf.StringValue,
      Google.Protobuf.Timestamp,
    ]
  end

  object :google__protobuf__field_mask do
    field :paths, list_of(:string)
  end

  input_object :google__protobuf__field_mask__input_object do
    field :paths, list_of(:string)
  end
end
