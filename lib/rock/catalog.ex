defmodule Rock.Catalog do
  @moduledoc """
  Pure specification of Lego-inspired block archetypes, color palette,
  oriented 3D footprints, top stud ports, and bottom anti-stud receptors.
  Mirrors `roc/Catalog.roc` and `roc/Types.roc`.
  """

  @specs [
    %{kind: :brick_1x1, width: 1, depth: 1, height_plates: 3, category: "Bricks", label: "Brick 1x1"},
    %{kind: :brick_1x2, width: 1, depth: 2, height_plates: 3, category: "Bricks", label: "Brick 1x2"},
    %{kind: :brick_1x4, width: 1, depth: 4, height_plates: 3, category: "Bricks", label: "Brick 1x4"},
    %{kind: :brick_2x2, width: 2, depth: 2, height_plates: 3, category: "Bricks", label: "Brick 2x2"},
    %{kind: :brick_2x4, width: 2, depth: 4, height_plates: 3, category: "Bricks", label: "Brick 2x4"},
    %{kind: :plate_1x2, width: 1, depth: 2, height_plates: 1, category: "Plates", label: "Plate 1x2"},
    %{kind: :plate_2x4, width: 2, depth: 4, height_plates: 1, category: "Plates", label: "Plate 2x4"},
    %{kind: :plate_2x6, width: 2, depth: 6, height_plates: 1, category: "Plates", label: "Plate 2x6"},
    %{kind: :slope_1x2, width: 1, depth: 2, height_plates: 3, category: "Slopes", label: "Slope 1x2"},
    %{kind: :slope_2x2, width: 2, depth: 2, height_plates: 3, category: "Slopes", label: "Slope 2x2"},
    %{kind: :wheel_axle_2x2, width: 2, depth: 2, height_plates: 1, category: "Vehicle & Aero Parts", label: "Wheel Axle 2x2"},
    %{kind: :cockpit_2x2, width: 2, depth: 2, height_plates: 3, category: "Vehicle & Aero Parts", label: "Cockpit 2x2"},
    %{kind: :wing_left_2x3, width: 2, depth: 3, height_plates: 1, category: "Vehicle & Aero Parts", label: "Wing Left 2x3"},
    %{kind: :wing_right_2x3, width: 2, depth: 3, height_plates: 1, category: "Vehicle & Aero Parts", label: "Wing Right 2x3"},
    %{kind: :cabin_2x4, width: 2, depth: 4, height_plates: 3, category: "Vehicle & Aero Parts", label: "Cabin 2x4"}
  ]

  @colors [
    %{id: :red, label: "Red", hex: "#dc2626"},
    %{id: :blue, label: "Blue", hex: "#2563eb"},
    %{id: :yellow, label: "Yellow", hex: "#eab308"},
    %{id: :green, label: "Green", hex: "#16a34a"},
    %{id: :white, label: "White", hex: "#f8fafc"},
    %{id: :slate, label: "Slate", hex: "#475569"},
    %{id: :orange, label: "Orange", hex: "#ea580c"},
    %{id: :cyan, label: "Cyan", hex: "#0891b2"}
  ]

  @spec_map Map.new(@specs, fn spec -> {spec.kind, spec} end)
  @kind_strings Map.new(@specs, fn spec -> {Atom.to_string(spec.kind), spec.kind} end)
  @color_strings Map.new(@colors, fn color -> {Atom.to_string(color.id), color.id} end)
  @valid_rotations [0, 90, 180, 270]

  @spec all_specs() :: [map()]
  def all_specs, do: @specs

  @spec all_colors() :: [map()]
  def all_colors, do: @colors

  @spec spec_for(atom()) :: map() | nil
  def spec_for(kind), do: Map.get(@spec_map, kind)

  @spec parse_kind(atom() | String.t()) :: {:ok, atom()} | :error
  def parse_kind(kind) when is_atom(kind) do
    if Map.has_key?(@spec_map, kind), do: {:ok, kind}, else: :error
  end

  def parse_kind(kind) when is_binary(kind) do
    case Map.fetch(@kind_strings, kind) do
      {:ok, atom} -> {:ok, atom}
      :error -> :error
    end
  end

  def parse_kind(_), do: :error

  @spec parse_color(atom() | String.t()) :: {:ok, atom()} | :error
  def parse_color(color) when is_atom(color) do
    if Enum.any?(@colors, &(&1.id == color)), do: {:ok, color}, else: :error
  end

  def parse_color(color) when is_binary(color) do
    case Map.fetch(@color_strings, color) do
      {:ok, atom} -> {:ok, atom}
      :error -> :error
    end
  end

  def parse_color(_), do: :error

  @spec parse_rotation(integer() | String.t()) :: {:ok, 0 | 90 | 180 | 270} | :error
  def parse_rotation(rot) when rot in @valid_rotations, do: {:ok, rot}

  def parse_rotation(rot) when is_binary(rot) do
    case Integer.parse(rot) do
      {val, ""} when val in @valid_rotations -> {:ok, val}
      _ -> :error
    end
  end

  def parse_rotation(_), do: :error

  @spec rotated_dimensions(atom(), integer()) :: %{
          width: integer(),
          depth: integer(),
          height_plates: integer()
        }
  def rotated_dimensions(kind, rotation) do
    spec = Map.fetch!(@spec_map, kind)

    case rem(rotation, 360) do
      deg when deg in [90, 270] ->
        %{width: spec.depth, depth: spec.width, height_plates: spec.height_plates}

      _ ->
        %{width: spec.width, depth: spec.depth, height_plates: spec.height_plates}
    end
  end

  @spec occupied_cells(map()) :: [{integer(), integer(), integer()}]
  def occupied_cells(%{kind: kind, pos: %{x: x, y: y, z: z}, rotation: rotation}) do
    dims = rotated_dimensions(kind, rotation)

    for dx <- 0..(dims.width - 1),
        dy <- 0..(dims.depth - 1),
        dz <- 0..(dims.height_plates - 1) do
      {x + dx, y + dy, z + dz}
    end
  end

  @spec stud_ports(map()) :: [{integer(), integer(), integer()}]
  def stud_ports(%{kind: kind, pos: %{x: x, y: y, z: z}, rotation: rotation}) do
    dims = rotated_dimensions(kind, rotation)
    top_z = z + dims.height_plates

    for dx <- 0..(dims.width - 1),
        dy <- 0..(dims.depth - 1) do
      {x + dx, y + dy, top_z}
    end
  end

  @spec tube_receptors(map()) :: [{integer(), integer(), integer()}]
  def tube_receptors(%{kind: kind, pos: %{x: x, y: y, z: z}, rotation: rotation}) do
    dims = rotated_dimensions(kind, rotation)

    for dx <- 0..(dims.width - 1),
        dy <- 0..(dims.depth - 1) do
      {x + dx, y + dy, z}
    end
  end
end

