defmodule AbsintheProto do
  @moduledoc """
  Provides macros for reading protobuf messages and providing them as absinthe graphql messages.
  """

  @doc """
  Imports the relevant macros from `AbsintheProto.DSL`
  """
  defmacro __using__(_opts \\ []) do
    quote location: :keep do
      require AbsintheProto.DSL
      @before_compile {AbsintheProto.DSL, :compile_protos_to_gql!}
      require Absinthe.Schema.Notation
      use Absinthe.Schema.Notation
      import AbsintheProto.DSL, only: :macros
    end
  end
end
