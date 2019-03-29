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
    assert ExEEx.render_string("<%= include \"test/templates/same_block.txt\" do %><% block \"test\" do %>This is overrided block<% end %><% end %>") == """
This is overrided block
This is overrided block
"""
  end

  test "mix include template " do
    assert ExEEx.render_string("<%= include \"test/templates/mix.txt\" do %><% block \"block2\" do %>This is Block2<% end %><% block \"block1\" do %>This is Block1<% end %><% end %>") == """
This is Block1

This is Block2

"""
  end

  test "undefined block error" do
    assert_raise ExEEx.TemplateError, fn ->
      ExEEx.compile_string("<%= include \"test/templates/main.txt\" do %><% block \"undefined\" do %>undefined<% end %><% end %>")
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
      ExEEx.compile_string("<% include \"test/templates/cyclic_error2.txt\" %>")
    end

    assert_raise ExEEx.TemplateError, fn ->
      ExEEx.compile_string("<% include \"test/templates/cyclic_error.txt\" %>")
    end
  end

  test "invalid include type" do
    assert_raise ExEEx.TemplateError, fn ->
      ExEEx.compile_string("<% include x %>")
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
  end
end
