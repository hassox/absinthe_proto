defmodule AbsintheProto.Blueprinter do
  @moduledoc false
    # 2. Ignore objects (remove them from consideration)
    # 4. Apply exlude fields from base objects
    # 5. Create `object` for all proto messages
    # 6. Create service objects
    # 7. Create input objects (from the base objects or at least exclude the fields)

  defstruct []

  defmacro __before_compile__(env) do
    env.module
    |> Module.get_attribute(:ap_builds)
    |> compile_builds()
    |> Enum.flat_map(&(&1))
  end

  defp compile_builds(builds),
    do: compile_builds(builds, [])

  defp compile_builds([], acc),
    do: acc

  defp compile_builds([build | rest], acc),
    do: compile_builds(rest, [compile_build(build) | acc])

  defp compile_build(build) do
    {build, %__MODULE__{}}
    |> ignore_objects()
    # |> apply_id_alias()
    # |> apply_foreign_keys()
    |> generate_blueprint_objects()
    # |> generate_objects()
    # |> compile_services()
    # |> compile_input_objects()
    # |> quote_compiled()
  end

  defp ignore_objects({%{messages: messages, ignored_objects: ignored} = build, comp}) do
    {%{build | messages: Map.drop(messages, MapSet.to_list(ignored))}, comp}
  end

  defp generate_blueprint_objects({%{messages: messages} = b, c} = o) do
    blueprints =
      messages
      |> Enum.map(&message_to_blueprint/1)
      |> Enum.into(%{})

    # each message
    # get all fields
    # exclude fields
    # create GqlField
  end

  defp compile_objects({b, c} = o) do
    o
  end

  defp compile_enums({b, c} = o) do
    o
  end

  defp compile_services({b, c} = o) do
    o
  end

  defp compile_input_objects({b, c} = o) do
    o
  end

  defp quote_compiled({b, c} = o) do
    []
  end

  defp message_to_blueprint({mod, %{proto_type: :enum, excluded_fields: exclude} = msg}) do
    # excluded fields is a mapset of fields to exclude
    values =
      mod.__message_props__.field_props
      |> Map.values()
      |> Enum.filter(&(not MapSet.member?(exclude, &1.name_atom)))
      |> Enum.map(&(&1.name_atom))

    {
      mod,
      %AbsintheProto.Objects.Blueprint.Enum{
        identifier: msg.gql_name,
        message: msg,
        values: values,
      }
    }
  end

  defp message_to_blueprint({mod, %{proto_type: :message, excluded_fields: excluded} = msg}) do
    raw_field_props = Map.values(mod.__message_props__.field_props)

    raw_field_map = # %{foo: %{identifier: foo, list?: true|false, proto_datatype: ...}}
      raw_field_props
      |> Stream.filter(&(not MapSet.member?(excluded, &1.name_atom)))
      |> Stream.filter(&(&1.oneof != nil))
      |> Stream.map(&message_field/1)
      |> Enum.into(%{})

    additional_field_map =
      msg.additional_fields
      |> Enum.map(fn {name, attrs} ->
        {
          name,
          %AbsintheProto.Objects.Blueprint.MessageField{
             identifier: name,
             attrs: attrs,
          }
        }
      end)
      |> Enum.into(%{})

    oneof_field_map =
      case mod.__message_props__ do
        %{oneof: []} ->
          %{}
        %{oneof: oneofs} ->
          for {name, id} <- oneofs, into: %{} do
            oneof_fields =
              raw_field_props
              |> Stream.filter(&(&1.oneof == id))
              |> Stream.map(&message_field/1)
              |> Enum.into(%{})

            {name, oneof_fields}
          end
      end

    {
      mod,
      %AbsintheProto.Objects.Blueprint.Message{
        identifier: msg.gql_name,
        message: msg,
        raw_field_map: raw_field_map,
        additional_field_map: additional_field_map,
        oneof_field_map: oneof_field_map,
      }
    }
  end

  defp message_to_blueprint({mod, %{proto_type: :service, excluded_fields: excluded} = msg}) do
    service =
      %AbsintheProto.Objects.Blueprint.Service{
        identifier: msg.gql_name,
        proto_module: mod,
        resolver: msg.service_resolver,
      }

    fields = 
      mod.__rpc_calls__()
      |> Stream.map(fn {raw_name, input, output} ->
        name = raw_name |> to_string() |> Macro.underscore() |> String.to_atom()
        {name, input, output}
      end)
      |> Stream.filter(fn {name, _, _} -> not MapSet.member?(excluded, name) end)
      |> Enum.map(fn {name, input, output} ->
        rpc = 
          %AbsintheProto.Objects.Blueprint.Service.RPCCall{
            identifier: name,
            output_object: output,
          }

        rpc =
          Enum.reduce(input.__message_props__.field_props, rpc, fn 
            {_, p}, rpc_call ->
          end)
      end)

    # excluded fields
    # updated_rpcs
    # object :od__protos__bobs__services__bobs__service__queries do
    #   # excluded via exclude_fields field :secret_bob_action, ....
    #   field :create_thing do
    #     arg :bob, :od_protos__objects__bob
    #     # excluded (via skip args) arg :bob, :od_protos__objects__bob
    #     arg :bob, non_null(:od_protos__objects__bob) # via required args

    #     arg :id, :string
    #     arg :count, :int64
    #     resolve {BobsServiceResolver, :method_name}
    #   end 
    # end

    # modify OdProtos.Bobs.Services.Bobs.Service do
    #   serviceResolver BobsServiceResolver 
    #   exclude_fields [:secret_bob_action]
    #   rpc_queries [:create_thing]

    #   update_rpc :create_thing, skip_args: [:bob]
    #   # OR 
    #   update_rpc :create_thing, require_args: [:bob]
    # end

    {mod, service}
  end

  defp message_field(%{enum?: true, enum_type: type} = f) do
    {
      f.name_atom,
      %AbsintheProto.Objects.Blueprint.MessageField{
        proto_field_props: f,
        identifier: f.name_atom,
        list?: f.repeated?,
        proto_datatype: type,
      }
    }
  end

  defp message_field(%{type: type} = f) do
    {
      f.name_atom,
      %AbsintheProto.Objects.Blueprint.MessageField{
        proto_field_props: f,
        identifier: f.name_atom,
        list?: f.repeated?,
        proto_datatype: type,
      }
    }
  end
end
