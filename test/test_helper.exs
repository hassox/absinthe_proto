{_, 0} = System.cmd(
  "protoc",
  ~w(
    -I
    ./test/protos
    --elixir_out=plugins=grpc:./test/protos
    ./test/protos/absinthe_proto/test.proto
    --descriptor_set_out=./test/protos/bundle
  )
)

ExUnit.start()
