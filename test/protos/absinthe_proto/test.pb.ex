defmodule AbsintheProto.Test.Basic do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
    name:       String.t,
    enum_value: integer
  }
  defstruct [:name, :enum_value]

  field :name, 1, type: :string
  field :enum_value, 2, type: AbsintheProto.Test.Basic.SimpleEnum, enum: true
end

defmodule AbsintheProto.Test.Basic.SimpleEnum do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto3

  field :DEFAULT, 0
  field :ONE, 1
end

defmodule AbsintheProto.Test.User do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
    token:           String.t,
    name:            String.t,
    extra_field:     integer,
    field_to_remove: non_neg_integer
  }
  defstruct [:token, :name, :extra_field, :field_to_remove]

  field :token, 1, type: :string
  field :name, 2, type: :string
  field :extra_field, 3, type: :int64
  field :field_to_remove, 4, type: :uint64
end

defmodule AbsintheProto.Test.Oneof do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
    union_enum:      {atom, any},
    id:              String.t
  }
  defstruct [:union_enum, :id]

  oneof :union_enum, 0
  field :id, 1, type: :string
  field :string_value, 2, type: :string, oneof: 0
  field :int_value, 3, type: :int32, oneof: 0
  field :enum_value, 4, type: AbsintheProto.Test.Basic.SimpleEnum, enum: true, oneof: 0
  field :field_to_remove, 5, type: :uint64, oneof: 0
  field :user_token, 6, type: :string, oneof: 0
end

defmodule AbsintheProto.Test.WithAny do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
    anything: Google.Protobuf.Any.t
  }
  defstruct [:anything]

  field :anything, 1, type: Google.Protobuf.Any
end

defmodule AbsintheProto.Test.RepeatedNested do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
    basics: [AbsintheProto.Test.Basic.t]
  }
  defstruct [:basics]

  field :basics, 1, repeated: true, type: AbsintheProto.Test.Basic
end

defmodule AbsintheProto.Test.WithForeignKey do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
    id:         String.t,
    user_token: String.t
  }
  defstruct [:id, :user_token]

  field :id, 1, type: :string
  field :user_token, 2, type: :string
end

defmodule AbsintheProto.Test.Service.Service do
  @moduledoc false
  use GRPC.Service, name: "absinthe_proto.test.Service"

  rpc :GetBasic, AbsintheProto.Test.Basic, AbsintheProto.Test.Basic
  rpc :GetOneof, AbsintheProto.Test.Oneof, AbsintheProto.Test.Oneof
end

defmodule AbsintheProto.Test.Service.Stub do
  @moduledoc false
  use GRPC.Stub, service: AbsintheProto.Test.Service.Service
end

