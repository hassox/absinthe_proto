defmodule AbsintheProto.MixProject do
  use Mix.Project

  def project do
    [
      app: :absinthe_proto,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixir_paths(Mix.env()),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def elixir_paths(:absinthe_proto) do
    ~w(lib test/support)
  end

  def elixir_paths(:test),
    do: ~w(lib test/support)

  def elixir_paths(_),
    do: ~w(lib)

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:protobuf, github: "tony612/protobuf-elixir", override: true},
      # {:grpc, github: "tony612/grpc-elixir", override: true},
      {:protobuf, ">= 0.0.0"},
      {:grpc, ">= 0.0.0"},
      {:google_protos, "~> 0.1"},
      {:absinthe, "~>1.4"},
    ]
  end
end
