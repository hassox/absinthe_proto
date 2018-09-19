defmodule AbsintheProtoTest do
  use ExUnit.Case
  doctest AbsintheProto

  test "greets the world" do
    result =
      Absinthe.run( """
          query {
            repeatedNested {
              basics {
                name
                enumValue
                __typename
              }
              __typename
            }
            user {
              id
              name
              extra_field
              another_field
              __typename
            }
            basic {
              name
              enumValue
              __typename
            }
            oneof {
              id
              __typename
              union_enum {
                string_value
                int_value
                enum_value
                __typename
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
