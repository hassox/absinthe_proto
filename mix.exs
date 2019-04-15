defmodule AbsintheProto.MixProject do
  use Mix.Project

  def project do
    [
      app: :absinthe_proto,
      version: "0.2.0",
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
    ~w(lib test/support test/protos)
  end

  def elixir_paths(:test),
    do: ~w(lib test/support test/protos)

  def elixir_paths(_),
    do: ~w(lib)

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:protobuf, github: "tony612/protobuf-elixir", override: true, ref: "fd42cfdfa8eea19659fd89840a7010b635afaca0"},
      # {:protobuf, ">= 0.0.0"},
      {:grpc, ">= 0.0.0"},
      {:google_protos, "~> 0.1"},
      {:absinthe, "~>1.4"},
    ]
  end
end
