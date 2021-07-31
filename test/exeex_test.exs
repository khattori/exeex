defmodule ExEExTest do
  use ExUnit.Case
  doctest ExEEx

  test "override inherited template" do
    assert ExEEx.render("test/templates/sub.txt") == """
Header overrided by sub
---
This is body
---
This is footer


"""
  end

  test "override inherited template in block" do
    assert ExEEx.render("test/templates/main_sub_sub.txt") == """
Header overrided by main_sub
---
Body overrided by main_sub
Sub body@main_sub_sub.txt
---
This is footer



"""
  end

  test "include in include body" do
    assert ExEEx.render("test/templates/sub2.txt") == """
This is header
---
Body overrided by sub2:
{This is header
---
This is body
---
This is footer

}---
This is footer


"""
  end

  test "multiple include same template" do
    assert ExEEx.render("test/templates/sub3.txt") == """
Header overrided by sub3
---
This is body
---
This is footer


This is header
---
Body overrided by sub3
---
This is footer


This is header
---
This is body
---
Footer overrided by sub3


"""
  end

  test "include template specified by abspath" do
    abspath = Path.expand("test/templates/body.txt")
    assert ExEEx.render_string("<%= include \"#{abspath}\" %>") == "This is body\n"
  end

  test "include block via include template" do
    assert ExEEx.render("test/templates/sub5.txt") == """
Header from sub5
---
This is body
---
This is footer



"""
  end

  test "subdir template" do
    assert ExEEx.render("test/templates/subdir/subsub.txt") == """
Header overrided by sub
---
This is body
---
Footer overrided by subsub


"""
  end

  test "included template has same block" do
    assert ExEEx.render_string("<%= include \"test/templates/same_block.txt\" do %><%= block \"test\" do %>This is overrided block<% end %><% end %>") == """
This is overrided block
This is overrided block
"""
  end

  test "mix include template" do
    assert ExEEx.render_string("<%= include \"test/templates/mix.txt\" do %><%= block \"block2\" do %>This is Block2<% end %><%= block \"block1\" do %>This is Block1<% end %><% end %>") == """
This is Block1

This is Block2

"""
  end

  test "include with empty block body" do
    assert ExEEx.render_string(~s'<%= include "test/templates/block1.txt" do %><%= block "block1" %><% end %>') == "\n"
  end

  test "super directive" do
    assert ExEEx.render_string(~s'<%= include "test/templates/super.txt" do %><%= block "body" do %><%= super %>(In sub)<% end %><% end %>') == "Hello world\nIn super(In sub)\n"
  end

  test "super directive error" do
    assert_raise ExEEx.TemplateError, fn ->
      ExEEx.compile_string("<%= super %>")
    end
  end

  test "undefined block error" do
    assert_raise ExEEx.TemplateError, fn ->
      ExEEx.compile_string("<%= include \"test/templates/main.txt\" do %><%= block \"undefined\" do %>undefined<% end %><% end %>")
    end
  end

  test "cyclic include error" do
    assert_raise ExEEx.TemplateError, fn ->
      ExEEx.compile("test/templates/cyclic_error.txt")
    end
    assert_raise ExEEx.TemplateError, fn ->
      ExEEx.compile("test/templates/cyclic_error1.txt")
    end
    assert_raise ExEEx.TemplateError, fn ->
      ExEEx.compile_string("<%= include \"test/templates/cyclic_error2.txt\" %>")
    end

    assert_raise ExEEx.TemplateError, fn ->
      ExEEx.compile_string("<%= include \"test/templates/cyclic_error.txt\" %>")
    end
  end

  test "invalid include type" do
    assert_raise ExEEx.TemplateError, fn ->
      ExEEx.compile_string("<%= include x %>")
    end
  end

  test "no such file include error" do
    assert_raise File.Error, fn ->
      ExEEx.compile_string("<%= include \"file not found\" %>")
    end
  end

  test "block override error" do
    assert_raise ExEEx.TemplateError, fn ->
      ExEEx.compile("test/templates/dup_block_error.txt")
    end
    assert_raise ExEEx.TemplateError, fn ->
      assert ExEEx.render_string(~s'<%= include "test/templates/block1.txt" do %><%= block "block1" %><%= block "block1" %><% end %>')
    end
  end

  test "macro expand" do
    assert ExEEx.render("test/templates/macro.txt", assigns: [ext_var: "EXT_VAR"]) == """




NO ARGS MACRO
NO ARGS MACRO2
MACRO(EXT_VAR) ARG, ARG
MACRO2 FOO, DEFAULT
MACRO2 FOO, BAR
"""
  end

  test "macro arg error" do
    assert_raise ExEEx.TemplateError, fn ->
      ExEEx.compile_string("<%= def @macro(arg, arg) do %><% end %>")
    end
  end

  test "macro call from macro" do
    assert ExEEx.render("test/templates/macro2.txt", assigns: [ext_var: "EXT"]) == """



FROM MACRO
MACRO(EXT) CALL, CALL

"""
  end

  test "duplicate macro definition error" do
    assert_raise ExEEx.TemplateError, fn ->
      ExEEx.render_string("<%= def @foo do %>BAR<% end %><%= def @foo(x) do %>FOO<% end %><%= @foo() %>")
    end
  end

  test "undefined macro error" do
    assert_raise ExEEx.TemplateError, fn ->
      ExEEx.compile_string("<%= def @macro() do %><% end %><%= @macro(val) %>")
    end
    assert_raise ExEEx.TemplateError, fn ->
      ExEEx.compile_string("<%= @undef_macro() %>")
    end
  end

  test "include macros file but do not include macros in the file" do
    assert_raise ExEEx.TemplateError, fn ->
      ExEEx.compile_string("<% include \"test/templates/macro.txt\" %><%= @macro_no_args() %>")
    end
  end

  test "importing macros file include macros in the file" do
    assert ExEEx.render_string("<% import \"test/templates/macro.txt\" %><%= @macro_no_args() %>") == "NO ARGS MACRO"
  end

  test "importing macros file into namespace" do
    assert_raise ExEEx.TemplateError, fn ->
      ExEEx.render_string("<% import \"test/templates/macro.txt\", as: utils %><%= @macro_no_args() %>")
    end
    assert ExEEx.render_string("<% import \"test/templates/macro.txt\", as: utils %><%= utils::@macro_no_args() %>") == "NO ARGS MACRO"
  end

  test "invalid macros import error" do
    assert_raise ExEEx.TemplateError, fn ->
      ExEEx.render_string("<%= import \"test/templates/macro.txt\" do %><% end %>")
    end
  end

  test "macros namespace error" do
    assert_raise ExEEx.TemplateError, fn ->
      ExEEx.render_string("<%= unknown::@macro() %>")
    end
  end
end
