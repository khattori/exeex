defmodule ExEEx.Engine do
  def do_include(name, block_map \\ %{})
  def do_include(name, block_map) when is_binary(name) do
    adapter = Application.get_env(:exeex, :adapter, ExEEx.Adapter.FileStorage)
    include_stack = Process.get(:includes)
    #
    # includeするファイルの絶対パスを取得
    #
    file_path =
      include_stack
      |> hd()
      |> elem(0)
      |> Path.join(name)        # dir/name を作成
      |> adapter.expand_path()  # 絶対パスに変換
    {dir, name} = {Path.dirname(file_path), Path.basename(file_path)}
    if {dir, name} in include_stack do
      raise ExEEx.TemplateError, message: "detected cyclic include: #{dir}/#{name}"
    end
    #
    # includeスタックに ファイルパスをプッシュ
    #
    push(:includes, {dir, name})
    push(:blocks, block_map)
    push(:defblocks, [])
    #
    # テンプレートの読み込みとコンパイル
    #
    file_path
    |> adapter.read()
    |> EEx.compile_string()
    |> mk_guard()
  end
  def do_include(_name, _map), do: raise ExEEx.TemplateError, message: "include parameter should be a string literal"

  def expand_macro([do: block]), do: [do: expand_macro(block)]
  def expand_macro(block) do
    block
    |> Macro.traverse(nil,
         fn
           {:include, _, _} = body, acc ->
             #
             # include のマーカーを挿入
             #
             {{:__enter__, [], [Macro.expand(body, make_env())]}, acc}
           block, acc ->
             {Macro.expand(block, make_env()), acc}
         end,
         fn
           {:__enter__, _, [body]}, acc ->
             #
             # block定義をチェック
             #
             # ---+---> block A, B
             #    |
             #    +---> block C, D, E
             #
             # ---> block A, B, C, D, E にマージされる
             #
             defblocks = pop(:defblocks)
             update_peek(:defblocks, defblocks ++ peek(:defblocks))
             blocks = pop(:blocks)
             for block <- Map.keys(blocks) do
               if block not in defblocks do
                 raise ExEEx.TemplateError, message: "block \"#{block}\" is not found"
               end
             end
             #
             # includeスタックから要素をポップ
             #
             pop(:includes)
             #
             # include のマーカーを削除
             #
             {body, acc}
           block, acc -> {block, acc}
         end
       )
    |> elem(0)
    |> mk_guard()
  end

  defp mk_guard(block) do
    #
    # 変数の衝突を防ぐために、関数でガードしてローカルスコープにする
    # (fn -> <BLOCK> end).()
    #
    {{:., [], [{:fn, [], [{:->, [], [[], block]}]}]}, [], []}
  end

  defp make_env() do
    require ExEEx.Macro
    import ExEEx.Macro, only: [block: 1, block: 2, include: 1, include: 2]
    __ENV__
  end

  defp push(key, val) do
    Process.put(key, [val | Process.get(key)])
  end

  defp pop(key) do
    [head | tail] = Process.get(key)
    Process.put(key, tail)
    head
  end

  def peek(key) do
    Process.get(key) |> hd()
  end

  def update_peek(key, val) do
    Process.put(key, [val | Process.get(key) |> tl()])
  end

  def block_map() do
    Process.get(:blocks)
    |> Enum.reduce(fn m, acc -> Map.merge(acc, m) end)
  end
end
