defmodule AbsintheProto.Objects do
  defmodule GqlObject do
    defstruct [:gql_type, :identifier, :attrs, fields: %{}, module: nil]

    defmodule GqlField do
      defstruct [:identifier, :attrs]
    end
  end

  defmodule GqlEnum do
    defstruct [:gql_type, :identifier, :attrs, values: [], module: nil]
    defmodule GqlValue do
      defstruct [:identifier, attrs: []]
    end
  end
end
