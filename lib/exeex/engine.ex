defmodule ExEEx.Engine do
  use EEx.Engine

  def do_block(name, block \\ nil) do
    defblocks = peek(:defblocks)
    update_peek(:defblocks, [name | defblocks])
    #
    # [NOTE]
    # ブロック辞書は、S: include A -> A: include B ->  B: include C -> C
    # というインクルードチェインの場合、[C, B, A, S]という並びでblocksスタックに積まれる
    # スタックの先頭から辞書をマージしていくことで、ブロックの検索順序は逆順のS, A, B, Cとなる
    #
    Process.get(:blocks)
    |> Enum.map(fn block_map -> Map.get(block_map,  name) end)
    |> Enum.reduce(block, &replace_super/2)
  end

  #
  # blockにsuperがあれば置き換えてsuper_blockで差し替える
  #
  defp replace_super(nil, super_block), do: super_block
  defp replace_super(block, super_block) do
    Macro.postwalk(block,
      fn
        {:super, _, _} -> super_block
        ast -> ast
      end
    )
  end

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

  def expand_macro(block, check_super \\ true)
  def expand_macro([do: block], check_super), do: [do: expand_macro(block, check_super)]
  def expand_macro(block, check_super) do
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
             defblocks = peek(:defblocks)
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
           {:super, [line: line], _}, _acc when check_super ->
             {_dir, file_name} = peek(:includes)
             raise ExEEx.TemplateError, message: "super directive must be in an include block: #{file_name}:#{inspect line}"
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

  def handle_expr(state, mark, ast) do
    {ast, state} = Macro.prewalk(ast, state, &handle_macro/2)
    super(state, mark, ast)
  end

  def init(opts) do
    super(opts)
    |> Map.put(:macros, %{})
  end

  #
  # マクロ定義の処理を行う
  # ---
  #
  # マクロ定義の形式は以下のとおり
  #
  # <% def @macro_fun(arg1, arg2 \\ default) do %>
  #   BODY
  # <% end %>
  #
  defp handle_macro({:def, _, [{:@, _, [{name, _, args}]}, [do: body]]}, state) when is_atom(name) do
    #
    # argsを引数名をキーとするKeywordリストに変換する
    #
    #   [
    #     <arg_name1>: :mandatory,
    #     <arg_name2>: {:optional, <default>},    # デフォルト値付きの場合
    #     ...
    #   ]
    #

    #
    # マクロ定義の重複チェック
    #
    if Map.has_key?(state.macros, name) do
      raise ExEEx.TemplateError, message: "duplicate macro definition: #{name}"
    end

    args =
      Enum.map(args || [],
        fn
          {arg_name, _, nil} -> {arg_name, :mandatory}
          {:\\, _, [{arg_name, _, nil}, default_value]} -> {arg_name, {:optional, default_value}}
        end
      )
      |> check_dup_args()
    arities = count_arity(args)

    #
    # 変数の衝突を避けるためにガードする
    #
    body = mk_guard(body)
    state =
      put_in(state, [:macros, name], {args, arities, body})
    {nil, state}
  end
  #
  # マクロの展開を行う
  # ---
  #
  # <%= macro_fun(param1, param2) %>
  #
  defp handle_macro({:@, _, [{name, _, params}]}, state) when is_atom(name) and not is_nil(params) do
    #
    # マクロ定義の検索
    #
    arity = length(params)
    Map.get(state.macros, name)
    |> case do
         {args, arities, body} ->
           #
           # 引数のチェック
           #
           if arity not in arities do
             raise ExEEx.TemplateError, message: "undefined macro: #{name}/#{arity}"
           end
           #
           # 渡されたパラメータを引数に束縛して環境を作成する
           #
           {env, _} =
             Enum.map_reduce(
               args,
               %{params: params, extra: arity - arities.first},
               fn
                 {arg_name, :mandatory}, %{params: [param | rest_params], extra: extra} -> {{arg_name, param}, %{params: rest_params, extra: extra}}
                 {arg_name, {:optional, default}}, %{params: params, extra: 0} -> {{arg_name, default}, %{params: params, extra: 0}}
                 {arg_name, {:optional, _default}}, %{params: [param | rest_params], extra: extra} -> {{arg_name, param}, %{params: rest_params, extra: extra - 1}}
               end
             )
           #
           # 束縛環境の元でマクロ本体を展開する
           #
           {body, _env} = Macro.prewalk(body, env, &subst_param/2)
           body = Macro.prewalk(body, &EEx.Engine.handle_assign/1)
           {body, state}
         _ -> raise ExEEx.TemplateError, message: "undefined macro: #{name}/#{arity}"
       end
  end
  defp handle_macro(ast, state), do: {ast, state}

  #
  # マクロ本体での変数展開
  #
  # ---
  # <%= @foo %>
  # 環境中に foo 変数が定義されていれば、展開する
  # 無ければ、EExのassignsとして処理する
  #
  defp subst_param({:@, _, [{name, _, atom}]} = ast, env) when is_atom(name) and is_atom(atom) do
    ast =
      Keyword.get(env, name)
      |> case do
           nil -> EEx.Engine.handle_assign(ast)
           param -> param
         end
    {ast, env}
  end
  defp subst_param(ast, env), do: {ast, env}

  defp check_dup_args(args) do
    for {key, count} <- Enum.frequencies_by(args, fn {k, _v} -> k end) do
      if count > 1 do
        raise ExEEx.TemplateError, message: "duplicate macro argument: #{key}"
      end
    end
    args
  end

  defp count_arity(args) do
    min = Enum.count(args, fn {_k, v} -> v == :mandatory end)
    max = length(args)
    min..max
  end
end
