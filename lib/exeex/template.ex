defmodule ExEEx.Template do
  @enforce_keys [:code, :path, :name]
  defstruct code: nil, path: "", name: ""
  @type t :: %__MODULE__{code: Macro.t, path: String.t, name: String.t}

  defimpl Inspect do
    def inspect(%{path: path, name: :nofile}, _opts) do
      "#Template<#{path}:nofile>"
    end
    def inspect(%{path: path, name: name}, _opts) do
      "#Template<#{path}/#{name}>"
    end
  end
end
