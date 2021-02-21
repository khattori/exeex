# ExEEx

ExEEx is an Elixir template engine with macro and template import and
inheritance capabilities.


# Usage

      iex> ExEEx.render_string("foo <%= bar %>", bar: "baz")
      "foo baz"

      iex> ExEEx.render("template_file.eex", bar: "baz")
      "foo baz"


## Include directive

The include directive is used to include another template file.

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
      <% end %>

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

## Super directive

The super directive is used to refer to an included template block.

super.eex:

      Hello world
      <%= block "body" do %>In super<% end %>

sub.eex:

      <%= include "super.eex" do %>
      <%= block "body" do %><%= super %>(In sub)<% end %>
      <% end %>

The rendering output of sub.eex is as follows:

      Hello World
      In super(In sub)

## Macro directive

The macro directive defines a macro.

    <% def @checkbox_input(name, checked, disabled) do %>
    <input type="checkbox" name="<%= @name %>" id="id_<%= @name %>" <%= if @checked do %>checked<% end %> <%= if @disabled do %>disabled<% end %>>
    <% end %>

Using macros:

    <%= @input("checkbox", true, true) %>

## Import macros

Import macros:

    <% import "macro_defs.txt" %>
    <%= @input("check_box", true, true) %>

or import macros into specified namespace.

    <% import "macro_defs.txt", as: view %>
    <%= view::@input("check_box", true, true) %>
