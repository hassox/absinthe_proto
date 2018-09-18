defmodule AbsintheProto.Application do
  use Application

  def start(_, _) do
    children = []
    opts = [strategy: :one_for_one, name: AbsintheProto.Supervisor]
    Supervisor.start_link(children, opts)
  end

end
