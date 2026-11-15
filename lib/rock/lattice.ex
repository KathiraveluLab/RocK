defmodule Rock.Lattice do
  @moduledoc """
  Discrete 3D stud-and-plate spatial lattice (16x16 studs by 36 plates high)
  handling bounds checks, collision rejection, and drag-and-drop elevation snapping.
  """

  alias Rock.Catalog

  @baseplate_size 16
  @max_elevation_plates 36

  @type cell_key :: {integer(), integer(), integer()}
  @type t :: %{optional(cell_key()) => non_neg_integer()}

  @spec baseplate_size() :: integer()
  def baseplate_size, do: @baseplate_size

  @spec max_elevation_plates() :: integer()
  def max_elevation_plates, do: @max_elevation_plates

  @spec empty() :: t()
  def empty, do: %{}

  @spec within_bounds?(map()) :: boolean()
  def within_bounds?(%{kind: kind, pos: %{x: x, y: y, z: z}, rotation: rotation}) do
    dims = Catalog.rotated_dimensions(kind, rotation)

    x >= 0 and y >= 0 and z >= 0 and
      x + dims.width <= @baseplate_size and
      y + dims.depth <= @baseplate_size and
      z + dims.height_plates <= @max_elevation_plates
  end

  @spec can_place?(t(), map()) :: boolean()
  def can_place?(lattice, brick) do
    within_bounds?(brick) and
      Enum.all?(Catalog.occupied_cells(brick), fn cell ->
        not Map.has_key?(lattice, cell)
      end)
  end

  @spec insert_brick(t(), map()) :: {:ok, t()} | {:error, :out_of_bounds | :collision}
  def insert_brick(lattice, brick) do
    cond do
      not within_bounds?(brick) ->
        {:error, :out_of_bounds}

      not can_place?(lattice, brick) ->
        {:error, :collision}

      true ->
        updated =
          Enum.reduce(Catalog.occupied_cells(brick), lattice, fn cell, acc ->
            Map.put(acc, cell, brick.id)
          end)

        {:ok, updated}
    end
  end

  @spec from_bricks([map()]) :: {:ok, t()} | {:error, :out_of_bounds | :collision}
  def from_bricks(bricks) do
    Enum.reduce_while(bricks, {:ok, empty()}, fn brick, {:ok, acc} ->
      case insert_brick(acc, brick) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec remove_brick(t(), non_neg_integer()) :: t()
  def remove_brick(lattice, brick_id) do
    Map.reject(lattice, fn {_cell, owner_id} -> owner_id == brick_id end)
  end

  @spec snap_elevation(t(), atom(), integer(), integer(), integer()) :: integer()
  def snap_elevation(lattice, kind, rotation, x, y) do
    dims = Catalog.rotated_dimensions(kind, rotation)
    min_x = x
    max_x = x + dims.width
    min_y = y
    max_y = y + dims.depth

    Enum.reduce(lattice, 0, fn {{cx, cy, cz}, _owner_id}, highest_z ->
      if cx >= min_x and cx < max_x and cy >= min_y and cy < max_y do
        max(highest_z, cz + 1)
      else
        highest_z
      end
    end)
  end
end

