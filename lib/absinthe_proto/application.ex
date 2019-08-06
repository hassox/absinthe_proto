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
    AbsintheProto.DSL.load_modify_message()
  rescue
    err ->
      Logger.error("\n\nInvalid configuration (syntax error) for `config :absinthe_proto, :modify_message`\n\n")
      reraise(err, __STACKTRACE__)
  end
end
