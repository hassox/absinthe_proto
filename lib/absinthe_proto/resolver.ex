defmodule AbsintheProto.Resolver do
  @moduledoc """
  Builds a resolver for a given service.

  This implements a simple resolver.

  If no custom resolver is set, the default resolver will be used with the client provided at compile time.
  """

  import AbsintheProto.Utils

  @typedoc "Protobuf Service module"
  @type service :: module

  @typedoc "The module name of the resolver"
  @type resolver_name :: atom

  @typedoc "The client to use in the resolver"
  @type client :: module

  @doc "Creates the module `resolver_name` using the provided client"
  @callback build_resolver(service, resolver_name, client) :: {:module, module(), binary(), term()} | {:error, term}


  @spec build_resolver(service, resolver_name, client) :: {:module, module(), binary(), term()} | {:error, term}
  def build_resolver(service, resolver_name, client)
  when is_nil(service) or is_nil(resolver_name) or is_nil(client),
    do: {:error, :invalid_argument}

  def build_resolver(service, resolver_name, client) do
    quoted_source =
      for {raw_name, {_, _streamin}, {_, _streamout}} <- service.__rpc_calls__ do
        fun_name = rpc_name_to_gql_name(raw_name)

        quote location: :keep do
          def unquote(fun_name)(_, args, _) do
            apply(unquote(client), unquote(fun_name), args)
          end
        end
      end

    Module.create(resolver_name, quoted_source, Macro.Env.location(__ENV__))
  end

  @doc """
  Fetches the configured resolver builder or uses this module
  """
  @spec fetch_resolver_builder() :: module
  def fetch_resolver_builder() do
    case Application.get_env(:absinthe_proto, :resolver_builder, __MODULE__) do
      nil ->
        require Logger
        Logger.error "No resolver builder config"
        __MODULE__
      cb ->
        Code.ensure_compiled(cb)
        cb
    end
  end
end