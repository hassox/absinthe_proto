defmodule AbsintheProto.GoogleTypes do
  use AbsintheProto

  build Google, otp_app: :google_protos do
    input_objects [
      Google.Protobuf.Any,
      Google.Protobuf.BytesValue,
      Google.Protobuf.BoolValue,
      Google.Protobuf.DoubleValue,
      Google.Protobuf.FloatValue,
      Google.Protobuf.Int32Value,
      Google.Protobuf.Int64Value,
      Google.Protobuf.StringValue,
      Google.Protobuf.UInt32Value,
      Google.Protobuf.UInt64Value,
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
