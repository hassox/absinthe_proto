defmodule AbsintheProto.Writer do
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
    |> generate_blueprints()
    # |> generate_objects()
    # |> compile_services()
    # |> compile_input_objects()
    |> quote_compiled()
  end

  defp ignore_objects({%{messages: messages, ignored_objects: ignored} = build, comp}) do
    {%{build | messages: Map.drop(messages, MapSet.to_list(ignored))}, comp}
  end

  defp generate_blueprints_objects({%{messages: messages} = b, c} = o) do
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
      |> Enum.filter(&(not MapSet.member?(exclude, &1.name_atom))
      |> Enum.map(fn {_, p} -> p.name_atom})

    {
      mod,
      %AbsintheProto.Objects.Blueprint.Enum{
        message: msg,
        identifier: msg.gql_name,
        values: values,
      }
    }
  end

  defp message_to_blueprint({mod, %{proto_type: :message} = msg}) do
    raw_field_props = Map.values(mod.__message_props__.field_props)

    raw_field_map = # %{foo: %{identifier: foo, list?: true|false, proto_datatype: ...}}
      raw_field_props
      |> Enum.filter(&(not MapSet.member?(exclude, &1.name_atom)))
      |> Enum.filter(&(&1.oneof != nil))
      |> Enum.map(&message_field/1)
      |> Enum.into(%{})

    additional_field_map =
      msg.additional_fields
      |> Enum.map(fn {name, attrs} ->
        {
          name,
          %AbsintheProto.Object.MessageField{
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
              |> Enum.filter(&(&1.oneof == id))
              |> Enum.map(&message_field/1)
              |> Enum.into(%{})

            {name, oneof_fields}
          end
      end

    {
      mod,
      %AbsintheProto.Objects.Blueprint.Message{
        message: msg,
        raw_field_map: raw_field_map,
        additional_field_map: additional_field_map,
        oneof_field_map: oneof_field_map,
      }
    }
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
