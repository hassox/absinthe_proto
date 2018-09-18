{_, 0} = System.cmd(
  "protoc",
  ~w(
    -I
    ./test/protos
    --elixir_out=./test/protos
    ./test/protos/absinthe_proto/test.proto
  )
)

ExUnit.start()
