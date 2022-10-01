defmodule ExEEx.Engine do
  @behaviour EEx.Engine

  defmodule BlockStack do
    @key :exeex_block_stack

    def init() do
      Process.put(@key, [MapSet.new()])
    end

    def push() do
      Process.put(@key, [MapSet.new() | Process.get(@key)])
    end

    def merge_and_pop() do
      [fst, snd | tail] = Process.get(@key)
      Process.put(@key, [MapSet.union(fst, snd) | tail])
    end

    def add(names) when is_list(names), do: add(MapSet.new(names))
    def add(%MapSet{} = names) do
      [head | tail] = Process.get(@key)
      Process.put(@key, [MapSet.union(names, head) | tail])
    end

    def check(block_params) do
      [head | _tail] = Process.get(@key)
      for {name, %{file: file, line: line}} <- block_params do
        if not MapSet.member?(head, name) do
          raise ExEEx.TemplateError, message: "undefined block name: #{name}: #{file}:#{line}"
        end
      end
    end
  end

  @impl true
  def init(opts) do
    EEx.Engine.init(opts)
    |> Map.put(:macros, %{})
    |> Map.put(:namespaces, %{})
    |> Map.put(:includes, Keyword.get(opts, :includes))
    |> Map.put(:block_envs, Keyword.get(opts, :block_envs, []))
    |> Map.put(:file, Keyword.get(opts, :file))
    |> Map.put(:dir, Keyword.get(opts, :dir))
  end

  @impl true
  def handle_expr(state, mark, ast) do
    {ast, state} =
      Macro.prewalk(ast, state, &handle_directive/2)
    EEx.Engine.handle_expr(state, mark, ast)
  end

  @impl true
  def handle_body(state) do
    # マクロ定義を保存する
    macros = Map.get(state, :macros, %{})
    Process.put(:exeex_macro_defs, macros)
    EEx.Engine.handle_body(state)
  end

  @impl true
  defdelegate handle_begin(state), to: EEx.Engine

  @impl true
  defdelegate handle_end(state), to: EEx.Engine

  @impl true
  defdelegate handle_text(state, meta, text), to: EEx.Engine

  #
  # インクルード処理を行う
  # ---
  #
  # インクルードの形式は以下のとおり
  #
  # <% include "template_file.html" %>
  #
  defp handle_directive({:include, _, [path]}, state) when is_binary(path) do
    {do_include(path, state.dir, state.includes, %{}, MapSet.new(), state.block_envs), state}
  end
  #
  # <%= include "template_file.html" do %>
  #    <%= block "header" do %><% end %>
  # <% end %>
  #
  defp handle_directive({:include, _, [path, [do: body]]}, state) when is_binary(path) do
    #
    # include body をたどって、block 定義を抽出する
    #
    {_node, env} = Macro.prewalk(body, %{block_env: %{}, block_params: %{}, inner_blocks: MapSet.new(), file: state.file}, &make_blockenv/2)
    {do_include(path, state.dir, state.includes, env.block_params, env.inner_blocks, [env.block_env | state.block_envs]), state}
  end
  defp handle_directive({:include, [line: line], _args}, state) do
    raise ExEEx.TemplateError, message: "include parameter should be a string literal: #{state.file}:#{line}"
  end

  #
  # マクロ定義ファイルのインポート
  # ---
  # <% import "macro_file.txt" %>
  # <% import "macro_file.txt" as namespace %>
  #
  defp handle_directive({:import, _, [path]}, state) when is_binary(path) do
    {nil, do_import(path, state)}
  end
  defp handle_directive({:import, _, [path, [as: {namespace, _, nil}]]}, state) when is_binary(path) and is_atom(namespace) do
    {nil, do_import(path, namespace, state)}
  end
  defp handle_directive({:import, [line: line], _args}, state) do
    raise ExEEx.TemplateError, message: "invalid macro import: #{state.file}:#{line}"
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
  defp handle_directive({:def, _, [{:@, _, [{name, _, args}]}, [do: body]]}, state) when is_atom(name) do
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
    body = wrap_guard(body)
    state =
      put_in(state, [:macros, name], {args, arities, body})
    {nil, state}
  end
  #
  # マクロの展開を行う
  # ---
  # <%= namespace::@macro_fun(param1, param2) %>
  # <%= @macro_fun(param1, param2) %>
  #
  defp handle_directive({:"::", [line: line], [{namespace, _, _args}, {:@, _, [{name, _, params}]}]}, state) do
    Map.get(state.namespaces, namespace)
    |> case do
         nil -> raise ExEEx.TemplateError, message: "undefined namespace: #{namespace}: #{state.file}:#{line}"
         macros -> {expand_macro(macros, name, params, state.file, line), state}
       end
  end
  defp handle_directive({:@, [line: line], [{name, _, params}]}, state) when is_atom(name) and not is_nil(params) do
    {expand_macro(state.macros, name, params, state.file, line), state}
  end
  defp handle_directive(ast, state), do: {ast, state}

  #
  # マクロ定義の検索
  #
  defp expand_macro(macros, name, params, file, line) do
    arity = length(params)
    case Map.get(macros, name) do
      {args, arities, body} ->
        #
        # 引数のチェック
        #
        if arity not in arities do
          raise ExEEx.TemplateError, message: "undefined macro: #{name}/#{arity}: #{file}:#{line}"
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
        body
      _ ->
        raise ExEEx.TemplateError, message: "undefined macro: #{name}/#{arity}: #{file}:#{line}"
    end
  end

  #
  # マクロファイルのインポート処理
  #
  defp do_import(path, namespace \\ nil, state)
  defp do_import(path, nil, state) do
    {text, file_path, dir, name} = read_path(path, state.dir, state.includes)
    EEx.compile_string(text, file: name, dir: dir, includes: [file_path | state.includes], engine: ExEEx.Engine)
    macros = Process.get(:exeex_macro_defs)
    %{state | macros: Map.merge(state.macros, macros)}
  end
  defp do_import(path, namespace, state) do
    {text, file_path, dir, name} = read_path(path, state.dir, state.includes)
    EEx.compile_string(text, file: name, dir: dir, includes: [file_path | state.includes], engine: ExEEx.Engine)
    macros = Process.get(:exeex_macro_defs)
    %{state | namespaces: Map.put(state.namespaces, namespace, macros)}
  end

  #
  # テンプレートファイルのインクルード処理
  #
  defp do_include(path, dir, includes, block_params, inner_blocks, block_envs) do
    {text, file_path, dir, name} = read_path(path, dir, includes)
    #
    # テンプレートの読み込みとコンパイル
    #
    BlockStack.push()
    {ast, block_names} =
      text
      |> EEx.compile_string(file: name, dir: dir, block_envs: block_envs, includes: [file_path | includes], engine: ExEEx.Engine)
      |> subst_blocks(name, block_envs)
    BlockStack.add(block_names)
    BlockStack.add(inner_blocks)
    BlockStack.merge_and_pop()
    BlockStack.check(block_params)
    wrap_guard(ast)
  end

  defp read_path(path, dir, includes) do
    adapter = ExEEx.adapter()
    #
    # includeするファイルの絶対パスを取得
    #
    file_path =
      case path do
        "/" <> _  -> path
        _ -> Path.join(dir, path)      # 相対パスの場合 dir/name を作成
      end
      |> adapter.expand_path()  # 絶対パスに変換
    {dir, name} = ExEEx.Utils.split_path(file_path)
    if file_path in includes do
      raise ExEEx.TemplateError, message: "detected cyclic include/import: #{file_path}"
    end
    {adapter.read(file_path), file_path, dir, name}
  end

  #
  # ブロック構文の解決
  #
  def subst_blocks(ast, name, block_envs \\ []) do
    # include 対象の構文木から block を抽出して初期を環境作成する
    {_ast, blocks} = Macro.prewalk(ast, %{}, &extract_block/2)
    {ast, _} = Macro.prewalk(ast, %{file_name: name, blocks: blocks, block_envs: block_envs}, &subst_block/2)
    {ast, Map.keys(blocks)}
  end

  #
  # ブロックの出現を置き換える
  #
  defp subst_block({:block, _, [name, [do: body]]}, env) when is_binary(name) do
    {_, block_env} = Enum.reduce(env.block_envs, {env.blocks, %{}}, &merge_envs/2)
    {Map.get(block_env, name, body) |> wrap_guard(), env}
  end
  defp subst_block({:block, _, [name]}, env) when is_binary(name) do
    {_, block_env} = Enum.reduce(env.block_envs, {env.blocks, %{}}, &merge_envs/2)
    {Map.get(block_env, name) |> wrap_guard(), env}
  end
  defp subst_block({:block, [line: line], _}, env) do
    raise ExEEx.TemplateError, message: "block name should be a string literal: #{env.file_name}:#{line}"
  end
  defp subst_block({:super, [line: line], _}, env) do
    raise ExEEx.TemplateError, message: "super directive must be in an include block: #{env.file_name}:#{line}"
  end
  defp subst_block(ast, envs), do: {ast, envs}

  #
  # ブロック環境をマージしていく
  #
  defp merge_envs(env, {blocks, sup_env}) do
    # superを置き換える
    env =
      Enum.map(env,
        fn {name, ast} ->
          {ast, _} = Macro.prewalk(ast, {name, blocks, sup_env}, &subst_super/2)
          {name, ast}
        end
      )
      |> Enum.into(%{})
    {blocks, Map.merge(sup_env, env)}
  end

  #
  # superをinclude元のblock本体で置き換え
  #
  defp subst_super({:super, _, nil}, {name, blocks, env} = acc) do
    sup_body =
      Map.merge(blocks, env)
      |> Map.get(name)
      |> wrap_guard()
    {sup_body, acc}
  end
  defp subst_super(ast, acc), do: {ast, acc}

  defp make_blockenv({:block, [line: line] = meta, [name, [do: body]]}, %{block_env: block_env, block_params: block_params, inner_blocks: inner_blocks, file: file}) when is_binary(name) do
    if Map.has_key?(block_env, name) do
      raise ExEEx.TemplateError, message: "block \"#{name}\" already exists: #{file}:#{line}"
    end
    # body部に入れ子になっているblock定義を抽出する
    {_ast, inner_env} = Macro.prewalk(body, %{}, &extract_block/2)
    # body部に出現するblockは無視する
    new_env = %{
      block_env: Map.put_new(block_env, name, body),
      block_params: Map.put_new(block_params, name, %{file: file, line: line}),
      inner_blocks: MapSet.union(inner_blocks, MapSet.new(Map.keys(inner_env))),
      file: file
    }
    {{:block, meta, [name]}, new_env}
  end
  defp make_blockenv({:block, [line: line], [name]} = ast, %{block_env: block_env, block_params: block_params, file: file} = env) when is_binary(name) do
    if Map.has_key?(block_env, name) do
      raise ExEEx.TemplateError, message: "block \"#{name}\" already exists: #{file}:#{line}"
    end
    new_env = %{env | block_env: Map.put_new(block_env, name, nil), block_params: Map.put_new(block_params, name, %{file: file, line: line})}
    {ast, new_env}
  end
  defp make_blockenv(ast, env), do: {ast, env}

  #
  # block定義を抽出する
  # ---
  #  env: <block_name> -> {<block_body>, <line>}
  #
  defp extract_block({:block, _, [name, [do: body]]} = ast, env) when is_binary(name) do
    {ast, Map.put_new(env, name, body)}
  end
  defp extract_block({:block, _, [name]} = ast, env) when is_binary(name) do
    {ast, Map.put_new(env, name, nil)}
  end
  defp extract_block(ast, env), do: {ast, env}

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
      case Keyword.get(env, name) do
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

  defp wrap_guard(block) do
    #
    # 変数の衝突を防ぐために、関数でガードしてローカルスコープにする
    # (fn -> <BLOCK> end).()
    #
    {{:., [], [{:fn, [], [{:->, [], [[], block]}]}]}, [], []}
  end
end
