defmodule AbsintheProto do
  defmacro __using__(opts) do
    otp_app = Keyword.get(opts, :otp_app)
    proto_mod = __CALLER__.module

    quote location: :keep, unquote: true do
      require AbsintheProto.DSL

      @otp_app unquote(otp_app)
      def otp_app, do: @otp_app

      Module.register_attribute(__MODULE__, :proto_foreign_keys, accumulate: false)
      @proto_foreign_keys %{}

      defmacro __using__(_ \\ []) do
        otp_app = unquote(otp_app)
        proto_mod = unquote(proto_mod)
        Module.register_attribute(__CALLER__.module, :proto_gql_messages, accumulate: false)
        Module.register_attribute(__CALLER__.module, :otp_app, accumulate: false)
        Module.register_attribute(__CALLER__.module, :absinthe_proto_mod, accumulate: false)
        Module.put_attribute(__CALLER__.module, :proto_gql_messages, %{})
        Module.put_attribute(__CALLER__.module, :otp_app, otp_app)
        Module.put_attribute(__CALLER__.module, :absinthe_proto_mod, __CALLER__.module)

        quote do
          require AbsintheProto.DSL
          require Absinthe.Schema.Notation
          use Absinthe.Schema.Notation
          import AbsintheProto.DSL, only: :macros

          def otp_app, do: @otp_app
        end
      end
    end
  end
end
