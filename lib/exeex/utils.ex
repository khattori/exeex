defmodule ExEEx.Utils do
  def split_path(path), do: {Path.dirname(path), Path.basename(path)}
end
