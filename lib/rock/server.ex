defmodule Rock.Server do
  @moduledoc """
  Zero-dependency HTTP/1.1 server using OTP `:gen_tcp` to serve the RocK
  browser studio assets and JSON API endpoints.
  """

  use GenServer

  alias Rock.{Blueprints, Catalog, Studio}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec port(GenServer.server()) :: :inet.port_number()
  def port(server \\ __MODULE__) do
    GenServer.call(server, :port)
  end

  @impl true
  def init(opts) do
    requested_port = Keyword.get(opts, :port, 4000)
    studio_server = Keyword.get(opts, :studio, Rock.Studio)

    listen_opts = [
      :binary,
      packet: :raw,
      active: false,
      reuseaddr: true,
      ip: {127, 0, 0, 1}
    ]

    case :gen_tcp.listen(requested_port, listen_opts) do
      {:ok, listen_socket} ->
        {:ok, actual_port} = :inet.port(listen_socket)
        parent = self()
        spawn_link(fn -> accept_loop(listen_socket, studio_server, parent) end)
        {:ok, %{socket: listen_socket, port: actual_port, studio: studio_server}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:port, _from, state) do
    {:reply, state.port, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.socket, do: :gen_tcp.close(state.socket)
    :ok
  end

  defp accept_loop(listen_socket, studio_server, parent) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        spawn(fn -> handle_connection(client_socket, studio_server) end)
        accept_loop(listen_socket, studio_server, parent)

      {:error, :closed} ->
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  defp handle_connection(socket, studio_server) do
    case read_http_request(socket, "") do
      {:ok, method, path, body} ->
        {status, content_type, resp_body} = route(method, path, body, studio_server)
        write_http_response(socket, status, content_type, resp_body)

      :error ->
        write_http_response(socket, 400, "text/plain; charset=utf-8", "Bad Request")
    end

    :gen_tcp.close(socket)
  end

  @doc """
  Pure HTTP request dispatcher returning `{status_code, content_type, body}`.
  """
  @spec route(String.t(), String.t(), String.t(), GenServer.server()) ::
          {pos_integer(), String.t(), binary()}
  def route(method, raw_path, body, studio_server \\ Rock.Studio) do
    path = raw_path |> String.split("?", parts: 2) |> hd()

    case {method, path} do
      {"GET", "/"} ->
        serve_static("index.html", "text/html; charset=utf-8")

      {"GET", "/index.html"} ->
        serve_static("index.html", "text/html; charset=utf-8")

      {"GET", "/studio.css"} ->
        serve_static("studio.css", "text/css; charset=utf-8")

      {"GET", "/studio.js"} ->
        serve_static("studio.js", "application/javascript; charset=utf-8")

      {"GET", "/api/state"} ->
        json_response(200, Studio.get_state(studio_server))

      {"GET", "/api/catalog"} ->
        json_response(200, %{
          specs: Catalog.all_specs(),
          colors: Catalog.all_colors()
        })

      {"GET", "/api/templates"} ->
        json_response(200, %{templates: Blueprints.all_templates()})

      {"POST", "/api/action"} ->
        case JSON.decode(body) do
          {:ok, params} when is_map(params) ->
            payload = Studio.dispatch(studio_server, params)
            json_response(200, payload)

          _ ->
            json_response(400, %{error: "Invalid JSON payload"})
        end

      _ ->
        json_response(404, %{error: "Not Found"})
    end
  end

  defp serve_static(filename, content_type) do
    static_dir = Path.join(:code.priv_dir(:rock), "static")
    file_path = Path.join(static_dir, filename)

    case File.read(file_path) do
      {:ok, content} -> {200, content_type, content}
      {:error, _} -> {404, "text/plain; charset=utf-8", "Static file not found"}
    end
  end

  defp json_response(status, data) do
    {status, "application/json; charset=utf-8", JSON.encode!(data)}
  end

  defp read_http_request(socket, buffer) do
    case :binary.match(buffer, "\r\n\r\n") do
      {header_end, 4} ->
        header_part = binary_part(buffer, 0, header_end)
        rest = binary_part(buffer, header_end + 4, byte_size(buffer) - header_end - 4)

        with [request_line | header_lines] <- String.split(header_part, "\r\n"),
             [method, path | _] <- String.split(request_line, " ") do
          content_length = parse_content_length(header_lines)
          read_body(socket, rest, content_length, method, path)
        else
          _ -> :error
        end

      :nomatch ->
        case :gen_tcp.recv(socket, 0, 5_000) do
          {:ok, chunk} -> read_http_request(socket, buffer <> chunk)
          {:error, _} -> :error
        end
    end
  end

  defp read_body(_socket, rest, 0, method, path), do: {:ok, method, path, rest}

  defp read_body(socket, rest, content_length, method, path) do
    if byte_size(rest) >= content_length do
      {:ok, method, path, binary_part(rest, 0, content_length)}
    else
      case :gen_tcp.recv(socket, 0, 5_000) do
        {:ok, chunk} -> read_body(socket, rest <> chunk, content_length, method, path)
        {:error, _} -> :error
      end
    end
  end

  defp parse_content_length(header_lines) do
    Enum.find_value(header_lines, 0, fn line ->
      case String.split(line, ":", parts: 2) do
        [key, val] ->
          if String.downcase(String.trim(key)) == "content-length" do
            case Integer.parse(String.trim(val)) do
              {len, ""} when len >= 0 -> len
              _ -> 0
            end
          end

        _ ->
          nil
      end
    end)
  end

  defp write_http_response(socket, status, content_type, body) do
    reason =
      case status do
        200 -> "OK"
        400 -> "Bad Request"
        404 -> "Not Found"
        _ -> "OK"
      end

    headers =
      "HTTP/1.1 #{status} #{reason}\r\n" <>
        "Content-Type: #{content_type}\r\n" <>
        "Content-Length: #{byte_size(body)}\r\n" <>
        "Connection: close\r\n" <>
        "Cache-Control: no-store\r\n\r\n"

    :gen_tcp.send(socket, headers <> body)
  end
end
