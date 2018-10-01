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
    {opts, _} = Module.eval_quoted(__CALLER__, options)
    Module.put_attribute(__CALLER__.module, :id_alias, nil)
    case Keyword.get(opts, :id_alias) do
      nil -> :nothing
      id_alias -> Module.put_attribute(__CALLER__.module, :id_alias, id_alias)
    end

    foreign_keys = Keyword.get(opts, :foreign_keys, [])

    mods =
      case Keyword.take(opts, [:paths, :otp_app]) do
        nil -> nil
        [paths: load_files] when is_list(load_files) ->
          load_files = Enum.map(load_files, &Path.expand/1)
          mod_strings =
          for path <- load_files, into: [] do
            "cat #{path} | grep defmodule | awk '{print $2}' | sort"
            |> String.to_charlist()
            |> :os.cmd()
            |> to_string()
            |> String.split("\n")
            |> Enum.filter(&(&1 != ""))
          end
          |> Enum.flat_map(&(&1))

          Enum.map(mod_strings, &(:"Elixir.#{&1}"))

        [otp_app: app] when is_atom(app) ->
          Application.ensure_all_started(app)
          {:ok, m} = :application.get_key(app, :modules)
          m
        [] ->
          raise "path or otp_app should be passed to AbsintheProto.DSL.build"
        _ ->
          raise "unknown options given to AbsintheProto.DSL.build"
      end

    Module.put_attribute(__CALLER__.module, :proto_namespace, ns)

    msgs = AbsintheProto.DSL.messages_from_proto_namespace(ns, mods)
    Module.put_attribute(__CALLER__.module, :proto_gql_messages, msgs)

    Module.eval_quoted(__CALLER__, blk)

    msgs =
      __CALLER__.module
      |> apply_id_alias()
      |> apply_foreign_keys(foreign_keys)

    Module.put_attribute(__CALLER__.module, :proto_gql_messages, msgs)

    for {_, obj} <- msgs do
      case obj do
        %AbsintheProto.Objects.GqlObject{identifier: obj_id, attrs: obj_attrs, fields: fields} ->
          field_ast =
            if Map.size(fields) == 0 do
              [
                quote do
                  field :noop, :boolean
                end
              ]
            else
              for {id, %{attrs: attrs}} <- fields do
                quote do
                  field unquote(id), unquote(attrs)
                end
              end
            end

          quote do
            object unquote(obj_id), unquote(obj_attrs) do
              unquote_splicing(field_ast)
            end
          end

        %AbsintheProto.Objects.GqlService{identifier: obj_id, attrs: obj_attrs, fields: fields} = srv ->
          query_field_ast =
            for {id, field} <- fields,
                field.identifier in srv.queries
            do
              attrs = service_attrs(field, srv)
              quote do
                field unquote(id), unquote(attrs)
              end
            end

          mutation_field_ast =
            for {id, field} <- fields,
                field.identifier not in srv.queries
            do
              attrs = service_attrs(field, srv)
              quote do
                field unquote(id), unquote(attrs)
              end
            end

          query_obj_id = :"#{obj_id}__queries"
          mutation_obj_id = :"#{obj_id}__mutations"

          quote do
            object unquote(query_obj_id), unquote(obj_attrs) do
              unquote_splicing(query_field_ast)
            end

            object unquote(mutation_obj_id), unquote(obj_attrs) do
              unquote_splicing(mutation_field_ast)
            end
          end

        %AbsintheProto.Objects.GqlInputObject{identifier: obj_id, attrs: obj_attrs, fields: fields} ->
          field_ast = for {id, %{attrs: attrs}} <- fields do
            quote do
              field unquote(id), unquote(attrs)
            end
          end

          quote do
            input_object unquote(obj_id), unquote(obj_attrs) do
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

    unless proto_type(mod) == :message do
      raise "cannot update_field on non message"
    end

    {new_attrs, _} = Module.eval_quoted(__CALLER__, attrs)
    {field_name, _} = Module.eval_quoted(__CALLER__, field_name)

    case Enum.find(mod.__message_props__.field_props, fn {_, p} -> p.name_atom == field_name end) do
      nil ->
        raise "could not find field #{inspect(field_name)} in #{mod}"
      {_, %{oneof: nil}} ->
        obj_name = gql_object_name(mod)
        case Map.get(gql_messages, obj_name) do
          nil -> raise "could not find gql message #{obj_name}"
          %{fields: _} = obj ->
            do_update_field(__CALLER__.module, gql_messages, obj, field_name, new_attrs)
        end
      {_, %{oneof: _oneof_id} = _props} -> :todo
    end
  end

  defmacro update_rpc(field_name, attrs) do
    ns = Module.get_attribute(__CALLER__.module, :proto_namespace)
    mod = Module.get_attribute(__CALLER__.module, :modify_proto_mod)
    maybe_raise_not_modifying_object(mod, ns, __CALLER__)
    gql_messages = Module.get_attribute(__CALLER__.module, :proto_gql_messages)
    obj_name = gql_object_name(mod)
    obj = Map.get(gql_messages, obj_name)

    unless proto_type(mod) == :service do
      raise "cannot update_rpc on non service"
    end

    {new_attrs, _} = Module.eval_quoted(__CALLER__, attrs)
    {field_name, _} = Module.eval_quoted(__CALLER__, field_name)

    do_update_field(__CALLER__.module, gql_messages, obj, field_name, new_attrs)
  end

  defmacro service_resolver(rmod) do
    ns = Module.get_attribute(__CALLER__.module, :proto_namespace)
    mod = Module.get_attribute(__CALLER__.module, :modify_proto_mod)
    maybe_raise_not_modifying_object(mod, ns, __CALLER__)
    gql_messages = Module.get_attribute(__CALLER__.module, :proto_gql_messages)
    obj_name = gql_object_name(mod)
    obj = Map.get(gql_messages, obj_name)
    {resolver_mod, _} = Module.eval_quoted(__CALLER__, rmod)

    unless mod do
      raise "not modifying a service"
    end

    unless proto_type(mod) == :service do
      raise "cannot set service_resolver on non service"
    end

    unless obj do
      raise "cannot find object for #{obj_name}"
    end

    new_msgs = Map.put(gql_messages, obj.identifier, %{obj | resolver_module: resolver_mod})
    Module.put_attribute(__CALLER__.module, :proto_gql_messages, new_msgs)
  end

  defmacro rpc_queries(raw_queries) do
    ns = Module.get_attribute(__CALLER__.module, :proto_namespace)
    mod = Module.get_attribute(__CALLER__.module, :modify_proto_mod)
    maybe_raise_not_modifying_object(mod, ns, __CALLER__)
    gql_messages = Module.get_attribute(__CALLER__.module, :proto_gql_messages)
    obj_name = gql_object_name(mod)
    obj = Map.get(gql_messages, obj_name)
    {queries, _} = Module.eval_quoted(__CALLER__, raw_queries)

    unless proto_type(mod) == :service do
      raise "cannot update_field on non message"
    end

    new_msgs = Map.put(gql_messages, obj.identifier, %{obj | queries: queries})
    Module.put_attribute(__CALLER__.module, :proto_gql_messages, new_msgs)
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

  defmacro input_objects(objs) do
    {objs, _} = Module.eval_quoted(__CALLER__, objs)
    for obj <- objs do
      create_input_object(__CALLER__.module, obj)
    end
  end

  defp apply_id_alias(mod) do
    id_alias = Module.get_attribute(mod, :id_alias)
    gql_messages = Module.get_attribute(mod, :proto_gql_messages)
    apply_id_alias(gql_messages, id_alias)
  end

  defp apply_id_alias(gql_messages, nil), do: gql_messages
  defp apply_id_alias(gql_messages, %Regex{} = id_alias) do
    apply_id_alias gql_messages, fn {field_id, _} ->
      Regex.match?(id_alias, to_string(field_id))
    end
  end

  defp apply_id_alias(gql_messages, id_alias) when is_function(id_alias) do
    Enum.reduce gql_messages, gql_messages, fn
      {_, %AbsintheProto.Objects.GqlObject{fields: %{id: _}}}, acc -> acc
      {obj_id, %AbsintheProto.Objects.GqlObject{} = obj}, acc ->
        case Enum.find(obj.fields, id_alias) do
          nil -> acc
          {field_id, field} ->
            resolver = quote do
              fn(%{unquote(field_id) => val}, _, _) ->
                {:ok, val}
              end
            end

            id_attrs =
              field.attrs
              |> Keyword.take([:type])
              |> Keyword.put(:resolve, resolver)

            id_field = %AbsintheProto.Objects.GqlObject.GqlField{
              identifier: :id,
              attrs: id_attrs
            }

            obj = %{obj | fields: Map.put(obj.fields, :id, id_field)}
            Map.put(acc, obj_id, obj)
        end
      _, acc -> acc
    end
  end

  defp apply_id_alias(gql_messages, id_alias) do
    apply_id_alias gql_messages, fn {field_id, _} ->
      field_id == id_alias
    end
  end

  defp apply_foreign_keys(gql_messages, []), do: gql_messages
  defp apply_foreign_keys(gql_messages, foreign_keys) do
    Enum.map gql_messages, fn
      {obj_id, %AbsintheProto.Objects.GqlObject{} = obj} ->
        # go over the fields defined and see if they match
        new_fields =
          obj.fields
          |> Enum.map(fn {id, field} -> maybe_create_foreign_key({id, field}, obj, foreign_keys) end)
          |> Enum.filter(&(&1 != nil))
          |> Enum.into(%{})

        {obj_id, %{obj | fields: Map.merge(obj.fields, new_fields)}}
      item ->
        item
    end
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

  defp create_input_object(within_mod, mod) do
    ns = Module.get_attribute(within_mod, :proto_namespace)
    gql_messages = Module.get_attribute(within_mod, :proto_gql_messages)
    if !within_namespace?(mod, ns) do
      raise "cannot create input object for #{mod}. It is not within the #{ns} namespace"
    end

    obj_name = gql_object_name(mod, [:input_object])

    # we only want to create this once
    with obj when is_nil(obj) <- Map.get(gql_messages, obj_name) do
      input_objs =
        for o <- proto_gql_object(:input, mod, ns), into: %{}, do: {o.identifier, o}

      gql_messages = Map.merge(gql_messages, input_objs)
      Module.put_attribute(within_mod, :proto_gql_messages, gql_messages)
    else
      _ -> nil
    end
  end

  @doc false
  def messages_from_proto_namespace(ns, from_mods) do
    ns
    |> modules_for_namespace(from_mods)
    |> proto_gql_objects(ns)
  end

  defp modules_for_namespace(ns, from_mods) do
    mods =
      from_mods
      |> Enum.filter(fn m -> within_namespace?(m, ns) end)
    {:ok, mods}
  end

  defp proto_gql_objects({:error, _} = err, _ns), do: err
  defp proto_gql_objects({:ok, mods}, ns) do
    mods
    |> Enum.flat_map(fn x -> proto_gql_object(x, ns) end)
    |> List.flatten()
    |> Enum.filter(&(&1 != nil))
    |> Enum.into(%{}, fn i ->
      {i.identifier, i}
    end)
  end

  defp proto_gql_object(mod, ns) do
    mod
    |> proto_type()
    |> proto_gql_object(mod, ns)
  end

  defp proto_gql_object(:unknown, _, _ns), do: []
  defp proto_gql_object(:message, mod, ns) do
    name_opts = []
    [
      proto_default_oneof_objects(mod, name_opts, AbsintheProto.Objects.GqlObject, ns),
      proto_default_map_objects(mod, name_opts, AbsintheProto.Objects.GqlObject, ns),
      proto_default_message_object(mod, name_opts, AbsintheProto.Objects.GqlObject, ns)
    ]
    |> Enum.flat_map(&(&1))
  end

  defp proto_gql_object(:input, mod, ns) do
    name_opts = [:input_object]
    out =
      [
        proto_default_oneof_objects(mod, name_opts, AbsintheProto.Objects.GqlInputObject, ns),
        proto_default_map_objects(mod, name_opts, AbsintheProto.Objects.GqlInputObject, ns),
        proto_default_message_object(mod, name_opts, AbsintheProto.Objects.GqlInputObject, ns)
      ]
      |> Enum.flat_map(&(&1))

    # need to go through and create new input objects for embedded messages
    result =
    Enum.reduce mod.__message_props__.field_props, out, fn
      {_, %{embedded?: true, type: type}}, acc ->
        if within_namespace?(type, ns) do
          :input
          |> proto_gql_object(type, ns)
          |> Enum.concat(acc)
        else
          acc
        end
      _, acc -> acc
    end
    result
  end

  defp proto_gql_object(:enum, mod, _ns) do
    %AbsintheProto.Objects.GqlEnum{
      module: mod,
      identifier: gql_object_name(mod),
      attrs: [],
      values: Enum.map(mod.__message_props__.field_props, fn {_, p} ->
        %AbsintheProto.Objects.GqlEnum.GqlValue{identifier: p.name_atom, attrs: []}
      end),
    }
    |> List.wrap()
  end

  defp proto_gql_object(:service, mod, ns) do
    calls = mod.__rpc_calls__

    # create input objects
    other_objs =
      for {_, {input, _}, {_, _}} <- calls, into: [] do
        objs = proto_default_oneof_objects(input, [:input_object], AbsintheProto.Objects.GqlInputObject, ns)

        field_objs =
          for {_, props} <- input.__message_props__.field_props,
              props.embedded?,
              within_namespace?(props.type, ns),
              into: [],
              do: proto_gql_object(:input, props.type, ns)
        objs ++ field_objs
      end
    other_objs = Enum.flat_map(other_objs, &(&1))

    obj = %AbsintheProto.Objects.GqlService{
      gql_type: :service,
      identifier: gql_object_name(mod),
      module: mod,
      attrs: [],
      fields: %{},
    }

    Enum.reduce(mod.__rpc_calls__(), obj, fn {method, {input, _}, {output, _}}, acc ->
      field_name = method |> to_string() |> Macro.underscore() |> String.to_atom()
      output_type = gql_object_name(output)
      args =
        for {_, props} <- input.__message_props__.field_props,
            props.oneof == nil,
            into: %{}
         do
          datatype =
            []
            |> datatype_for_props(props, [:input_object])
            |> wrap_datatype(props)
            |> Keyword.get(:type)

          {
            props.name_atom,
            [default_value: props.default, name: props.name_atom, type: datatype]
          }
        end

      args =
        Enum.reduce input.__message_props__.oneof || [], args, fn
          {field_name, _id}, acc ->
            output_type = gql_object_name(input, [:oneof, field_name, :input_object])
            arg = [name: field_name, type: quote do: unquote(output_type)]
            Map.put(acc, field_name, arg)
          _, acc -> acc
        end

      field =
        %AbsintheProto.Objects.GqlObject.GqlField{
          identifier: field_name,
          attrs: [args: args, type: quote do: unquote(output_type)],
        }
      %{obj | fields: Map.put(acc.fields, field.identifier, field)}
    end)
    |> List.wrap()
    |> Enum.concat(other_objs)
  end

  defp proto_default_oneof_objects(mod, name_opts, as_mod, _ns) do
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

          struct(
            as_mod,
            %{
              gql_type: :message,
              module: nil,
              identifier: gql_object_name(mod, [:oneof, field] ++ name_opts),
              attrs: [description: "Only one of these fields may be set"],
              fields: proto_fields(field_props, %{}, name_opts),
            }
          )
        end
    end
  end

  defp proto_default_map_objects(_mod, _name_opts, _as_mod, _ns), do: []
  defp proto_default_message_object(mod, name_opts, as_mod, _ns) do
    struct(
      as_mod,
      %{
        gql_type: :message,
        module: mod,
        identifier: gql_object_name(mod, name_opts),
        attrs: [],
        fields: %{}
      }
    )
    |> proto_basic_message_fields(name_opts)
    |> List.wrap()
  end

  defp proto_basic_message_fields(%{module: nil} = gql_object, _name_opts), do: gql_object
  defp proto_basic_message_fields(%{module: mod} = gql_object, name_opts) do
    bare_props =
      Enum.map(mod.__message_props__.field_props, fn {_, props} -> props end)

    basic_field_props = Enum.filter(bare_props, &(&1.oneof == nil))
    fields = proto_fields(basic_field_props, %{}, name_opts)
    fields = create_message_oneof_fields(mod, fields, name_opts)

    %{gql_object | fields: fields}
  end

  defp create_message_oneof_fields(mod, fields, name_opts) do
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
              attrs: [type: gql_object_name(mod, [:oneof, ident] ++ name_opts), resolve: resolver],
              orig?: true,
            }
          }
      end
    end
  end

  defp proto_fields(field_props, existing, name_opts) do
    for props <- field_props, into: existing do
      f = %AbsintheProto.Objects.GqlObject.GqlField{identifier: props.name_atom, orig?: true, list?: props.repeated?}
      attrs =
        []
        |> datatype_for_props(props, name_opts)
        |> wrap_datatype(props)
        |> enum_resolver_for_props(props)

      {f.identifier, %{f | attrs: attrs}}
    end
  end

  def datatype_for_props(attrs, props, name_opts)
  def datatype_for_props(attrs, %{embedded?: true, type: type}, name_opts),
    do: Keyword.put(attrs, :type, gql_object_name(type, name_opts))

  def datatype_for_props(attrs, %{enum?: true, enum_type: type}, _),
    do: Keyword.put(attrs, :type, gql_object_name(type))

  def datatype_for_props(attrs, %{type: type}, _),
    do: Keyword.put(attrs, :type, AbsintheProto.Scalars.proto_to_gql_scalar(type))

  def wrap_datatype(attrs, %{repeated?: true}) do
    datatype = Keyword.get(attrs, :type)
    content = quote do: %Absinthe.Type.List{of_type: %Absinthe.Type.NonNull{of_type: unquote(datatype)}}
    Keyword.put(attrs, :type, content)
  end

  def wrap_datatype(attrs, _), do: attrs

  defp enum_resolver_for_props(attrs, %{name_atom: name, enum?: true, enum_type: type}) do
    res =
      quote do
        fn
          %{unquote(name) => value}, _, _ when is_integer(value) ->
            {:ok, unquote(type).key(value)}
          %{unquote(name) => value}, _, _ when is_atom(value) ->
            {:ok, value |> unquote(type).value() |> unquote(type).key()}
          _, _, _ ->
            {:ok, nil}
        end
      end
    Keyword.put(attrs, :resolve, res)
  end

  defp enum_resolver_for_props(attrs, _), do: attrs

  defp maybe_create_foreign_key({_id, field}, gql_obj, foreign_keys) do
    if fk = Enum.find(foreign_keys, fn {_, fk} -> fk.matcher(gql_obj, field) end) do
      {_fk_name, fk} = fk
      ident = fk.output_field_name(gql_obj, field)
      dt = fk.output_field_type(gql_obj, field)
      resolver =
        if field.list? do
          fk.many_resolver(gql_obj, field)
        else
          fk.one_resolver(gql_obj, field)
        end
      {
        ident,
        %AbsintheProto.Objects.GqlObject.GqlField{
          identifier: ident,
          attrs: [
            type: (quote do: unquote(dt)),
            resolve: (quote do: unquote(resolver)),
          ],
        }
      }
    else
      nil
    end
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

  defp service_attrs(%{attrs: attrs} = field, srv) do
    if Keyword.has_key?(attrs, :resolve) do
      attrs
    else
      if srv.resolver_module == nil do
        raise "no resolver specified for #{srv.identifier}##{field.identifier}"
      else
        resolver_mod = srv.resolver_module
        field_id = field.identifier

        [resolve: quote do: {unquote(resolver_mod), unquote(field_id)}] ++ attrs
      end
    end
  end

  def gql_object_name(mod, other_parts \\ []) do
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
end
