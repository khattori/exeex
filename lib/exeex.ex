defmodule ExEEx do
  @moduledoc """
  Documentation for ExEEx.
  """
  @adapter Application.get_env(:exeex, :adapter, ExEEx.Adapter.FileStorage)
  def adapter(), do: @adapter

  @doc """
  Render template file.

  ## Examples

      iex> ExEEx.render("test/templates/hello.txt", val: "world")
      "Hello, world!\\n"

      iex> ExEEx.render("test/templates/main.txt")
      "This is header\\n---\\nThis is body\\n---\\nThis is footer\\n\\n"

      iex> ExEEx.render("test/templates/main.txt", [{"foo", 3}])
      ** (ExEEx.TemplateError) expected keywords as template parameters

  """
  def render(filename, params \\ [])
  def render(%ExEEx.Template{code: code}, params) when is_list(params) do
    if not Keyword.keyword?(params) do
      raise ExEEx.TemplateError, message: "expected keywords as template parameters"
    end
    {result, _binding} = Code.eval_quoted(code, params)
    result
  end
  def render(filename, params) when is_binary(filename) and is_list(params) do
    compile(filename)
    |> render(params)
  end

  @doc """
  Render template string.

  ## Examples

      iex> ExEEx.render_string("Hello, world!")
      "Hello, world!"

      iex> ExEEx.render_string("<%= include \\"test/templates/hello.txt\\" %>OK", val: "world")
      "Hello, world!
      OK"

      iex> ExEEx.render_string("<%= block \\"header\\" do %>This is default header<% end %>")
      "This is default header"

      iex> ExEEx.render_string("<%= block \\"test\\" %>")
      ""

      iex> ExEEx.render_string("<% block invalid %>")
      ** (ExEEx.TemplateError) block name should be a string literal: nofile:1
  """
  def render_string(template, params \\ []) when is_list(params) do
    compile_string(template)
    |> render(params)
  end

  @doc """
  Compile template file.

  ## Examples

      iex> ExEEx.compile("test/templates/hello.txt").name
      "hello.txt"
  """
  def compile(filename, opts \\ []) when is_binary(filename) do
    file_path = @adapter.expand_path(filename)
    @adapter.read(file_path)
    |> compile_string(Keyword.put(opts, :file, file_path))
  end

  @doc """
  Compile template file.

  ## Examples

      iex> ExEEx.compile_string("Hello, world!").name
      :nofile
  """
  def compile_string(source, opts \\ []) when is_binary(source) do
    {dir, name} =
      with nil <- Keyword.get(opts, :file) do
        #
        # インメモリの場合、現在のディレクトリ
        #
        {@adapter.expand_path("."), :nofile}
      else
        file ->
          # 絶対パスに変換
          file_path = @adapter.expand_path(file)
          #
          # ファイルパスが渡されている場合、ディレクトリとベース名に分割
          #
          ExEEx.Utils.split_path(file_path)
      end
    file_name = to_string(name)
    opts =
      opts
      |> Keyword.put(:file, file_name)
      |> Keyword.put(:dir, dir)
      |> Keyword.put(:includes, [])
      |> Keyword.put(:engine, ExEEx.Engine)
    ExEEx.Engine.BlockStack.init()
    {code, _} =
      EEx.compile_string(source, opts)
      |> ExEEx.Engine.subst_blocks(file_name)
    %ExEEx.Template{
      code: code,
      path: dir,
      name: name
    }
  end
end
