defmodule AbsintheProtoTest do
  use ExUnit.Case
  doctest AbsintheProto

  test "greets the world" do
    result =
      Absinthe.run( """
          query {
            basic {
              name
              enumValue
            }
            oneof {
              id
              union_enum {
                string_value
                int_value
                enum_value
              }
            }
          }
        """,
        AbsintheProtoTest.Schema
      )
    # result =
    #   Absinthe.run( """
    #       query {
    #         __schema {
    #           types {
    #             name
    #             fields {
    #               name
    #             }
    #           }
    #         }
    #       }
    #     """,
    #     AbsintheProtoTest.Schema
    #   )
    #
    IO.inspect(result)
  end
end
