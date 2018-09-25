defmodule AbsintheProtoTest do
  use ExUnit.Case
  doctest AbsintheProto

  test "greets the world" do
    result =
      Absinthe.run( """
          query {
            getBasic(name: "foo", enumValue: ONE) {
              name
              enumValue
              __typename
            }

            getOneof(id: "3", unionEnum: {stringValue: "bob"}){
              id
              __typename
              unionEnum {
                stringValue
                intValue
                enumValue
                userToken
                user {
                 id
                 token
                }
                __typename
              }
            }
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
              token
              name
              extraField
              anotherField
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
              unionEnum {
                stringValue
                intValue
                enumValue
                __typename
              }
            }
          }
        """,
        AbsintheProtoTest.Schema
      )
    assert {:ok, %{data: data}} = result
    IO.inspect(data)
  end
end
