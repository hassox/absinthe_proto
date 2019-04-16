defmodule AbsintheProto.DSL do
  @moduledoc """
  Provides a DSL for building absinthe graphql messages

  Generates:

  * All input objects for services found
  * All clients (requires a `AbsintheProto.Client` client builder in config)
  * All resolvers for found services (overwriteabe with an `AbsintheProto.Resolver builder)
  * All rpc calls are setup as mutations by default 
  * All scalar fields in `object`s are marked as required as per Proto3 behaviour
  * All scalar fields in `input_object`s are not marked as required unless specified
  * Applies specified foreign keys to all objects within the given namespace (optional) `AbsintheProto.ForeignKey`

  For all services, two objects are generated. One for all service queries and one for all mutations.
  Queries must be specified as mutations are the default.

  ### Naming convention

  All objects are created utilizing the generated module name of the 
  proto message using double `_` between package names and snake case between.
  
  e.g. `MyApp.Protos.FredFlintstone ==> :my_app__protos__fred_flintstone`

  * Input objects are suffixed with `__input_object`
  * Queries for a service are suffixed with `__queries`
  * Mutations are suffixed with `__mutations`

  ### Services

  All services generate both clients and resolvers as well as query and mutation objects.

  * Query objects are the service name suffixed with `__queries` e.g. `:my_app__protos__my_service__service__queries`
  * Mutation objects are the service name suffixed with `__mutations` e.g. `:my_app__protos__my_service__service__mutations`
  * Generate a client using the configured `AbsintheProto.Client` builder. Put at `MyProtos.Protos.MyService.Service.Client`
  * Generate a resolver using the configured `AbsintheProto.Resolver` builder. Put at `MyProtos.Protos.MyService.Service.Resolver`

  ### Foreign keys

  Foregin keys if specified will be mapped automatically for every object.

  To setup a foreign key 
  
  * Implement the `AbsintheProto.ForeignKey` behaviour. 
  * Specify the foreign key in the `build` macro. Optionally specify namespaces to apply the foreign key

  ### Configuration

  A Client builder must be provided, and a resolver builder _may_ be provided.

      config :absinthe_proto,
        resolver_builder: MyResolverBuilder,
        client_builder: MyClientBuilder,
  

  ### Troubleshooting

  This library heavliy relies on macros to provide the translation between protos and graphql objects
  As such, normal compile loading is affected and updates to proto files may not be picked up.

  In order to sort this you _must_ force compile the code that makes use of this library when you update protos.

  ## Example

  ```elixir
  defmodule MyApp.Types do
    use AbsintheProto

    build path_glob: "path/to/protos/**/*.pb.ex", # the source of the compiled proto files
          namespace: MyProtos, # the namespace to compile
          foreign_keys: [
            [foreign_key: MyApp.ForeignKeys.Users],
            [
              foreign_key: MyApp.ForeignKeys.Addresses,
              namespaces: [
                MyProtos.Under.Here,
                MyProtos.Under.There,
              ]
            ],
          ]
    do

      # declare input_objects that are not part of an RPC call within this namespace
      input_objects([
        MyProtos.Some.Input
      ])

      # ignore the provided objects and do not generate gql types 
      ignore_objects([
        MyProtos.Some.PrivateObject
      ])

      bulk_rpc_queries(%{
        MyProtos.MyService => 

      })

      modify MyProtos.SomeMessage do
        # add a new field
        add_field :name, :type, resolve: {mod, :fun_name}

        # exclude the following fields from this message
        exclude_fields([:private_field])
      end

      modify MyProtos.SomeService.Service do
        # set the rpc queries
        rpc_queries([:my_queries, :yo])

        # manually specify the resolver
        service_resolver MyResolver

        update_rpc :rpc_call_name, required_args: [:field, :names, :from, :input, :object],
                                   skip_args: [:field_names_from_input_object]


    end
  end
  ```
  """

  @typedoc "a glob for compiled proto files. e.g. `my/proto/path/**/*.pb.ex`"
  @type path_glob :: String.t

  @typedoc "an otp application that has compiled protos"
  @type otp_app :: :atom

  @typedoc """
  A foreign key specification. 
  The foreign key must implement the `AbsintheProto.ForeignKey` behaviour.
  The namespaces specify that all objects found within that namespace will have the foreign key applied
  """
  @type foreign_key :: [
    namespaces: [module],
    foreign_key: module,
  ]

  @typedoc """
  If a namepace is specified, only objects under that namespace will be compiled to gql
  `id_aliases` will implement a resolver to provide an ID field
  """
  @type options :: [
    namespace: module,
    foreign_keys: [foreign_key],
    id_aliases: [Regex.t],
    path_glob: path_glob,
    otp_app: otp_app,
  ]

  defstruct [
    namespace: nil,
    service_resolvers: %{},
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

  @doc """
  Build a collection of proto modules into gql objects, input objects, resolvers and clients.
  """
  defmacro build(options, blk \\ [do: []]) do
    {opts, _} = Module.eval_quoted(__CALLER__, options)
    ns = Keyword.get(opts, :namespace)

    build_struct = %__MODULE__{options: opts, namespace: ns}

    save_draft_build(build_struct, __CALLER__.module)

    raw_types =
      case fetch_modules(Keyword.take(opts, [:path_glob, :otp_app])) do
        [] -> 
          raise "no proto messages found for #{} namespace"

        mods ->
          filter_proto_messages(mods, ns)
      end

    build_struct = %{build_struct | raw_types: raw_types}

    save_draft_build(build_struct, __CALLER__.module)

    Module.eval_quoted(__CALLER__, blk)

    nil
  end

  @doc """
  Used within a build call. Provide a list of proto objects to ignore
  """
  defmacro ignore_objects(objs) do
    {objs, _} = Module.eval_quoted(__CALLER__, objs)

    build_struct = current_draft_build!(__CALLER__.module)

    ignored_types =
      objs
      |> MapSet.new()
      |> MapSet.union(build_struct.ignored_types)
    
    build_struct = %{build_struct | ignored_types: ignored_types}
    save_draft_build(build_struct, __CALLER__.module)

    nil 
  end

  @doc """
  Used within a build call.
  
  Manually specify input_objects to force creating input objects.

  Normally all objects that are part of rpc calls are automatically created as input objects
  but there are some times where you need to specify them in this way.

  1. When they are used outside the protos found in the `build` call
  2. Can be used in a more manual way (to support `Any` fields)
  """
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

  @doc """
  Modify a specific proto message.

  This could be a 

  * message
  * enum
  * service
  """
  defmacro modify(mod, blk) do
    {mod, _} = Module.eval_quoted(__CALLER__, mod)
    save_current_proto_message(mod, __CALLER__.module)
    Module.eval_quoted(__CALLER__, blk)
    clear_current_proto_message(__CALLER__.module)
    nil
  end

  @doc """
  Exclude fields from a proto message.

  This will not be available to use (either as input objects or normal objects)
  """
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

  @doc """
  Update a specific field that maps to an rpc call.

  Only used within a call to modify a service

  Example

  ```
    modify MyProtos.Services.Flowers.Service do
      update_rpc :rpc_method, required_args: [...], skip_args: [...], description: "some docs"
    end
  ```

  Update rpc is used to require or skip arguments or to add documentation.
  """
  defmacro update_rpc(field_name, attrs) do
    {field_name, _} = Module.eval_quoted(__CALLER__, field_name)
    {attrs, _} = Module.eval_quoted(__CALLER__, attrs)
    proto_mod = current_proto_message!(__CALLER__.module)

    build_struct = current_draft_build!(__CALLER__.module)

    if !has_proto_type?(build_struct, proto_mod, :service) do 
      raise "#{proto_mod} is not an service. cannot update_rpc"
    end

    mod_updated_rpcs = 
      build_struct.updated_rpcs
      |> Map.get(proto_mod, %{})
      |> Map.put(field_name, %{field_name: field_name, attrs: attrs})

    updated_rpcs = Map.put(build_struct.updated_rpcs, proto_mod, mod_updated_rpcs)

    build_struct = %{build_struct | updated_rpcs: updated_rpcs}
    save_draft_build(build_struct, __CALLER__.module)

    nil
  end

  @doc """
  Used within a modify call of a SERVICE.

  Normally not needed, you can override the service resolver
  to a custom one if required.
  """
  defmacro service_resolver(resolver) do
    {resolver, _} = Module.eval_quoted(__CALLER__, resolver)

    build_struct = current_draft_build!(__CALLER__.module)
    proto_mod = current_proto_message!(__CALLER__.module)

    if !has_proto_type?(build_struct, proto_mod, :service) do 
      raise "#{proto_mod} is not an service. cannot set service resolver"
    end

    resolvers = Map.put(build_struct.service_resolvers, proto_mod, resolver)
    build_struct = %{build_struct | service_resolvers: resolvers}
    save_draft_build(build_struct, __CALLER__.module)
    nil
  end

  @doc """
  Used within a `modify` call of a SERVICE.

  By default all rpc methods are `mutation`s.
  Specify the methods/fields that should be considered queries.

  All queries will be created in gql as the service suffixed with `__queries`
  All mutations will be created in gql as the service suffixed with `__mutations`

  Example

  ```
  # MyProtos.Services.Flowers.Service gives
  :my_protos__services__flowers__service__queries
  :my_protos__services__flowers__service__mutations
  ```

  Each is only generated when there are fields found.
  """
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

  @doc """
  Setting queries can be done in bulk by providing a map of service to list of query fields.

  Used within the `build` call

  ```
  build_rpc_queries(%{
    MyProtos.Services.Flowers.Service => [:get, :search]
  })
  """
  defmacro bulk_rpc_queries(queries) do
    {queries, _} = Module.eval_quoted(__CALLER__, queries)
    build_struct = current_draft_build!(__CALLER__.module)

    new_queries =
      queries
      |> Enum.reduce(build_struct.rpc_queries, fn {mod, qs}, acc ->
        existing = Map.get(acc, mod, MapSet.new())
        Map.put(acc, mod, MapSet.union(existing, MapSet.new(qs)))
      end)
    
    build_struct = %{build_struct | rpc_queries: new_queries}
    save_draft_build(build_struct, __CALLER__.module)
    nil
  end

  @doc """
  Used within `modify` call

  Add a field to a proto message when it becomes gql.

  Added fields provide the ability to manually setup associations and other fields that are not part of the proto message.

  Added fields are NOT applied to `input_object`s
  """
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

  defmacro compile_protos_to_gql!(_args \\ []) do
    caller = __CALLER__.module
    try do
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
    rescue
      _ -> []
    end
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
      if length(namespaces) > 0 do
        Enum.filter msgs, fn m -> 
          Enum.any?(namespaces, &within_namespace?(m, &1)) 
        end
      else
        msgs
      end

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

    all_props =
      Enum.filter msg.__message_props__.field_props, fn {_, fp} ->
        if Enum.member?(excluded_fields, fp.name_atom) do
          false
        else
          fk_field = %{identifier: fp.name_atom, field_props: fp, list?: fp.repeated?}
          fk.matcher(fk_msg, fk_field)
        end
      end

    Enum.reduce all_props, build_struct, fn props, bs ->
      case props do
        nil ->
          bs

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

          %{bs | added_fields: new_added_fields}
      end
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
    resolver = Map.get(build_struct.service_resolvers, service,Module.concat(service, :Resolver))

    {build_struct, calls} =
      service.__rpc_calls__
      |> Enum.reduce({build_struct, %{queries: [], mutations: []}}, fn
        {raw_name, {rpc_input, _streamin}, {rpc_out, _streamout}}, {bs, c}->
          new_input_objects = gather_all_input_objects_from_mod(rpc_input, build_struct.input_objects)
          bs = %{bs | input_objects: MapSet.union(bs.input_objects, MapSet.new(new_input_objects))}
          updated_rpcs = Map.get(bs.updated_rpcs, service, %{})

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

          msg_props = rpc_input.__message_props__

          args = 
            for {_, f} <- msg_props.field_props,
                          !Enum.member?(excluded_fields, f.name_atom),
                          !Enum.member?(skipped_args, f.name_atom),
                          f.oneof == nil
                          do

              datatype = field_datatype(f.type, required: Enum.member?(required_args, f.name_atom), name_parts: [:input_object], repeated?: f.repeated?)
              {arg_name, attrs} = normalized_field_name_and_args(f.name_atom)

              quote do 
                arg unquote(arg_name), unquote(datatype), unquote(attrs)
              end
            end

          oneof_args = 
            for f <- Keyword.keys(msg_props.oneof),
                     !Enum.member?(excluded_fields, f),
                     !Enum.member?(skipped_args, f)
                     do
            
              datatype = field_datatype(rpc_input, required: Enum.member?(required_args, f), name_parts: [:oneof, f, :input_object])
              {arg_name, attrs} = normalized_field_name_and_args(f)

              quote do 
                arg unquote(arg_name), unquote(datatype), unquote(attrs)
              end
            end

          all_args = args ++ oneof_args

          output_name = gql_object_name(rpc_out)
          {rpc_field_name, attrs} = normalized_field_name_and_args(field_name)


          service_output =
            quote do
              field unquote(rpc_field_name), unquote(output_name), unquote(attrs) do
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
        {field_name, attrs} = normalized_field_name_and_args(f.name_atom)
        attrs = attrs ++ enum_resolver_for_props([], f)

        quote do
          field unquote(field_name), unquote(datatype), unquote(attrs)
        end
      end

    oneof_fields_ast =
      for f <- Keyword.keys(msg_props.oneof),
               !Enum.member?(excluded_fields, f)
               do

        {f_name, attrs} = normalized_field_name_and_args(f)
        datatype = field_datatype(type, name_parts: [:oneof, f] ++ name_parts, required?: false)
        resolver = quote location: :keep do
          fn
            %{unquote(f_name) => oneof_value}, _, _ ->
              case oneof_value do
                nil -> {:ok, nil}
                {f_name, value} -> {:ok, Map.put(%{}, f_name, value)}
                map -> {:ok, map}
              end
            _, _, _ -> {:ok, nil}
          end
        end

        attrs = attrs ++ [resolve: resolver]

        quote do
          field unquote(f_name), unquote(datatype), unquote(attrs)
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
            datatype = field_datatype(f.type, repeated?: f.repeated?, required?: false, name_parts: name_parts)
            {field_name, attrs} = normalized_field_name_and_args(f.name_atom)

            quote do
              field unquote(field_name), unquote(datatype), unquote(attrs)
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
    all_fields =
      if length(all_fields) == 0 do
        [
          quote do
            field :noop, :boolean, description: "empty field"
          end
        ]
      else
        all_fields
      end

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
      resolver = Map.get(build_struct.service_resolvers, service)

      case client_builder.build_client(service, client_name) do
        {:error, reason} -> raise "could not build client for #{service} #{inspect(reason)}"
        _ -> :ok
      end

      unless resolver do
        case resolver_builder.build_resolver(service, resolver_name, client_name) do
          {:error, reason} -> raise "could not build resolver for #{service} #{inspect(reason)}"
          _ -> :ok
        end
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
            _ -> 
              :message
          end
        _ -> 
          :unknown
      end
    rescue
      _ -> 
        :unknown
    end
  end

  defp fetch_modules(blank) when blank in [nil, []],
    do: raise "path or otp_app should be passed to AbsintheProto.DSL.build"

  defp fetch_modules([path_glob: glob]) when is_binary(glob) do
    paths = Path.wildcard(glob)
    "grep -h defmodule #{Enum.join(paths, " ")} | awk '{print $2}' | sort"
    |> String.to_charlist()
    |> :os.cmd()
    |> to_string()
    |> open_string_io!()
    |> IO.stream(:line)
    |> Stream.map(&String.trim/1)
    |> Stream.filter(&(&1 != ""))
    |> Stream.map(&(:"Elixir.#{&1}"))
    |> Enum.to_list()
  end

  defp fetch_modules([otp_app: app]) when is_atom(app) do
    Application.ensure_all_started(app)
    {:ok, m} = :application.get_key(app, :modules)
    m
  end

  defp open_string_io!(str) do
    case StringIO.open(str) do
      {:ok, pid} -> pid
      {:error, reason} -> raise "Could not open string IO #{inspect(reason)}"
    end
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

  defp normalized_field_name_and_args(name) do
    camel_case = name |> to_string() |> Absinthe.Adapter.LanguageConventions.to_external_name(:field)
    underscore = Absinthe.Adapter.LanguageConventions.to_internal_name(camel_case, :field)
    if underscore == to_string(name) do
      {name, []}
    else
      {name, [name: to_string(underscore)]}
    end
  end
end
