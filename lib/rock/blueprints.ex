defmodule Rock.Blueprints do
  @moduledoc """
  Canonical starter design templates (Car, Gondola, Airplane), layer slicing,
  bill-of-materials aggregation, and blueprint homomorphism scoring.
  """

  alias Rock.Catalog

  @template_ids [:race_car, :gondola, :airplane]

  defp brick(id, kind, x, y, z, rotation, color) do
    %{
      id: id,
      kind: kind,
      pos: %{x: x, y: y, z: z},
      rotation: rotation,
      color: color
    }
  end

  @spec parse_template_id(atom() | String.t()) :: {:ok, atom()} | :error
  def parse_template_id(id) when id in @template_ids, do: {:ok, id}

  def parse_template_id(id) when is_binary(id) do
    case id do
      "race_car" -> {:ok, :race_car}
      "gondola" -> {:ok, :gondola}
      "airplane" -> {:ok, :airplane}
      _ -> :error
    end
  end

  def parse_template_id(_), do: :error

  @spec template_bricks(atom()) :: [map()]
  def template_bricks(:race_car) do
    [
      brick(1, :wheel_axle_2x2, 7, 5, 0, 0, :slate),
      brick(2, :wheel_axle_2x2, 7, 9, 0, 0, :slate),
      brick(3, :plate_1x2, 7, 7, 0, 0, :slate),
      brick(4, :plate_1x2, 8, 7, 0, 0, :slate),
      brick(5, :plate_2x6, 7, 5, 1, 0, :white),
      brick(6, :brick_1x2, 7, 5, 2, 90, :yellow),
      brick(7, :brick_2x4, 7, 6, 2, 0, :red),
      brick(8, :brick_1x2, 7, 10, 2, 90, :red),
      brick(9, :slope_2x2, 7, 5, 5, 0, :red),
      brick(10, :cockpit_2x2, 7, 7, 5, 0, :cyan),
      brick(11, :slope_1x2, 7, 9, 5, 0, :slate),
      brick(12, :slope_1x2, 8, 9, 5, 0, :slate)
    ]
  end

  def template_bricks(:gondola) do
    [
      brick(1, :plate_2x4, 7, 4, 0, 0, :slate),
      brick(2, :plate_2x6, 7, 8, 0, 0, :slate),
      brick(3, :slope_2x2, 7, 4, 1, 0, :red),
      brick(4, :plate_2x6, 7, 6, 1, 0, :white),
      brick(5, :slope_1x2, 7, 12, 1, 0, :red),
      brick(6, :slope_1x2, 8, 12, 1, 0, :red),
      brick(7, :brick_1x2, 7, 6, 2, 90, :yellow),
      brick(8, :cabin_2x4, 7, 7, 2, 0, :cyan),
      brick(9, :brick_1x2, 7, 11, 2, 90, :yellow),
      brick(10, :plate_2x4, 7, 7, 5, 0, :white),
      brick(11, :plate_1x2, 7, 8, 6, 90, :slate),
      brick(12, :brick_1x1, 7, 9, 6, 0, :yellow),
      brick(13, :brick_1x1, 8, 9, 6, 0, :yellow)
    ]
  end

  def template_bricks(:airplane) do
    [
      brick(1, :plate_2x6, 7, 4, 0, 0, :slate),
      brick(2, :plate_2x4, 7, 10, 0, 0, :slate),
      brick(3, :slope_2x2, 7, 4, 1, 0, :red),
      brick(4, :plate_2x6, 5, 6, 1, 90, :white),
      brick(5, :brick_2x4, 7, 8, 1, 0, :white),
      brick(6, :plate_1x2, 7, 12, 1, 90, :white),
      brick(7, :plate_1x2, 7, 13, 1, 90, :white),
      brick(8, :wing_left_2x3, 4, 6, 2, 90, :blue),
      brick(9, :wing_right_2x3, 9, 6, 2, 90, :blue),
      brick(10, :slope_2x2, 7, 6, 2, 0, :white),
      brick(11, :plate_2x4, 6, 12, 2, 90, :blue),
      brick(12, :brick_1x2, 7, 12, 3, 0, :red),
      brick(13, :cockpit_2x2, 7, 8, 4, 0, :cyan),
      brick(14, :slope_1x2, 7, 12, 6, 0, :red)
    ]
  end

  @spec template_meta(atom()) :: map()
  def template_meta(template_id) when template_id in @template_ids do
    bricks = template_bricks(template_id)

    elevations =
      bricks
      |> Enum.map(& &1.pos.z)
      |> Enum.uniq()
      |> Enum.sort()

    {title, subtitle} =
      case template_id do
        :race_car ->
          {"Modular Roadster",
           "Twin-axle chassis car with sloped hood, cockpit canopy, and split rear spoiler."}

        :gondola ->
          {"Venetian & Alpine Gondola",
           "Staggered keel hull with central cabin, canopy roof, and top suspension crest."}

        :airplane ->
          {"Swept-Wing Skyplane",
           "Transverse-spar fuselage with swept port/starboard wings, horizontal stabilizer, and tail fin."}
      end

    %{
      id: template_id,
      title: title,
      subtitle: subtitle,
      brick_count: length(bricks),
      layer_elevations: elevations
    }
  end

  @spec all_templates() :: [map()]
  def all_templates do
    Enum.map(@template_ids, fn id ->
      %{
        meta: template_meta(id),
        bricks: template_bricks(id),
        bom: bill_of_materials(template_bricks(id))
      }
    end)
  end

  @spec slice_by_layer([map()], integer() | :all) :: [map()]
  def slice_by_layer(bricks, :all), do: bricks

  def slice_by_layer(bricks, max_layer_z) when is_integer(max_layer_z) do
    Enum.filter(bricks, fn b -> b.pos.z <= max_layer_z end)
  end

  @spec bill_of_materials([map()]) :: [map()]
  def bill_of_materials(bricks) do
    bricks
    |> Enum.group_by(fn b -> {b.kind, b.color} end)
    |> Enum.map(fn {{kind, color}, group} ->
      spec = Catalog.spec_for(kind)

      %{
        kind: kind,
        label: spec.label,
        color: color,
        count: length(group)
      }
    end)
    |> Enum.sort_by(fn item -> {-item.count, item.label, Atom.to_string(item.color)} end)
  end

  @spec evaluate_match([map()], [map()]) :: %{
          matched_bricks: non_neg_integer(),
          target_bricks: non_neg_integer(),
          brick_match_pct: non_neg_integer(),
          matched_cells: non_neg_integer(),
          target_cells: non_neg_integer(),
          cell_overlap_pct: non_neg_integer()
        }
  def evaluate_match(placed, target) do
    placed_sigs = MapSet.new(placed, &brick_signature/1)
    target_sigs = MapSet.new(target, &brick_signature/1)

    matched_bricks = MapSet.size(MapSet.intersection(placed_sigs, target_sigs))
    target_bricks = MapSet.size(target_sigs)

    placed_cells =
      placed
      |> Enum.flat_map(&Catalog.occupied_cells/1)
      |> MapSet.new()

    target_cells =
      target
      |> Enum.flat_map(&Catalog.occupied_cells/1)
      |> MapSet.new()

    matched_cells = MapSet.size(MapSet.intersection(placed_cells, target_cells))
    total_target_cells = MapSet.size(target_cells)

    brick_match_pct =
      if target_bricks == 0, do: 100, else: div(matched_bricks * 100, target_bricks)

    cell_overlap_pct =
      if total_target_cells == 0, do: 100, else: div(matched_cells * 100, total_target_cells)

    %{
      matched_bricks: matched_bricks,
      target_bricks: target_bricks,
      brick_match_pct: brick_match_pct,
      matched_cells: matched_cells,
      target_cells: total_target_cells,
      cell_overlap_pct: cell_overlap_pct
    }
  end

  defp brick_signature(brick) do
    rot_norm = if brick.rotation in [90, 270], do: 90, else: 0
    {brick.kind, brick.pos.x, brick.pos.y, brick.pos.z, rot_norm}
  end
end
