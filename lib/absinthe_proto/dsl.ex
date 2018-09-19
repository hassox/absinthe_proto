defmodule AbsintheProto.DSL do
  @moduledoc """
  Provides a DSL for importing Proto messages and converting to GraphQL types.
  """
  require AbsintheProto.Objects.GqlObject
  require AbsintheProto.Objects.GqlObject.GqlField
  require AbsintheProto.Objects.GqlEnum
  require AbsintheProto.Objects.GqlEnum.GqlValue

  @type build_opts :: [paths: [String.t]] | [otp_app: atom]

  @custom_field_attrs [:non_null]

  @doc """
  Build all protos found within the namespace.

  We need to give the compiler some help to find all the modules available.

  For this we use options to either provide paths to files containing our modules or an otp_app.

  ### `:paths` vs `:otp_app`

  Both are evaluated at compile time so are safe to use inside packages.

  If your compiled protos live in the same otp_application as you're using, you'll need to use
  the `:paths` option.

      build MyProto.Package, paths: Path.wildcard("#{__DIR__}/relative/path/**/*.pb.ex")

   If you're compiled protos live in a separate otp application, use the `:otp_app` option.
   This option is more efficient than the `:paths` option

   If you need to modify the fields you can pass build a block.
  """
  defmacro build(proto_namespace, options, blk \\ [do: []]) do
    ns = Macro.expand(proto_namespace, __CALLER__)
    opts = Module.eval_quoted(__CALLER__, options)

    mods =
      case opts do
        nil -> nil
        {[paths: load_files], _} when is_list(load_files) ->
          for path <- load_files, do: Code.compile_file(path)
          Enum.map(:code.all_loaded(), fn {m, _} -> m end)

        {[otp_app: app], _} when is_atom(app) ->
          Application.ensure_all_started(app)
          {:ok, m} = :application.get_key(app, :modules)
          m
        _ ->
          raise "unknown options given to AbsintheProto.DSL.build"
      end

    Module.put_attribute(__CALLER__.module, :proto_namespace, ns)

    otp_app = Module.get_attribute(__CALLER__.module, :otp_app)
    msgs = AbsintheProto.DSL.messages_from_proto_namespace(ns, mods)
    Module.put_attribute(__CALLER__.module, :proto_gql_messages, msgs)

    Module.eval_quoted(__CALLER__, blk)

    msgs = Module.get_attribute(__CALLER__.module, :proto_gql_messages)

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

  defmacro modify(proto_mod, blk) do
    mod = Macro.expand(proto_mod, __CALLER__)
    Module.put_attribute(__CALLER__.module, :modify_proto_mod, mod)
    ns = Module.get_attribute(__CALLER__.module, :proto_namespace)
    maybe_raise_not_modifying_object(mod, ns, __CALLER__)
    Module.eval_quoted(__CALLER__, blk)
  after
    Module.delete_attribute(__CALLER__.module, :modify_proto_mod)
  end

  @doc """
  Excludes fields from a proto message
  """
  defmacro exclude_fields(fields) do
    ns = Module.get_attribute(__CALLER__.module, :proto_namespace)
    mod = Module.get_attribute(__CALLER__.module, :modify_proto_mod)
    maybe_raise_not_modifying_object(mod, ns, __CALLER__)

    gql_messages = Module.get_attribute(__CALLER__.module, :proto_gql_messages)

    {excluded_fields, _} = Module.eval_quoted(__CALLER__, fields)

    identifier = gql_object_name(mod)

    case Map.get(gql_messages, identifier) do
      nil -> raise "cannot find gql object #{inspect(identifier)}"
      %AbsintheProto.Objects.GqlObject{} = obj ->
        new_msgs = remove_fields(gql_messages, obj, mod, excluded_fields)
        Module.put_attribute(__CALLER__.module, :proto_gql_messages, new_msgs)
      _ ->
        raise "exclude_fields is only applicable to proto messages"
    end
  end

  defmacro update_field(field_name, attrs) do
    ns = Module.get_attribute(__CALLER__.module, :proto_namespace)
    mod = Module.get_attribute(__CALLER__.module, :modify_proto_mod)
    maybe_raise_not_modifying_object(mod, ns, __CALLER__)

    gql_messages = Module.get_attribute(__CALLER__.module, :proto_gql_messages)

    {new_attrs, _} = Module.eval_quoted(__CALLER__, attrs)
    {field_name, _} = Module.eval_quoted(__CALLER__, field_name)

    case Enum.find(mod.__message_props__.field_props, fn {_, p} -> p.name_atom == field_name end) do
      nil ->
        raise "could not find field #{inspect(field_name)} in #{mod}"
      {_, %{oneof: nil}} ->
        obj_name = gql_object_name(mod)
        case Map.get(gql_messages, obj_name) do
          nil -> raise "could not find gql message #{obj_name}"
          %{fields: fields} = obj ->
            do_update_field(__CALLER__.module, gql_messages, obj, field_name, new_attrs)
        end
      {_, %{oneof: oneof_id} = props} ->
    end
  end

  defmacro add_field(field_name, datatype, attrs \\ []) do
    ns = Module.get_attribute(__CALLER__.module, :proto_namespace)
    mod = Module.get_attribute(__CALLER__.module, :modify_proto_mod)
    maybe_raise_not_modifying_object(mod, ns, __CALLER__)

    gql_messages = Module.get_attribute(__CALLER__.module, :proto_gql_messages)
    obj_name = gql_object_name(mod)
    obj = Map.get(gql_messages, obj_name)
    if !obj do
      raise "could not find gql object #{obj_name}"
    end

    {ident, _} = Module.eval_quoted(__CALLER__, field_name)
    {attrs, _} = Module.eval_quoted(__CALLER__, attrs)
    attrs = for {k, v} <- attrs, into: [], do: {k, quote do: unquote(v)}
    attrs = Keyword.put(attrs, :type, datatype)

    new_field = %AbsintheProto.Objects.GqlObject.GqlField{
      identifier: ident,
      attrs: attrs,
    }
    new_obj = %{obj | fields: Map.put(obj.fields, new_field.identifier, new_field)}
    gql_messages = Map.put(gql_messages, new_obj.identifier, new_obj)
    Module.put_attribute(__CALLER__.module, :proto_gql_messages, gql_messages)
  end

  defp do_update_field(caller_mod, gql_messages, obj, field_name, new_attrs) do
    new_fields = update_field_attrs(obj.fields, field_name, new_attrs)
    obj = %{obj | fields: new_fields}
    Module.put_attribute(caller_mod, :proto_gql_messages, Map.put(gql_messages, obj.identifier, obj))
  end

  defp update_field_attrs(fields, field_name, new_attrs) do
    field = Map.get(fields, field_name)
    if !field do
      raise "could not find field #{field_name}"
    end

    attrs = field.attrs

    custom_attrs = Keyword.take(new_attrs, @custom_field_attrs)
    new_attrs = Keyword.drop(new_attrs, @custom_field_attrs)

    new_attrs =
      for {k, v} <- new_attrs, into: [], do: {k, quote do: unquote(v)}

    new_attrs = Keyword.merge(attrs, new_attrs)

    new_attrs =
      if Keyword.get(custom_attrs, :non_null) do
        type = Keyword.get(new_attrs, :type)
        content =
          quote bind_quoted: [type: Macro.escape(type, unquote: true)] do
            non_null(type)
          end
        Keyword.put(new_attrs, :type, content)
      else
        new_attrs
      end

    Map.put(fields, field_name, %{field | attrs: new_attrs})
  end

  @doc false
  def messages_from_proto_namespace(ns, from_mods) do
    ns
    |> modules_for_namespace(from_mods)
    |> proto_gql_objects()
  end

  defp modules_for_namespace(ns, from_mods) do
    mods =
      from_mods
      |> Enum.filter(fn m -> within_namespace?(m, ns) end)
    {:ok, mods}
  end

  defp proto_gql_objects({:error, _} = err), do: err
  defp proto_gql_objects({:ok, mods}) do
    mods
    |> Enum.flat_map(&proto_gql_object/1)
    |> Enum.filter(&(&1 != nil))
    |> Enum.into(%{}, fn i ->
      {i.identifier, i}
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
            attrs: [description: "Only one of these fields may be set"],
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
    fields = create_message_oneof_fields(mod, fields)

    %{gql_object | fields: fields}
  end

  defp create_message_oneof_fields(mod, fields \\ []) do
    case mod.__message_props__.oneof do
      [] -> fields
      oneofs ->
        for {ident, _oneof_id} <- oneofs, into: fields do
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
              orig?: true,
            }
          }
      end
    end
  end

  defp proto_fields(field_props, existing \\ %{}) do
    for props <- field_props, into: existing do
      f = %AbsintheProto.Objects.GqlObject.GqlField{identifier: props.name_atom, orig?: true}
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

  defp raise_not_modifying_object(ns) do
    raise "not currently modifying an object in #{ns}"
  end

  defp remove_fields(msgs, %AbsintheProto.Objects.GqlObject{} = obj, mod, fields) do
    # remove oneof fields
    removed_field_props =
      for {_, props} <- mod.__message_props__.field_props,
          Enum.member?(fields, props.name_atom),
          into: [],
          do: props

    obj = %{obj | fields: Map.drop(obj.fields, fields)}
    msgs = Map.put(msgs, obj.identifier, obj)
    oneof_fields_by_name =
      removed_field_props
      |> Enum.filter(fn p -> p.oneof != nil end)
      |> Enum.map(fn p ->
        oneof_ident = Enum.find(mod.__message_props__.oneof, fn {_name, id} -> id == p.oneof end)
        case oneof_ident do
          {name, _} -> %{oneof_name: name, field_name: p.name_atom}
          _ -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))
      |> Enum.group_by(fn i -> Map.get(i, :oneof_name) end)

    Enum.reduce oneof_fields_by_name, msgs, fn {oneof_ident, items}, acc ->
      obj_name = gql_object_name(mod, [:oneof, oneof_ident])
      case Map.get(acc, obj_name) do
        nil -> raise "cannot find the oneof object for #{mod}"
        %{fields: fields} = oneof_obj ->
          field_names = Enum.map(items, &(&1.field_name))
          oneof_obj = %{oneof_obj | fields: Map.drop(fields, field_names)}
          Map.put(acc, obj_name, oneof_obj)
      end
    end
  end

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

  defp within_namespace?(mod, ns) do
    String.starts_with?(to_string(mod), to_string(ns))
  end

  defp maybe_raise_not_modifying_object(nil, ns, env) do
    raise """
      not modifying object within #{ns} (#{env.module} - #{env.file}:#{env.line})
    """
  end
  defp maybe_raise_not_modifying_object(_, _, _), do: :nothing

  defp maybe_raise_not_within_namespace(mod, ns, env) do
    unless within_namespace?(mod, ns) do
      raise """
        cannot modify #{mod}. It is not within #{ns} (#{env.module} - #{env.file}:#{env.line})
      """
    end
  end
end
