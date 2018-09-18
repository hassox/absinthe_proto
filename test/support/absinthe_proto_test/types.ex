defmodule AbsintheProtoTest.Types do
  use AbsintheProtoTest.ProtoConfig

  build AbsintheProto.Test, Path.wildcard("#{__DIR__}/../../protos/absinthe_proto/**/*.ex")
  
end
