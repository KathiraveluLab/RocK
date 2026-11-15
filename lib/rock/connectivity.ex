defmodule Rock.Connectivity do
  @moduledoc """
  Directed stud-to-tube adjacency graph and structural grounding analysis.
  """

  alias Rock.Catalog

  @type edge :: %{
          lower_id: non_neg_integer(),
          upper_id: non_neg_integer(),
          port_count: pos_integer()
        }

  @spec compute_edges([map()]) :: [edge()]
  def compute_edges(bricks) do
    stud_owners =
      Enum.reduce(bricks, %{}, fn brick, acc ->
        Enum.reduce(Catalog.stud_ports(brick), acc, fn port, inner ->
          Map.put(inner, port, brick.id)
        end)
      end)

    pair_counts =
      Enum.reduce(bricks, %{}, fn upper, acc ->
        Enum.reduce(Catalog.tube_receptors(upper), acc, fn receptor, inner ->
          case Map.fetch(stud_owners, receptor) do
            {:ok, lower_id} when lower_id != upper.id ->
              Map.update(inner, {lower_id, upper.id}, 1, &(&1 + 1))

            _ ->
              inner
          end
        end)
      end)

    pair_counts
    |> Enum.map(fn {{lower_id, upper_id}, count} ->
      %{lower_id: lower_id, upper_id: upper_id, port_count: count}
    end)
    |> Enum.sort_by(fn edge -> {edge.lower_id, edge.upper_id} end)
  end

  @spec connected_components_count([map()]) :: non_neg_integer()
  def connected_components_count([]), do: 0

  def connected_components_count(bricks) do
    adj = build_adjacency(bricks)

    {_visited, count} =
      Enum.reduce(bricks, {MapSet.new(), 0}, fn brick, {visited, comp_count} ->
        if MapSet.member?(visited, brick.id) do
          {visited, comp_count}
        else
          {bfs(adj, [brick.id], visited), comp_count + 1}
        end
      end)

    count
  end

  @spec grounded?(map() | [map()]) :: boolean()
  def grounded?([]), do: true

  def grounded?(bricks) when is_list(bricks) do
    grounded = grounded_set(bricks)
    Enum.all?(bricks, &MapSet.member?(grounded, &1.id))
  end

  @spec structural_summary([map()]) :: %{
          brick_count: non_neg_integer(),
          edge_count: non_neg_integer(),
          connected_components: non_neg_integer(),
          grounded_bricks: non_neg_integer(),
          all_grounded: boolean()
        }
  def structural_summary(bricks) do
    edges = compute_edges(bricks)
    grounded = grounded_set(bricks)
    grounded_count = MapSet.size(grounded)
    brick_count = length(bricks)

    %{
      brick_count: brick_count,
      edge_count: length(edges),
      connected_components: connected_components_count(bricks),
      grounded_bricks: grounded_count,
      all_grounded: grounded_count == brick_count
    }
  end

  defp grounded_set(bricks) do
    adj = build_adjacency(bricks)

    seeds =
      bricks
      |> Enum.filter(&(&1.pos.z == 0))
      |> Enum.map(& &1.id)

    bfs(adj, seeds, MapSet.new())
  end

  defp build_adjacency(bricks) do
    edges = compute_edges(bricks)
    initial = Map.new(bricks, fn b -> {b.id, MapSet.new()} end)

    Enum.reduce(edges, initial, fn edge, acc ->
      acc
      |> Map.update!(edge.lower_id, &MapSet.put(&1, edge.upper_id))
      |> Map.update!(edge.upper_id, &MapSet.put(&1, edge.lower_id))
    end)
  end

  defp bfs(_adj, [], visited), do: visited

  defp bfs(adj, [current | rest], visited) do
    if MapSet.member?(visited, current) do
      bfs(adj, rest, visited)
    else
      next_visited = MapSet.put(visited, current)

      unseen =
        adj
        |> Map.get(current, MapSet.new())
        |> Enum.reject(&MapSet.member?(next_visited, &1))

      bfs(adj, rest ++ unseen, next_visited)
    end
  end
end

