defmodule Mix.Tasks.Rock.Server do
  @shortdoc "Starts the RocK interactive 3D studio HTTP server"
  use Mix.Task

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [port: :integer])

    if port = opts[:port] do
      Application.put_env(:rock, :port, port)
    end

    Application.put_env(:rock, :start_server, true)
    Mix.Task.run("app.start")

    actual_port = Rock.Server.port(Rock.Server)
    Mix.shell().info("RocK Studio running at http://127.0.0.1:#{actual_port}/")
    Process.sleep(:infinity)
  end
end

