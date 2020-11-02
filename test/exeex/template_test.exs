defmodule ExEEx.TemplateTest do
  alias ExEEx.Template
  use ExUnit.Case

  doctest ExEEx.Template

  test "inspect template" do
    assert inspect(%Template{code: nil, path: "test", name: :nofile}) == "#Template<test:nofile>"
    assert inspect(%Template{code: nil, path: "test", name: "file"}) == "#Template<test/file>"
  end
end
