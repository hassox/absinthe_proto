defmodule AbsintheProto.DSL do

  @type foreign_key :: [
    namespaces: [module],
    foreign_key: module,
  ]

  @type options :: [
    namespace: module,
    foreign_keys: [foreign_key],
    id_aliases: [Regex.t],
    paths: paths,
    otp_app: otp_app,
  ]

  @type paths :: [String.t]
  @type otp_app :: :atom

  defstruct [
    namespace: nil,
    options: [],
    ignored_types: MapSet.new(),
    input_objects: MapSet.new(),
    excluded_fields: %{},
    added_fields: %{},
    rpc_queries: %{},
    raw_types: %{},
    updated_rpcs: %{},
  ]

  import AbsintheProto.Utils

  defmacro build(options, blk \\ [do: []]) do
    {opts, _} = Module.eval_quoted(__CALLER__, options)
    ns = Keyword.get(opts, :namespace)

    build_struct = %__MODULE__{options: opts, namespace: ns}

    save_draft_build(build_struct, __CALLER__.module)

    raw_types =
      case fetch_modules(Keyword.take(opts, [:paths, :otp_app])) do
        [] -> 
          raise "no proto messages found for #{} namespace"

        mods ->
          filter_proto_messages(mods, ns)
      end

    build_struct = %{build_struct | raw_types: raw_types}

    save_draft_build(build_struct, __CALLER__.module)

    Module.eval_quoted(__CALLER__, blk)

    compile_protos_to_gql!(__CALLER__.module)
  end

  defmacro ignore_objects(objs) do
    {objs, _} = Module.eval_quoted(__CALLER__, objs)

    build_struct = current_draft_build!(__CALLER__.module)

    ignored_types =
      objs
      |> MapSet.new()
      |> MapSet.union(build_struct.ignore_objects)
    
    build_struct = %{build_struct | ignored_types: ignored_types}
    save_draft_build(build_struct, __CALLER__.module)

    nil 
  end

  defmacro input_objects(objs) do
    {objs, _} = Module.eval_quoted(__CALLER__, objs)

    build_struct = current_draft_build!(__CALLER__.module)

    input_objects = 
      objs
      |> MapSet.new()
      |> MapSet.union(build_struct.input_objects)
    
    build_struct = %{build_struct | input_objects: input_objects}
    save_draft_build(build_struct, __CALLER__.module)

    nil
  end

  defmacro modify(mod, blk) do
    {mod, _} = Module.eval_quoted(__CALLER__, mod)
    save_current_proto_message(mod, __CALLER__.module)
    Module.eval_quoted(__CALLER__, blk)
    clear_current_proto_message(__CALLER__.module)
    nil
  end

  defmacro exclude_fields(fields) do
    {fields, _} = Module.eval_quoted(__CALLER__, fields)
    proto_mod = current_proto_message!(__CALLER__.module)

    build_struct = current_draft_build!(__CALLER__.module)

    new_excluded_fields = 
      build_struct.excluded_fields
      |> Map.get(proto_mod, MapSet.new())
      |> MapSet.union(MapSet.new(fields))

    excluded_fields = Map.put(build_struct.excluded_fields, proto_mod, new_excluded_fields)

    build_struct = %{build_struct | excluded_fields: excluded_fields}
    save_draft_build(build_struct, __CALLER__.module)

    nil
  end

  defmacro update_rpc(field_name, attrs) do
    {field_name, _} = Module.eval_quoted(__CALLER__, field_name)
    {attrs, _} = Module.eval_quoted(__CALLER__, attrs)
    proto_mod = current_proto_message!(__CALLER__.module)

    build_struct = current_draft_build!(__CALLER__.module)

    if !has_proto_type?(build_struct, proto_mod, :service), do: raise "#{proto_mod} is not an service. cannot update_rpc"

    mod_updated_rpcs = 
      build_struct.updated_rpcs
      |> Map.get(proto_mod, %{})
      |> Map.put(field_name, %{field_name: field_name, attrs: attrs})
    
    updated_rpcs = Map.put(build_struct.updated_rpcs, proto_mod, mod_updated_rpcs)

    build_struct = %{build_struct | updated_rpcs: updated_rpcs}
    save_draft_build(build_struct, __CALLER__.module)

    nil
  end

  defmacro rpc_queries(queries) do
    {queries, _} = Module.eval_quoted(__CALLER__, queries)
    proto_mod = current_proto_message!(__CALLER__.module)

    build_struct = current_draft_build!(__CALLER__.module)

    if !has_proto_type?(build_struct, proto_mod, :service), do: raise "#{proto_mod} is not a service"

    new_queries = 
      build_struct.rpc_queries
      |> Map.get(proto_mod, MapSet.new())
      |> MapSet.union(MapSet.new(queries))

    queries = Map.put(build_struct.rpc_queries, proto_mod, new_queries)

    build_struct = %{build_struct | rpc_queries: queries}
    save_draft_build(build_struct, __CALLER__.module)
    nil
  end

  defmacro add_field(field_name, datatype, attrs \\ []) do
    {field_name, _} = Module.eval_quoted(__CALLER__, field_name)
    proto_mod = current_proto_message!(__CALLER__.module)

    build_struct = current_draft_build!(__CALLER__.module)

    if has_proto_type?(build_struct, proto_mod, :enum), do: raise "#{proto_mod} is not an enum. cannot add fields"

    {attrs, _} = Module.eval_quoted(__CALLER__, attrs)
    attrs = for {k, v} <- attrs, into: [], do: {k, quote do: unquote(v)}
    attrs = Keyword.put(attrs, :type, datatype)

    mod_added_fields = 
      build_struct.added_fields
      |> Map.get(proto_mod, %{})
      |> Map.put(field_name, %{field_name: field_name, attrs: attrs})
    
    added_fields = Map.put(build_struct.added_fields, proto_mod, mod_added_fields)

    build_struct = %{build_struct | added_fields: added_fields}
    save_draft_build(build_struct, __CALLER__.module)

    nil
  end

  defp compile_protos_to_gql!(caller) do
    build_struct = current_draft_build!(caller)

    {_build_struct, output, _} = 
      {build_struct, [], caller}
      |> apply_id_alias!()
      |> apply_foreign_keys!()
      |> compile_service_protos!()
      |> compile_input_protos!()
      |> compile_messages!()
      |> compile_enums!()
      |> compile_clients_and_resolvers!()

    output
  end

  defp apply_id_alias!({build_struct, out, caller}) do
    regs = build_struct.options |> Keyword.get(:id_alias) |> List.wrap()
    build_struct = apply_id_alias(build_struct, regs)
    {build_struct, out, caller}
  end

  defp apply_id_alias(%__MODULE__{raw_types: %{message: messages}} = build_struct, regs) 
  when regs not in [nil, []] and messages not in [nil, []]
  do
    Enum.reduce messages, build_struct, fn msg, bs ->
      field_props =
        Enum.find msg.__message_props__.field_props, fn 
          {_, %{repeated?: true}} -> false
          {_, %{type: {:enum, _}}} -> false
          {_, %{embedded?: true}} -> false
          {_, %{name_atom: na}} ->
            Enum.any?(regs, &(Regex.match?(&1, to_string(na))))
        end

      case field_props do
        nil -> bs
        {_, field_props} ->
          field_name = field_props.name_atom
          attrs = 
            %{
              field_name: :id, 
              attrs: [
                {:type, field_datatype(field_props.type, required?: false, repeated?: false)},
                {:resolve, quote do
                  fn (parent, _, _) ->
                    {:ok, Map.get(parent, unquote(field_name))}
                  end
                end},
              ]
            }

          new_added_fields = Map.update(bs.added_fields, msg, %{id: attrs}, &Map.put(&1, :id, attrs))
          %{bs | added_fields: new_added_fields}
      end
    end
  end

  defp apply_id_alias(bs, _),
    do: bs

  defp apply_foreign_keys!({build_struct, out, caller}) do
    foreign_keys = build_struct.options |> Keyword.get(:foreign_keys, [])
    build_struct = apply_foreign_keys(build_struct, foreign_keys)
    {build_struct, out, caller}
  end

  defp apply_foreign_keys(build_struct, fks) when fks in [nil, []], 
    do: build_struct

  defp apply_foreign_keys(%__MODULE__{raw_types: %{message: msgs}} = build_struct, [fk_config | rest])
  when msgs not in [nil, []] and is_list(fk_config)
  do
    fk = Keyword.get(fk_config, :foreign_key)
    namespaces = Keyword.get(fk_config, :namespaces, [])
    if !fk, do: raise "no foreign key module supplied"

    candidates =
      Enum.filter msgs, fn m -> Enum.any?(namespaces, &within_namespace?(m, &1)) end

    candidates
    |> Enum.reduce(build_struct, &apply_foreign_key(&1, &2, fk))
    |> apply_foreign_keys(rest)
  end

  defp apply_foreign_keys(%__MODULE__{raw_types: %{message: msgs}} = build_struct, [{_, fk} | rest])
  when msgs not in [nil, []]
  do
    msgs
    |> Enum.reduce(build_struct, &apply_foreign_key(&1, &2, fk))
    |> apply_foreign_keys(rest)
  end

  defp apply_foreign_keys(build_struct, _), do: build_struct

  defp apply_foreign_key(msg, build_struct, fk) do
    excluded_fields = Map.get(build_struct.excluded_fields, msg, MapSet.new())

    fk_msg = %{identifier: gql_object_name(msg), proto_message: msg}

    props =
      Enum.find msg.__message_props__.field_props, fn {_, fp} ->
        if Enum.member?(excluded_fields, fp.name_atom) do
          false
        else
          fk_field = %{identifier: fp.name_atom, field_props: fp, list?: fp.repeated?}
          fk.matcher(fk_msg, fk_field)
        end
      end

    case props do
      nil ->
        build_struct

      {_, fp} ->
        fk_field = %{identifier: fp.name_atom, field_props: fp, list?: fp.repeated?}

        resolver =
          if fp.repeated? do
            fk.many_resolver(fk_msg, fk_field)
          else
            fk.one_resolver(fk_msg, fk_field)
          end

        dt = fk.output_field_type(fk_msg, fk_field)
        ident = fk.output_field_name(fk_msg, fk_field)
        attrs = fk.attributes(fk_msg, fk_field) || []

        attrs = attrs ++ [
          type: (quote do: unquote(dt)),
          resolve: (quote do: unquote(resolver)),
        ]

        msg_key =
          if fp.oneof == nil do
            msg
          else
            {name, _} = Enum.find(msg.__message_props__.oneof, fn {_name, idx} -> idx == fp.oneof end)
            [msg, [:oneof, name]]
          end

        field_defn = %{field_name: ident, attrs: attrs}

        new_added_fields =
          Map.update(build_struct.added_fields, msg_key, %{ident => field_defn}, fn x ->
            Map.put(x, ident, %{field_name: ident, attrs: attrs})
          end)

        %{build_struct | added_fields: new_added_fields}
    end
  end

  defp compile_service_protos!({build_struct, out, caller}) do
    services = Map.get(build_struct.raw_types, :service, [])
    input = %{services: services, build_struct: build_struct, output: out}
    %{build_struct: build_struct, output: output} = Enum.reduce(services, input, &compile_service/2)
    {build_struct, output, caller}
  end

  defp compile_service(service, %{build_struct: build_struct, output: output} = acc) do
    excluded_fields = Map.get(build_struct.excluded_fields, service, MapSet.new())
    rpc_queries = Map.get(build_struct.rpc_queries, service, MapSet.new())
    updated_rpcs = Map.get(build_struct.updated_rpcs, service, %{})

    {build_struct, calls} =
      service.__rpc_calls__
      |> Enum.reduce({build_struct, %{queries: [], mutations: []}}, fn
        {raw_name, {input, _streamin}, {output, _streamout}}, {bs, c}->
          new_input_objects = gather_all_input_objects_from_mod(input, build_struct.input_objects)
          bs = %{bs | input_objects: new_input_objects}

          field_name = rpc_name_to_gql_name(raw_name)
          query_type = 
            if Enum.member?(rpc_queries, field_name) do
              :queries
            else
              :mutations
            end

          updates = Map.get(updated_rpcs, field_name, %{})
          skipped_args = get_in(updates, [:attrs, :skip_args]) || []
          required_args = get_in(updates, [:attrs, :required_args]) || []

          msg_props = input.__message_props__

          args = 
            for {_, f} <- msg_props.field_props,
                          !Enum.member?(excluded_fields, f.name_atom),
                          !Enum.member?(skipped_args, f.name_atom),
                          f.oneof == nil
                          do

              datatype = field_datatype(f.type, required: Enum.member?(required_args, f.name_atom), name_parts: [:input_object], repeated?: f.repeated?)

              arg_name = f.name_atom

              quote do 
                arg unquote(arg_name), unquote(datatype)
              end
            end

          oneof_args = 
            for f <- Keyword.keys(msg_props.oneof),
                     !Enum.member?(excluded_fields, f),
                     !Enum.member?(skipped_args, f)
                     do
            
              datatype = field_datatype(input, required: Enum.member?(required_args, f), name_parts: [:oneof, f, :input_object])
              arg_name = f

              quote do 
                arg unquote(arg_name), unquote(datatype)
              end
            end

          all_args = args ++ oneof_args

          output_name = gql_object_name(output)
          resolver = Module.concat(service, :Resolver)
          
          service_output =
            quote do
              field unquote(field_name), unquote(output_name) do
                unquote_splicing(all_args)
                resolve {unquote(resolver), unquote(field_name)}
              end
            end

          c = update_in c, [query_type], fn existing_quoted ->
            [service_output | existing_quoted]
          end

          {bs, c}
      end)

    # construct objects for the mutations and queries
    out_quoted =
      if length(calls.queries) > 0 do
        the_calls = calls.queries
        obj_name = gql_object_name(service, [:queries])

        [
          quote do
            object(unquote(obj_name)) do
              unquote_splicing(the_calls)
            end
          end
        ]
      else
        []
      end

    out_quoted =
      if length(calls.mutations) > 0 do
        the_calls = calls.mutations
        obj_name = gql_object_name(service, [:mutations])
        [
          quote do
            object(unquote(obj_name)) do
              unquote_splicing(the_calls)
            end
          end
          | out_quoted
        ]
      else
        out_quoted
      end

    %{acc | build_struct: build_struct, output: out_quoted ++ output}
  end

  defp compile_input_protos!({build_struct, out, caller}) do
    all_input_objects = 
      build_struct.input_objects
      |> gather_all_input_objects()
      |> Enum.filter(&within_namespace?(&1, build_struct.namespace))
      |> Enum.into(MapSet.new())

    quoted_input_objects = Enum.flat_map(all_input_objects, &compile_proto_message(&1, input_object?: true, build_struct: build_struct))

    build_struct = %{build_struct | input_objects: all_input_objects}

    {build_struct, quoted_input_objects ++ out, caller}
  end

  defp compile_messages!({build_struct, out, caller}) do
    quoted_messages =
      build_struct.raw_types
      |> Map.get(:message, [])
      |> Enum.filter(&within_namespace?(&1, build_struct.namespace))
      |> Enum.filter(&(!Enum.member?(build_struct.ignored_types, &1)))
      |> Enum.into(MapSet.new())
      |> Enum.flat_map(&compile_proto_message(&1, input_object?: false, build_struct: build_struct))
    
    {build_struct, quoted_messages ++ out, caller}
  end

  defp compile_enums!({build_struct, out, caller}) do
    enum_ast =
      build_struct.raw_types
      |> Map.get(:enum, [])
      |> Enum.filter(&within_namespace?(&1, build_struct.namespace))
      |> Enum.filter(&(!Enum.member?(build_struct.ignored_types, &1)))
      |> Enum.into(MapSet.new())
      |> Enum.map(fn e ->
        excluded_fields = Map.get(build_struct.excluded_fields, e, MapSet.new())
        enum_name = gql_object_name(e)

        value_ast =
          for {_, f} <- e.__message_props__.field_props,
                        !Enum.member?(excluded_fields, f.name_atom)
          do
            name = f.name_atom
            quote do
              value unquote(name)
            end
          end

        quote do
          enum unquote(enum_name) do
            unquote_splicing(value_ast)
          end
        end
      end)

    {build_struct, enum_ast ++ out, caller}
  end

  defp compile_proto_message(type, opts) do
    build_struct = Keyword.get(opts, :build_struct)
    input_object? = Keyword.get(opts, :input_object?, false)
    excluded_fields = Map.get(build_struct.excluded_fields, type, %{})
    name_parts = if input_object?, do: [:input_object], else: []
    added_fields = if input_object?, do: %{}, else: Map.get(build_struct.added_fields, type, %{})
 
    msg_props = type.__message_props__

    fields_ast =
      for {_, f} <- msg_props.field_props,
                    !Enum.member?(excluded_fields, f.name_atom),
                    f.oneof == nil
                    do
      
        datatype = field_datatype(f.type, repeated?: f.repeated?, required?: (!input_object? && !f.embedded?), name_parts: name_parts)
        field_name = f.name_atom
        attrs = enum_resolver_for_props([], f)

        quote do
          field unquote(field_name), unquote(datatype), unquote(attrs)
        end
      end

    oneof_fields_ast =
      for f <- Keyword.keys(msg_props.oneof),
               !Enum.member?(excluded_fields, f)
               do

        datatype = field_datatype(type, name_parts: [:oneof, f] ++ name_parts)
        resolver = quote location: :keep do
          fn
            %{unquote(f) => oneof_value}, _, _ ->
              case oneof_value do
                nil -> {:ok, nil}
                {field_name, value} -> {:ok, Map.put(%{}, field_name, value)}
                map -> {:ok, map}
              end
            _, _, _ -> {:ok, nil}
          end
        end

        attrs = [resolve: resolver]

        quote do
          field unquote(f), unquote(datatype), unquote(attrs)
        end
      end

    oneof_objects =
      for {name, idx} <- msg_props.oneof,
                         !Enum.member?(excluded_fields, name) 
      do
        oneof_obj_fields =
          for {_, f} <- msg_props.field_props,
                        !Enum.member?(excluded_fields, f),
                        f.oneof == idx
          do
            datatype = field_datatype(f.type, repeated?: f.repeated?, required?: (!input_object? && !f.embedded?), name_parts: name_parts)
            field_name = f.name_atom

            quote do
              field unquote(field_name), unquote(datatype)
            end
          end

        obj_name = gql_object_name(type, [:oneof, name] ++ name_parts)

        if input_object? do
          quote do
            input_object(unquote(obj_name)) do
              unquote_splicing(oneof_obj_fields)
            end
          end
        else
          added_oneof_fields = Map.get(build_struct.added_fields, [type, [:oneof, name]], %{})
          added_oneof_fields_ast =
            for {field_name, %{attrs: attrs}} <- added_oneof_fields do
              quote do
                field unquote(field_name), unquote(attrs)
              end
            end

          all_oneof_obj_fields = oneof_obj_fields ++ added_oneof_fields_ast

          quote do
            object(unquote(obj_name)) do
              unquote_splicing(all_oneof_obj_fields)
            end
          end
        end
      end

    added_fields_ast = 
      for {id, %{attrs: attrs}} <- added_fields do
        quote do
          field unquote(id), unquote(attrs)
        end
      end

    all_fields = fields_ast ++ oneof_fields_ast ++ added_fields_ast

    out_name = gql_object_name(type, name_parts)

    quoted_msg = 
      if input_object? do
        quote do
          input_object(unquote(out_name)) do
            unquote_splicing(all_fields)
          end
        end
      else
        quote do
          object(unquote(out_name)) do
            unquote_splicing(all_fields)
          end
        end
      end

    [quoted_msg | oneof_objects]
  end

  defp compile_clients_and_resolvers!({%{raw_types: %{service: services}} = build_struct, _out, _caller} = done) 
  when services not in [nil, []]
  do
    client_builder = AbsintheProto.Client.fetch_client_builder()
    resolver_builder = AbsintheProto.Resolver.fetch_resolver_builder()

    candidates = 
      Enum.filter(services, &within_namespace?(&1, build_struct.namespace))

    Enum.each candidates, fn service ->
      client_name = Module.concat(service, :Client)
      resolver_name = Module.concat(service, :Resolver)

      case client_builder.build_client(service, client_name) do
        {:error, reason} -> raise "could not build client for #{service} #{inspect(reason)}"
        _ -> :ok
      end

      case resolver_builder.build_resolver(service, resolver_name, client_name) do
        {:error, reason} -> raise "could not build resolver for #{service} #{inspect(reason)}"
        _ -> :ok
      end
    end

    done
  end

  defp compile_clients_and_resolvers!(done),
    do: done

  defp filter_proto_messages(mods, namespace) do
    mods
    |> Enum.filter(&within_namespace?(&1, namespace))
    |> Enum.group_by(&proto_type/1)
    |> Map.drop([:unknown])
  end

  defp within_namespace?(_mod, nil), do: true
  defp within_namespace?(mod, ns) do
    String.starts_with?(to_string(mod), to_string(ns))
  end

  defp gather_all_input_objects(input_objects), 
    do: gather_all_input_objects(Enum.into(input_objects, []), MapSet.new())

  defp gather_all_input_objects([], input_objects), do: input_objects
  defp gather_all_input_objects([this | rest], input_objects) do
    if MapSet.member?(input_objects, this) do
      gather_all_input_objects(rest, input_objects)
    else
      gather_all_input_objects(rest, gather_all_input_objects_from_mod(this, input_objects))
    end
  end

  defp gather_all_input_objects_from_mod(mod, input_objects) do
    input_objects = MapSet.put(input_objects, mod)
    new_input_objects =
      for {_, field} <- mod.__message_props__.field_props,
                        field.embedded?,
                        !field.enum?,
                        !MapSet.member?(input_objects, field.type),
                        do: field.type

    Enum.reduce(new_input_objects, input_objects, &gather_all_input_objects_from_mod/2)
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

  defp fetch_modules(blank) when blank in [nil, []],
    do: raise "path or otp_app should be passed to AbsintheProto.DSL.build"

  defp fetch_modules([paths: load_files]) when is_list(load_files) do
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
  end

  defp fetch_modules([otp_app: app]) when is_atom(app) do
    Application.ensure_all_started(app)
    {:ok, m} = :application.get_key(app, :modules)
    m
  end

  defp save_draft_build(build, mod) do
    Module.put_attribute(mod, :ap_current_draft_build, build)
  end

  defp current_draft_build!(mod) do
    case Module.get_attribute(mod, :ap_current_draft_build) do
      nil -> raise "no current build (for #{mod})"
      build -> build
    end
  end

  defp save_current_proto_message(msg_proto, mod) do
    Module.put_attribute(mod, :ap_current_proto_message, msg_proto)
  end

  defp current_proto_message!(mod) do
    case Module.get_attribute(mod, :ap_current_proto_message) do
      nil -> raise "not currently modifying a message"
      msg -> msg
    end
  end

  defp clear_current_proto_message(mod) do
    Module.delete_attribute(mod, :ap_current_proto_message)
  end

  defp has_proto_type?(build_struct, mod, type) do
    case Map.get(build_struct.raw_types, type) do
      nil -> false
      types -> Enum.member?(types, mod)
    end
  end

  defp field_datatype({:enum, type}, opts),
    do: field_datatype(type, Keyword.drop(opts, [:name_parts]))

  defp field_datatype(type, opts) do
    dt_name =
      case AbsintheProto.Scalars.proto_to_gql_scalar(type) do
        :error ->
          gql_object_name(type, Keyword.get(opts, :name_parts, []))
        scalar ->
          scalar
      end

    opts |> Enum.into(%{}) |> quoted_field_datatype(dt_name)
  end

  defp quoted_field_datatype(%{required?: true, repeated?: true}, dt_name) do
    quote do
      Absinthe.Schema.Notation.non_null(Absinthe.Schema.Notation.list_of(Absinthe.Schema.Notation.non_null(unquote(dt_name))))
    end
  end

  defp quoted_field_datatype(%{repeated?: true}, dt_name) do
    quote do
      Absinthe.Schema.Notation.list_of(Absinthe.Schema.Notation.non_null(unquote(dt_name)))
    end
  end

  defp quoted_field_datatype(%{required?: true}, dt_name) do
    quote do
      Absinthe.Schema.Notation.non_null(unquote(dt_name))
    end
  end

  defp quoted_field_datatype(_, dt_name) do 
    quote do 
      unquote(dt_name)
    end
  end

  defp enum_resolver_for_props(attrs, %{name_atom: name, enum?: true, type: {:enum, type}}) do
    res =
      quote do
        fn
          %{unquote(name) => value}, _, _ when is_integer(value) ->
            {:ok, unquote(type).key(value)}
          %{unquote(name) => value}, _, _ when is_atom(value) ->
            {:ok, value |> unquote(type).value() |> unquote(type).key()}
          %{unquote(name) => value}, _, _ when is_binary(value) ->
            valid_value? =
              unquote(type).__message_props__.field_props
              |> Enum.map(fn {_, f} -> to_string(f.name_atom) end)
              |> Enum.member?(value)

            if valid_value? do
              {:ok, String.to_atom(value)}
            else
              {:error, :invalid_enum_value}
            end
          _, _, _ ->
            {:ok, nil}
        end
      end
    Keyword.put(attrs, :resolve, res)
  end

  defp enum_resolver_for_props(attrs, _), do: attrs
end
