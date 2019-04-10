defmodule AbsintheProtoTest.ClientBuilder do
  @behaviour AbsintheProto.Client

  def build_client(service, client_name) do
    quoted_source =
      for {raw_name, _, _} <- service.__rpc_calls__ do
        fun_name = AbsintheProto.Utils.rpc_name_to_gql_name(raw_name)

        quote location: :keep do
          def unquote(fun_name)(args, opts \\ []) do
          end
        end
      end
    
    Module.create(client_name, quoted_source, Macro.Env.location(__ENV__))
  end
end