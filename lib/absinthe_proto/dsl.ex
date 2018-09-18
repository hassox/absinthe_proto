defmodule AbsintheProto.DSL do
  require AbsintheProto.Objects.GqlObject
  require AbsintheProto.Objects.GqlObject.GqlField
  require AbsintheProto.Objects.GqlEnum
  require AbsintheProto.Objects.GqlEnum.GqlValue

  defmacro build(proto_namespace, load_files \\ []) do
    ns = Macro.expand(proto_namespace, __CALLER__)

    {load_files, _} = Module.eval_quoted(__CALLER__, load_files)
    for path <- load_files, do: Code.compile_file(path)

    # configurer = Module.get_attribute(__CALLER__.module, :absinthe_proto_mod)
    otp_app = Module.get_attribute(__CALLER__.module, :otp_app)
    msgs = AbsintheProto.DSL.messages_from_proto_namespace(ns)
    Module.put_attribute(__CALLER__.module, :proto_gql_messages, msgs)

    for {_, obj} <- msgs do
      case obj do
        %AbsintheProto.Objects.GqlObject{identifier: obj_id, attrs: obj_attrs, fields: fields} ->
          field_ast = for {id, %{attrs: attrs}} <- fields do
            quote do
              field unquote(id), unquote(attrs)
            end
          end

          quote do
            object unquote(obj_id), unquote(obj_attrs) do
              unquote_splicing(field_ast)
            end
          end
        %AbsintheProto.Objects.GqlEnum{identifier: enum_id, attrs: enum_attrs, values: values} ->
          value_ast = for %{identifier: ident, attrs: attrs} <- values do
            quote do
              value unquote(ident), unquote(attrs)
            end
          end

          quote do
            enum unquote(enum_id), unquote(enum_attrs) do
              unquote_splicing(value_ast)
            end
          end
      end
    end
  end

  def messages_from_proto_namespace(ns) do
    ns
    |> modules_for_namespace()
    |> proto_gql_objects()
  end

  defp modules_for_namespace(ns) do
    ns = to_string(ns)
    mods =
      :code.all_loaded()
      |> Enum.map(fn {m, _} -> m end)
      |> Enum.filter(fn m -> String.starts_with?(to_string(m), ns) end)
    {:ok, mods}
  end

  defp proto_gql_objects({:error, _} = err), do: err
  defp proto_gql_objects({:ok, mods}) do
    mods
    |> Enum.flat_map(&proto_gql_object/1)
    |> Enum.filter(&(&1 != nil))
    |> Enum.into(%{}, fn i ->
      {i.module, i}
    end)
  end

  defp proto_gql_object(mod) do
    mod
    |> proto_type()
    |> proto_gql_object(mod)
  end

  defp proto_gql_object(:unknown, _), do: []
  defp proto_gql_object(:message, mod) do
    [
      proto_default_oneof_objects(mod),
      proto_default_map_objects(mod),
      proto_default_message_object(mod)
    ]
    |> Enum.flat_map(&(&1))
  end

  defp proto_gql_object(:enum, mod) do
    %AbsintheProto.Objects.GqlEnum{
      gql_type: :enum,
      module: mod,
      identifier: gql_object_name(mod),
      attrs: [],
      values: Enum.map(mod.__message_props__.field_props, fn {_, p} ->
        %AbsintheProto.Objects.GqlEnum.GqlValue{identifier: p.name_atom, attrs: []}
      end),
    }
    |> List.wrap()
  end

  defp proto_gql_object(:service, mod), do: []

  defp proto_default_oneof_objects(mod, type \\ :object) do
    msg_props = mod.__message_props__
    case msg_props do
      %{oneof: []} ->
        []
      %{oneof: oneofs} ->
        for {field, id} <- oneofs, into: [] do
          field_props =
            msg_props.field_props
            |> Enum.map(fn {_, p} -> p end)
            |> Enum.filter(&(&1.oneof == id))

          %AbsintheProto.Objects.GqlObject{
            gql_type: type,
            module: nil,
            identifier: gql_object_name(mod, [:oneof, field]),
            attrs: [],
            fields: proto_fields(field_props),
          }
        end
    end
  end
  defp proto_default_map_objects(mod, type \\ :object), do: []
  defp proto_default_message_object(mod, type \\ :object) do
    %AbsintheProto.Objects.GqlObject{
      gql_type: type,
      module: mod,
      identifier: gql_object_name(mod),
      attrs: [],
      fields: %{}
    }
    |> proto_basic_message_fields()
    |> List.wrap()
  end

  defp proto_basic_message_fields(%{module: nil} = gql_object), do: gql_object
  defp proto_basic_message_fields(%{module: mod} = gql_object) do
    bare_props =
      Enum.map(mod.__message_props__.field_props, fn {_, props} -> props end)

    basic_field_props = Enum.filter(bare_props, &(&1.oneof == nil))
    fields = proto_fields(basic_field_props)

    fields =
      case mod.__message_props__.oneof do
        [] -> fields
        oneofs ->
          oneof_fields =
            for {ident, oneof_id} <- oneofs, into: fields do
              resolver = quote location: :keep do
                fn
                  %{unquote(ident) => {field_name, value}} = thing, _, _ ->
                    {:ok, Map.put(%{}, field_name, value)}
                  _, _, _ -> {:ok, nil}
                end
              end

              {
                ident,
                %AbsintheProto.Objects.GqlObject.GqlField{
                  identifier: ident,
                  attrs: [type: gql_object_name(mod, [:oneof, ident]), resolve: resolver],
                }
              }
          end
      end

    %{gql_object | fields: fields}
  end

  defp proto_fields(field_props, existing \\ %{}) do
    for props <- field_props, into: existing do
      f = %AbsintheProto.Objects.GqlObject.GqlField{identifier: props.name_atom}
      attrs =
        []
        |> datatype_for_props(props)
        |> wrap_datatype(props)
        |> enum_resolver_for_props(props)

      {f.identifier, %{f | attrs: attrs}}
    end
  end

  defp datatype_for_props(attrs, %{embedded?: true, type: type}),
    do: Keyword.put(attrs, :type, gql_object_name(type))

  defp datatype_for_props(attrs, %{enum?: true, enum_type: type}),
    do: Keyword.put(attrs, :type, gql_object_name(type))

  defp datatype_for_props(attrs, %{type: type}),
    do: Keyword.put(attrs, :type, AbsintheProto.Scalars.proto_to_gql_scalar(type))

  defp wrap_datatype(attrs, %{repeated?: true}) do
    datatype = Keyword.get(attrs, :type)
    content = quote do: %Absinthe.Type.List{of_type: %Absinthe.Type.NonNull{of_type: unquote(datatype)}}
    Keyword.put(attrs, :type, content)
  end

  defp wrap_datatype(attrs, _), do: attrs

  defp enum_resolver_for_props(attrs, %{name_atom: name, enum?: true, enum_type: type}) do
    res =
      quote do
        fn
          %{unquote(name) => value}, _, _ ->
            {:ok, unquote(type).key(value)}
          _, _, _ ->
            {:ok, nil}
        end
      end
    Keyword.put(attrs, :resolve, res)
  end

  defp enum_resolver_for_props(attrs, _), do: attrs

  defp proto_gql_type(:message), do: :object
  defp proto_gql_type(:enum), do: :enum
  defp proto_gql_type(:service), do: :object

  defp proto_type(m) do
    try do
      funs =
        :functions
        |> m.__info__()
        |> Enum.into(%{})

      case funs do
        %{__rpc_calls__: 0} ->
          :service
        %{__message_props__: 0} ->
          case m.__message_props__ do
            %{enum?: true} -> :enum
            _ -> :message
          end
        _ -> :unknown
      end
    rescue
      _ -> :unknown
    end
  end

  defp gql_object_name(mod, other_parts \\ []) do
    [Macro.underscore(mod) | other_parts]
    |> Enum.map(fn i ->
      i |> to_string() |> Macro.underscore() |> String.replace("/", "__")
    end)
    |> Enum.join("__")
    |> String.to_atom()
  end
end
