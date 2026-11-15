defmodule Rock.Studio do
  @moduledoc """
  Stateful studio workbench GenServer and pure state transition reducer
  coordinating drag-and-drop placement, template slicing, undo/redo, and telemetry.
  """

  use GenServer

  alias Rock.{Blueprints, Catalog, Connectivity, Lattice}

  @type state :: %{
          bricks: [map()],
          next_id: pos_integer(),
          selected_template: atom(),
          selected_kind: atom(),
          selected_rotation: integer(),
          selected_color: atom(),
          guide_visible: boolean(),
          layer_limit: integer() | :all,
          undo_stack: [[map()]],
          redo_stack: [[map()]],
          last_error: String.t() | nil
        }

  @spec new(atom()) :: state()
  def new(template_id \\ :race_car) do
    %{
      bricks: [],
      next_id: 1,
      selected_template: template_id,
      selected_kind: :brick_2x4,
      selected_rotation: 0,
      selected_color: :red,
      guide_visible: true,
      layer_limit: :all,
      undo_stack: [],
      redo_stack: [],
      last_error: nil
    }
  end

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    template_id = Keyword.get(opts, :template, :race_car)
    GenServer.start_link(__MODULE__, template_id, name: name)
  end

  def get_state(server \\ __MODULE__) do
    GenServer.call(server, :get_state)
  end

  def dispatch(server \\ __MODULE__, action) do
    GenServer.call(server, {:action, action})
  end

  @impl true
  def init(template_id) do
    {:ok, new(template_id)}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, to_payload(state), state}
  end

  @impl true
  def handle_call({:action, action}, _from, state) do
    next_state = apply_action(state, action)
    {:reply, to_payload(next_state), next_state}
  end

  @spec apply_action(state(), map()) :: state()
  def apply_action(state, %{"type" => type} = params) do
    atom_action =
      params
      |> Map.delete("type")
      |> Map.put(:type, type)

    apply_action(state, atom_action)
  end

  def apply_action(state, %{type: "place_at"} = params) do
    with {:ok, kind} <- Catalog.parse_kind(params["kind"] || params[:kind] || state.selected_kind),
         {:ok, rot} <-
           Catalog.parse_rotation(params["rotation"] || params[:rotation] || state.selected_rotation),
         {:ok, color} <-
           Catalog.parse_color(params["color"] || params[:color] || state.selected_color),
         {:ok, x} <- parse_int(params["x"] || params[:x]),
         {:ok, y} <- parse_int(params["y"] || params[:y]),
         {:ok, lattice} <- Lattice.from_bricks(state.bricks) do
      z =
        case parse_int(params["z"] || params[:z]) do
          {:ok, explicit_z} -> explicit_z
          :error -> Lattice.snap_elevation(lattice, kind, rot, x, y)
        end

      candidate = %{
        id: state.next_id,
        kind: kind,
        pos: %{x: x, y: y, z: z},
        rotation: rot,
        color: color
      }

      case Lattice.insert_brick(lattice, candidate) do
        {:ok, _updated_lattice} ->
          %{
            state
            | bricks: state.bricks ++ [candidate],
              next_id: state.next_id + 1,
              undo_stack: state.undo_stack ++ [state.bricks],
              redo_stack: [],
              last_error: nil
          }

        {:error, :out_of_bounds} ->
          %{state | last_error: "Placement falls outside the 16x16x36 build volume."}

        {:error, :collision} ->
          %{state | last_error: "Placement collides with an existing block."}
      end
    else
      _ -> %{state | last_error: "Invalid placement parameters."}
    end
  end

  def apply_action(state, %{type: "remove_brick"} = params) do
    case parse_int(params["id"] || params[:id]) do
      {:ok, target_id} ->
        filtered = Enum.reject(state.bricks, &(&1.id == target_id))

        if length(filtered) == length(state.bricks) do
          %{state | last_error: "Block id not found."}
        else
          %{
            state
            | bricks: filtered,
              undo_stack: state.undo_stack ++ [state.bricks],
              redo_stack: [],
              last_error: nil
          }
        end

      :error ->
        %{state | last_error: "Invalid block id."}
    end
  end

  def apply_action(state, %{type: "select_template"} = params) do
    case Blueprints.parse_template_id(params["template_id"] || params[:template_id]) do
      {:ok, template_id} ->
        %{state | selected_template: template_id, layer_limit: :all, last_error: nil}

      :error ->
        %{state | last_error: "Unknown template identifier."}
    end
  end

  def apply_action(state, %{type: "load_template"} = params) do
    target_template = params["template_id"] || params[:template_id] || state.selected_template

    case Blueprints.parse_template_id(target_template) do
      {:ok, template_id} ->
        template_bricks = Blueprints.template_bricks(template_id)
        max_id = Enum.reduce(template_bricks, 0, fn b, acc -> max(b.id, acc) end)

        %{
          state
          | bricks: template_bricks,
            next_id: max_id + 1,
            selected_template: template_id,
            layer_limit: :all,
            undo_stack: state.undo_stack ++ [state.bricks],
            redo_stack: [],
            last_error: nil
        }

      :error ->
        %{state | last_error: "Unknown template identifier."}
    end
  end

  def apply_action(state, %{type: "set_layer_limit"} = params) do
    raw = params["layer_limit"] || params[:layer_limit]

    cond do
      raw in ["all", :all, nil] ->
        %{state | layer_limit: :all, last_error: nil}

      true ->
        case parse_int(raw) do
          {:ok, z} when z >= 0 ->
            %{state | layer_limit: z, last_error: nil}

          _ ->
            %{state | last_error: "Invalid layer limit."}
        end
    end
  end

  def apply_action(state, %{type: "toggle_guide"} = params) do
    visible =
      case params["visible"] do
        val when is_boolean(val) -> val
        _ ->
          case params[:visible] do
            val when is_boolean(val) -> val
            _ -> not state.guide_visible
          end
      end

    %{state | guide_visible: visible, last_error: nil}
  end

  def apply_action(state, %{type: "select_kind"} = params) do
    case Catalog.parse_kind(params["kind"] || params[:kind]) do
      {:ok, kind} -> %{state | selected_kind: kind, last_error: nil}
      :error -> %{state | last_error: "Unknown block kind."}
    end
  end

  def apply_action(state, %{type: "select_rotation"} = params) do
    case Catalog.parse_rotation(params["rotation"] || params[:rotation]) do
      {:ok, rot} -> %{state | selected_rotation: rot, last_error: nil}
      :error -> %{state | last_error: "Invalid rotation."}
    end
  end

  def apply_action(state, %{type: "rotate_cw"}) do
    next_rot = rem(state.selected_rotation + 90, 360)
    %{state | selected_rotation: next_rot, last_error: nil}
  end

  def apply_action(state, %{type: "select_color"} = params) do
    case Catalog.parse_color(params["color"] || params[:color]) do
      {:ok, color} -> %{state | selected_color: color, last_error: nil}
      :error -> %{state | last_error: "Unknown color."}
    end
  end

  def apply_action(state, %{type: "undo"}) do
    case List.pop_at(state.undo_stack, -1) do
      {nil, _} ->
        %{state | last_error: nil}

      {prev_bricks, remaining_undo} ->
        %{
          state
          | bricks: prev_bricks,
            undo_stack: remaining_undo,
            redo_stack: state.redo_stack ++ [state.bricks],
            last_error: nil
        }
    end
  end

  def apply_action(state, %{type: "redo"}) do
    case List.pop_at(state.redo_stack, -1) do
      {nil, _} ->
        %{state | last_error: nil}

      {next_bricks, remaining_redo} ->
        %{
          state
          | bricks: next_bricks,
            undo_stack: state.undo_stack ++ [state.bricks],
            redo_stack: remaining_redo,
            last_error: nil
        }
    end
  end

  def apply_action(state, %{type: "clear"}) do
    if state.bricks == [] do
      %{state | last_error: nil}
    else
      %{
        state
        | bricks: [],
          undo_stack: state.undo_stack ++ [state.bricks],
          redo_stack: [],
          last_error: nil
      }
    end
  end

  def apply_action(state, _unknown) do
    %{state | last_error: "Unsupported action."}
  end

  @spec to_payload(state()) :: map()
  def to_payload(state) do
    target_bricks = Blueprints.template_bricks(state.selected_template)
    guide_bricks = Blueprints.slice_by_layer(target_bricks, state.layer_limit)
    meta = Blueprints.template_meta(state.selected_template)
    match_metrics = Blueprints.evaluate_match(state.bricks, target_bricks)
    structural = Connectivity.structural_summary(state.bricks)
    bom = Blueprints.bill_of_materials(guide_bricks)

    %{
      bricks: state.bricks,
      next_id: state.next_id,
      selected_template: state.selected_template,
      selected_kind: state.selected_kind,
      selected_rotation: state.selected_rotation,
      selected_color: state.selected_color,
      guide_visible: state.guide_visible,
      layer_limit: state.layer_limit,
      can_undo: state.undo_stack != [],
      can_redo: state.redo_stack != [],
      last_error: state.last_error,
      template_meta: meta,
      guide_bricks: guide_bricks,
      template_bricks: target_bricks,
      bom: bom,
      match_metrics: match_metrics,
      structural: structural
    }
  end

  defp parse_int(val) when is_integer(val), do: {:ok, val}

  defp parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {parsed, ""} -> {:ok, parsed}
      _ -> :error
    end
  end

  defp parse_int(_), do: :error
end
