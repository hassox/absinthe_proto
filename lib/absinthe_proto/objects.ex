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

  defmodule GqlObject do
    defstruct AbsintheProto.ObjectFields.object_fields()

    defmodule GqlField do
      defstruct [:identifier, :attrs, :orig?]
    end
  end

  defmodule GqlEnum do
    defstruct [:gql_type, :identifier, :attrs, values: [], module: nil]
    defmodule GqlValue do
      defstruct [:identifier, attrs: []]
    end
  end
end
