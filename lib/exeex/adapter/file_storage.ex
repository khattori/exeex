defmodule ExEEx.Adapter.FileStorage do
  use ExEEx.Adapter

  def expand_path(path, relative_to), do: Path.expand(path, relative_to)
  def read(filepath), do: File.read!(filepath)
end
