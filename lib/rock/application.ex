defmodule Rock.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Rock.Studio, name: Rock.Studio}
      ] ++ server_children()

    opts = [strategy: :one_for_one, name: Rock.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp server_children do
    if Application.get_env(:rock, :start_server, true) do
      port = Application.get_env(:rock, :port, 4000)
      [{Rock.Server, name: Rock.Server, port: port, studio: Rock.Studio}]
    else
      []
    end
  end
end

