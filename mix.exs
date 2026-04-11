defmodule ExEEx.MixProject do
  use Mix.Project
  @description """
  Exeex is an Elixir template engine that provides macro, include and inheritance functions.
  It allows you to create reusable templates with dynamic content,
  making it easier to manage and maintain your views in Elixir applications.
  """
  def project do
    [
      app: :exeex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description: @description,
      package: package(),
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

  defp package do
    [
      maintainers: ["Kenta Hattori"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/khattori/exeex"}
    ]
  end
  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18.5", only: :test},
      {:mix_version, "~> 2.4.0", only: [:dev, :test], runtime: false},
    ]
  end
end
