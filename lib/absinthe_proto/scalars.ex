defmodule AbsintheProto.Scalars do
  use Absinthe.Schema.Notation
  # other types :group, :message, :enum
  @type_map [
    float: :float,
    double: :float,
    string: :string,
    bool: :boolean,
    bytes: :bytes,
    int32: :integer,
    fixed32: :uint32,
    uint32: :uint32,
    sint32: :integer,
    sfixed32: :integer,
    int64: :int64,
    sint64: :int64,
    fixed64: :uint64,
    sfixed64: :int64,
    uint64: :uint64
  ]

  def proto_to_gql_scalar(type) do
    Keyword.get(@type_map, type, :error)
  end

  @desc "Base64 encoded string (URL encoded)"
  scalar :bytes do
    parse fn
      nil -> {:ok, nil}
      str -> Base.url_decode64(str)
    end

    serialize fn
      nil -> nil
      str -> Base.url_encode64(str, padding: true)
    end
  end

  @desc "Non negative 32 bit integer"
  scalar :uint32 do
    parse fn
      nil -> {:ok, nil}
      n when is_binary(n) ->
        case Integer.parse(n) do
          :error -> :error
          {i, _} -> ensure_non_neg(i)
        end
      n when is_integer(n) -> ensure_non_neg(n)
      n when is_float(n) -> ensure_non_neg(Kernel.trunc(n))
      _ -> :error
    end

    serialize fn
      nil -> nil
      n -> n
    end
  end

  @desc "64 bit integer. Encoded as a string"
  scalar :int64 do
    parse fn
      nil -> {:ok, nil}
      n when is_binary(n) ->
        case Integer.parse(n) do
          :error -> :error
          {i, _} -> {:ok, i}
        end
      n when is_integer(n) -> {:ok, n}
      n when is_float(n) -> {:ok, Kernel.trunc(n)}
      _ -> :error
    end

    serialize fn
      nil -> nil
      n -> to_string(n)
    end
  end

  @desc "non negative 64 bit integer. Encoded as a string"
  scalar :uint64 do
    parse fn
      nil -> {:ok, nil}
      n when is_binary(n) ->
        case Integer.parse(n) do
          :error -> :error
          {i, _} -> ensure_non_neg(i)
        end
      n when is_integer(n) -> ensure_non_neg(n)
      n when is_float(n) -> ensure_non_neg(Kernel.trunc(n))
      _ -> :error
    end

    serialize fn
      nil -> nil
      n -> to_string(n)
    end
  end

  def ensure_non_neg(n) when n >= 0, do: {:ok, n}
  def ensure_non_neg(_n), do: :error
end
