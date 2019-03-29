defmodule ExEEx.Adapter do
  @moduledoc """
  Specifies the minimal API required from storage adapters.
  """

  @callback expand_path(filepath :: String.t, rootdir :: String.t) :: String.t
  @callback expand_path(filepath :: String.t) :: String.t
  @callback read(filepath :: String.t, rootdir :: String.t) :: {:ok, String.t} | {:error, term}
  @callback read(filepath :: String.t) :: {:ok, String.t} | {:error, term}


  defmacro __using__(_opts) do
    quote do
      @behaviour ExEEx.Adapter

      def expand_path(filepath) do
        expand_path(filepath, ".")
      end

      def read(filepath, rootdir) do
        expand_path(filepath, rootdir)
        |> read()
      end

      defoverridable ExEEx.Adapter
   end
  end
end
