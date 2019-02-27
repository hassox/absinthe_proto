defmodule AbsintheProto.DSL do
  @moduledoc """
  Builds out absinthe objects

  1. Collect the modules and configurations for each build in the module
  """

  # module attribute namespace is `ap_xxx`

  defmacro build(proto_namespace, options, blk \\ [do: []]) do
    ns = Macro.expand(proto_namespace, __CALLER__)
    {opts, _} = Module.eval_quoted(__CALLER__, options)

    build =
      %AbsintheProto.Objects.Build{
        namespace: ns,
        foreign_keys: Keyword.get(opts, :foreign_keys, []),
      }

    build =
      case Keyword.get(opts, :id_alias) do
        nil -> build
        id_alias -> %{build | id_alias: id_alias}
      end

    case fetch_modules(Keyword.take(opts, [:paths, :otp_app])) do
      [] -> raise "no proto messages found for #{ns} namespace"
      mods ->
        messages =
          mods
          |> modules_for_namespace(ns)
          |> wrap_raw_proto_messages()

        save_draft_build(%{build | messages: messages}, __CALLER__.module)
    end

    Module.eval_quoted(__CALLER__, blk)

    build =
      fetch_final_build!(__CALLER__.module)
      |> Macro.escape(unquote: true)

    quote do
      @ap_builds unquote(build)
    end
  end

  defmacro input_objects(objs) do
    {objs, _} = Module.eval_quoted(__CALLER__, objs)
    build = current_draft_build!(__CALLER__.module)
    new_inputs = MapSet.union(build.input_objects, MapSet.new(objs))
    save_draft_build(%{build | input_objects: new_inputs}, __CALLER__.module)
    nil
  end

  defmacro ignore_objects(objs) do
    {objs, _} = Module.eval_quoted(__CALLER__, objs)
    build = current_draft_build!(__CALLER__.module)
    new_ignored = MapSet.union(build.ignored_objects, MapSet.new(objs))
    save_draft_build(%{build | ignored_objects: new_ignored}, __CALLER__.module)
    nil
  end

  defmacro modify(proto_mod, blk) do
    mod = Macro.expand(proto_mod, __CALLER__)
    build = current_draft_build!(__CALLER__.module)

    message = Map.get(build.messages, mod)
    save_current_proto_message(message, __CALLER__.module)

    Module.eval_quoted(__CALLER__, blk)

    msg = current_proto_message!(__CALLER__.module)
    clear_current_proto_message(__CALLER__.module)

    save_draft_build(%{build | messages: Map.put(build.messages, mod, msg)}, __CALLER__.module)
    nil
  end

  defmacro exclude_fields(fields) do
    {fields, _} = Module.eval_quoted(__CALLER__, fields)
    fields = List.wrap(fields)
    message = current_proto_message!(__CALLER__.module)
    new_fields = MapSet.union(message.excluded_fields, MapSet.new(fields))
    save_current_proto_message(%{message | excluded_fields: new_fields}, __CALLER__.module)
    nil
  end

  defmacro update_rpc(field_name, attrs) do
    {field_name, _} = Module.eval_quoted(__CALLER__, field_name)
    {attrs, _} = Module.eval_quoted(__CALLER__, attrs)
    message = current_proto_message!(__CALLER__.module)

    if message.proto_type != :service,
      do: raise "#{message.module} is not a service it is #{message.proto_type}"

    updated_rpcs = Map.put(message.updated_rpcs, field_name, attrs)
    save_current_proto_message(%{message | updated_rpcs: updated_rpcs}, __CALLER__.module)
    nil
  end

  defmacro service_resolver(rmod) do
    {resolver_mod, _} = Module.eval_quoted(__CALLER__, rmod)
    message = current_proto_message!(__CALLER__.module)

    if message.proto_type != :service,
      do: raise "#{message.module} is not a service it is #{message.proto_type}"

    save_current_proto_message(%{message | service_resolver: resolver_mod}, __CALLER__.module)
    nil
  end

  defmacro rpc_queries(raw_queries) do
    {queries, _} = Module.eval_quoted(__CALLER__, raw_queries)
    message = current_proto_message!(__CALLER__.module)

    if message.proto_type != :service,
      do: raise "#{message.module} is not a service it is #{message.proto_type}"

    save_current_proto_message(
      %{message | rpc_queries: MapSet.union(message.rpc_queries, MapSet.new(queries))},
      __CALLER__.module
    )
    nil
  end

  defmacro add_field(field_name, datatype, attrs \\ []) do
    {field_name, _} = Module.eval_quoted(__CALLER__, field_name)
    {attrs, _} = Module.eval_quoted(__CALLER__, attrs)
    {datatype, _} = Module.eval_quoted(__CALLER__, datatype)
    attrs = Keyword.put(attrs, :type, datatype)

    message = current_proto_message!(__CALLER__.module)

    if message.proto_type == :enum,
      do: raise "#{message.module} is an enum. Cannot add field to an enum."

    additional_fields = Map.put(message.additional_fields, field_name, attrs)

    save_current_proto_message(%{message | additional_fields: additional_fields}, __CALLER__.module)
    nil
  end

  defp modules_for_namespace(from_mods, ns) do
    from_mods
    |> Enum.filter(fn m -> within_namespace?(m, ns) end)
  end

  defp within_namespace?(mod, ns) do
    String.starts_with?(to_string(mod), to_string(ns))
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

  def gql_object_name(mod, other_parts \\ []) do
    [Macro.underscore(mod) | other_parts]
    |> Enum.map(fn i ->
      i |> to_string() |> Macro.underscore() |> String.replace("/", "__")
    end)
    |> Enum.join("__")
    |> String.to_atom()
  end

  defp wrap_raw_proto_messages([]), do: []
  defp wrap_raw_proto_messages(mods) do
    Enum.map(mods, fn mod ->
      case proto_type(mod) do
        :unknown -> nil
        type ->
          {
            mod,
            %AbsintheProto.Objects.Message{
              module: mod,
              proto_type: type,
              gql_name: gql_object_name(mod),
            }
          }
      end
    end)
    |> Enum.filter(&(&1 != nil))
    |> Enum.into(%{})
  end

  defp proto_type(nil), do: raise "nil is not a valid object type"
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

  defp save_current_proto_message(%AbsintheProto.Objects.Message{} = msg, mod) do
    Module.put_attribute(mod, :ap_current_proto_message, msg)
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

  defp current_draft_build!(mod) do
    case Module.get_attribute(mod, :ap_current_draft_build) do
      nil -> raise "no current build (for #{mod})"
      build -> build
    end
  end

  defp save_draft_build(build, mod) do
    Module.put_attribute(mod, :ap_current_draft_build, build)
  end

  defp fetch_final_build!(mod) do
    build = current_draft_build!(mod)
    Module.delete_attribute(mod, :ap_current_draft_build)
    build
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
end
