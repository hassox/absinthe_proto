defmodule AbsintheProto do
  defmacro __using__(_opts \\ []) do
    quote location: :keep do
      # @before_compile AbsintheProto.Blueprinter
      # @before_compile AbsintheProto.Writer

      Module.register_attribute(__MODULE__, :ap_builds, accumulate: true)

      require AbsintheProto.DSL
      require Absinthe.Schema.Notation
      use Absinthe.Schema.Notation
      import AbsintheProto.DSL, only: :macros
    end
  end
end
