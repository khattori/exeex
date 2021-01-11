defmodule ExEEx.Macro do
  @doc ~S"""
  <%= block "header" %>

  <%= block "header" do %>
   This is default block header
  <% end %>

  <%= block "super" do %>
    <%= block super %>
  <% end %>
  """
  defmacro block(name), do: ExEEx.Engine.do_block(name)
  defmacro block(name, do: block), do: ExEEx.Engine.do_block(name, block)

  @doc ~S"""
  <%= include "main.tpl" do %>
    <% block "foo" do %>
    <% end %>
  <% end %>
  """
  defmacro include(name), do: ExEEx.Engine.do_include(name)
  defmacro include(name, do: body) do
    #
    # include body をたどって、block 定義を抽出する
    #
    {_node, block_map} =
      body
      |> Macro.prewalk(%{},
           fn
             {:block, _line, [block_name, [do: block_body]]} = block, acc when is_binary(block_name) ->
               {
                 block,
                 if Map.has_key?(acc, block_name) do
                   raise ExEEx.TemplateError, message: "block \"#{block_name}\" already exists"
                 else
                   # この時点でblock_bodyを展開する
                   block_body = ExEEx.Engine.expand_macro(block_body, false)
                   Map.put_new(acc, block_name, block_body)
                 end
               }
             block, acc ->
               {block, acc}
           end
         )
    ExEEx.Engine.do_include(name, block_map)
  end
end
