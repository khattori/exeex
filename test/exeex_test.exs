defmodule ExEExTest do
  use ExUnit.Case
  doctest ExEEx

  test "greets the world" do
    assert ExEEx.hello() == :world
  end
end
