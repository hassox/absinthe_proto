defmodule AbsintheProto do
  defmacro __using__(opts \\ []) do
    quote location: :keep do
      Module.register_attribute(__MODULE__, :proto_gql_messages, accumulate: false)
      Module.put_attribute(__MODULE__, :proto_gql_messages, %{})

      require AbsintheProto.DSL
      require Absinthe.Schema.Notation
      use Absinthe.Schema.Notation
      import AbsintheProto.DSL, only: :macros
    end
  end
end
