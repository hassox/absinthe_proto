defmodule AbsintheProto.Application do
  use Application
  require Logger

  def start(_, _) do
    children = []

    validate_modify_message!()

    opts = [strategy: :one_for_one, name: AbsintheProto.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp validate_modify_message! do
    case Application.get_env(:absinthe_proto, :modify_message) do
      str when is_binary(str) ->
        Code.eval_string(str)
        true
      _ ->
        true
    end
  rescue 
    err ->
      Logger.error("\n\nInvalid configuration (syntax error) for `config :absinthe_proto, :modify_message`\n\n")
      reraise(err, __STACKTRACE__)
  end
end
