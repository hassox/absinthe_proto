defmodule AbsintheProto.ObjectFields do
  @moduledoc false
  def object_fields,
    do: [:gql_type, :identifier, :attrs, fields: %{}, module: nil]
end

defmodule AbsintheProto.Objects do
  require AbsintheProto.ObjectFields

  defmodule Build do
    defstruct [
      :id_alias,
      :namespace, # done
      foreign_keys: [],
      ignored_objects: MapSet.new(),
      input_objects: MapSet.new(),
      messages: %{}, # done
    ]
  end

  defmodule Message do
    defstruct [
      :gql_name,
      :module,
      :proto_type,
      :service_resolver,
      excluded_fields: MapSet.new(),
      updated_rpcs: %{},
      rpc_queries: MapSet.new(),
      additional_fields: %{},
      resolved_fields: %{},
    ]
  end

  defmodule Blueprint do
    defmodule Enum do
      defstruct [
        message: nil,
        identifier: nil,
        values: []
      ]
    end

    defmodule Message do
      defstruct [
        identifier: nil,
        message: nil,
        raw_field_map: %{},
        additional_field_map: %{},
        oneof_field_map: %{},
      ]
    end

    defmodule MessageField do
      defstruct [
        :identifier,
        :proto_datatype,
        :proto_field_props,
        list?: false,
        attrs: nil,
      ]
    end

    defmodule Service do
      defstruct [
        :identifier,
        :resolver,
        :proto_module,
        :message,
        queries: MapSet.new(),
      ]

      defmodule RPCCall do
        defstruct [
          :identifier,
          :output_object,
          args: [],
          input_objects: MapSet.new(),
        ]
      end
    end
  end

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
