# ExEEx
 An Elixir template engine extended to include and inherit templates

# Usage

      iex> ExEEx.render_string("foo <%= bar %>", bar: "baz")
      "foo baz"

## Include directive

Include directive to include another template file.

main.eex:

      <%= include "header.eex" %>
      Hello world

header.eex:

      This is header

The rendering output of main.eex is as follows:

      This is header
      Hello world

## Block directive

The block directive is used to override part of the included text.

super.eex:

      Hello world
      <%= block "body" do %>In super<% end %>

sub.eex:

      <%= include "super.eex" do %>
      <%= block "body" do %>In sub<%= block "subbody" %><% end %>
      <% end>

subsub.eex:

      <%= include "sub.eex" do %>
      <%= block "subbody" do %>(In subsub)<% end %>
      <% end %>

The rendering output of super.eex is as follows:

      Hello World
      In super

The rendering output of sub.eex is as follows:

      Hello World
      In sub

The rendering output of subsub.eex is as follows:

      Hello World
      In sub(In subsub)
