# AbsintheProto

Maps grpc services to graphql.

This is alpha and not ready for production.

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `absinthe_proto` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:absinthe_proto, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/absinthe_proto](https://hexdocs.pm/absinthe_proto).

"First, make it correct. Then, make it beautiful. Then, if you need to, make it performant. Chances are once you've made it beautiful you'll find it sufficiently performant" - Joe Armstrong

- [ ] Make it correct
- [ ] Make it beautiful
- [ ] Decide if it's not performant enough

### Specifics

- [x] Basic messages
- [x] Repeated messages
- [x] Enums
- [x] Oneofs
- [x] Loading in app
- [x] Loading Other app
- [x] Exclude fields
- [x] Overwrite Fields
- [x] Input Objects
- [x] id alias
- [x] Services (with manual resolvers)
- [x] Foreign Keys
- [ ] Maps
- [ ] Service Resolvers
