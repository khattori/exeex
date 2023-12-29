defmodule ExEEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :exeex,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      description: "Elixir template engine with macro, include and inheritance functions",
      package: [
        maintainers: ["Kenta Hattori"],
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/khattori/exeex"}
      ],
      deps: deps(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :eex]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:ex_doc, "~> 0.31.0", only: :dev, runtime: false},
      {:excoveralls, "~> 0.16.1", only: :test}
    ]
  end
end
