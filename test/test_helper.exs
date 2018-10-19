:os.cmd('protoc -I ./test/protos --elixir_out=plugins=grpc:./test/protos ./test/protos/absinthe_proto/test.proto --descriptor_set_out=./test/protos/bundle')
:os.cmd('find test/support/absinthe_proto_test -name *.ex | xargs touch')

ExUnit.start()
