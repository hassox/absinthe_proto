defmodule AbsintheProto.GoogleTypes do
  use AbsintheProto

  # build Google, otp_app: :protobuf do
  #   input_objects [
  #     Google.Protobuf.StringValue
  #   ]
  # end

  build Google, otp_app: :google_protos do
    input_objects [
      Google.Protobuf.StringValue
    ]
  end
end
