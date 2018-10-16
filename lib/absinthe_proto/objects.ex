defmodule AbsintheProto.ObjectFields do
  @moduledoc false
  def object_fields,
    do: [:gql_type, :identifier, :attrs, fields: %{}, module: nil]
end

defmodule AbsintheProto.Objects do
  require AbsintheProto.ObjectFields

  defmodule GqlInputObject do
    defstruct AbsintheProto.ObjectFields.object_fields()
  end

  defmodule GqlService do
    defstruct AbsintheProto.ObjectFields.object_fields() ++ [resolver_module: nil, queries: [], skip_args: %{}, required_args: %{}]
  end

  defmodule GqlObject do
    defstruct AbsintheProto.ObjectFields.object_fields()

    defmodule GqlField do
      defstruct [:identifier, :attrs, :orig?, :list?]
    end
  end

  defmodule GqlEnum do
    defstruct [:gql_type, :identifier, :attrs, values: [], module: nil]
    defmodule GqlValue do
      defstruct [:identifier, attrs: []]
    end
  end
end
