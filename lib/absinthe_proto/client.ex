defmodule AbsintheProto.Client do
  @moduledoc """
  Builds a client module that provides a grpc client
  """

  @typedoc """
  A protocol buffer service module
  """
  @type service :: module

  @typedoc "The client name"
  @type client_module_name :: module

  @doc """
  Build the contents of a particular resolver 
  Returns the quoted source of the body of the client module
  """
  @callback build_client(service, client_module_name) :: {:module, module(), binary(), term()} | {:error, term}

  @doc """
  Fetches the configured client builder
  """
  @spec fetch_client_builder() :: module
  def fetch_client_builder() do
    case Application.get_env(:absinthe_proto, :client_builder) do
      nil ->
        require Logger
        Logger.error "ENV: #{inspect(Application.get_all_env(:absinthe_proto))}"
        raise "no client buidler specified"
      cb -> 
        Code.ensure_compiled(cb)
        cb
    end
  end
end