defmodule RockTest do
  use ExUnit.Case, async: false

  alias Rock.{Blueprints, Catalog, Connectivity, Lattice, Server, Studio}

  describe "Catalog" do
    test "exposes 15 block archetypes and 8 colors" do
      specs = Catalog.all_specs()
      colors = Catalog.all_colors()

      assert length(specs) == 15
      assert length(colors) == 8
      assert Catalog.spec_for(:brick_2x4) == %{
               kind: :brick_2x4,
               width: 2,
               depth: 4,
               height_plates: 3,
               category: "Bricks",
               label: "Brick 2x4"
             }
    end

    test "rotations swap width and depth at 90 and 270 degrees" do
      assert Catalog.rotated_dimensions(:plate_2x6, 0) == %{width: 2, depth: 6, height_plates: 1}
      assert Catalog.rotated_dimensions(:plate_2x6, 90) == %{width: 6, depth: 2, height_plates: 1}
      assert Catalog.rotated_dimensions(:plate_2x6, 180) == %{width: 2, depth: 6, height_plates: 1}
      assert Catalog.rotated_dimensions(:plate_2x6, 270) == %{width: 6, depth: 2, height_plates: 1}
    end

    test "computes occupied cells, stud ports, and tube receptors consistently" do
      brick = %{id: 1, kind: :brick_1x2, pos: %{x: 3, y: 4, z: 2}, rotation: 0, color: :red}
      cells = Catalog.occupied_cells(brick)
      studs = Catalog.stud_ports(brick)
      tubes = Catalog.tube_receptors(brick)

      assert length(cells) == 6
      assert {3, 4, 2} in cells
      assert {3, 5, 4} in cells
      assert Enum.sort(studs) == [{3, 4, 5}, {3, 5, 5}]
      assert Enum.sort(tubes) == [{3, 4, 2}, {3, 5, 2}]
    end
  end

  describe "Lattice" do
    test "enforces build volume bounds and prevents cell collisions" do
      b1 = %{id: 1, kind: :brick_2x4, pos: %{x: 0, y: 0, z: 0}, rotation: 0, color: :red}
      b_overlap = %{id: 2, kind: :brick_2x2, pos: %{x: 1, y: 2, z: 1}, rotation: 0, color: :blue}
      b_oob = %{id: 3, kind: :plate_2x6, pos: %{x: 15, y: 12, z: 0}, rotation: 0, color: :white}

      assert {:ok, lattice} = Lattice.insert_brick(Lattice.empty(), b1)
      assert {:error, :collision} = Lattice.insert_brick(lattice, b_overlap)
      assert {:error, :out_of_bounds} = Lattice.insert_brick(lattice, b_oob)
      assert {:ok, %{} = _} = {:ok, Lattice.remove_brick(lattice, 1)}
      assert Lattice.remove_brick(lattice, 1) == Lattice.empty()
    end

    test "snaps drag-and-drop elevation above occupied footprint cells" do
      axle1 = %{id: 1, kind: :wheel_axle_2x2, pos: %{x: 7, y: 5, z: 0}, rotation: 0, color: :slate}
      axle2 = %{id: 2, kind: :wheel_axle_2x2, pos: %{x: 7, y: 9, z: 0}, rotation: 0, color: :slate}
      {:ok, lattice} = Lattice.from_bricks([axle1, axle2])

      assert Lattice.snap_elevation(lattice, :plate_2x6, 0, 7, 5) == 1
      assert Lattice.snap_elevation(lattice, :brick_2x2, 0, 0, 0) == 0

      plate = %{id: 3, kind: :plate_2x6, pos: %{x: 7, y: 5, z: 1}, rotation: 0, color: :white}
      {:ok, lattice2} = Lattice.insert_brick(lattice, plate)
      assert Lattice.snap_elevation(lattice2, :brick_2x4, 0, 7, 6) == 2
    end
  end

  describe "Connectivity and Blueprints" do
    test "all three starter templates are collision-free, single-component, and grounded" do
      expected_counts = %{race_car: 12, gondola: 13, airplane: 14}

      for {template_id, expected_count} <- expected_counts do
        bricks = Blueprints.template_bricks(template_id)
        assert length(bricks) == expected_count
        assert {:ok, _lattice} = Lattice.from_bricks(bricks)

        summary = Connectivity.structural_summary(bricks)
        assert summary.brick_count == expected_count
        assert summary.connected_components == 1
        assert summary.all_grounded
        assert summary.grounded_bricks == expected_count
        assert summary.edge_count >= expected_count - 1
      end
    end

    test "slices blueprints by plate elevation and computes 100% parity when rebuilt" do
      car_bricks = Blueprints.template_bricks(:race_car)
      layer0 = Blueprints.slice_by_layer(car_bricks, 0)
      layer1 = Blueprints.slice_by_layer(car_bricks, 1)

      assert length(layer0) == 4
      assert length(layer1) == 5

      metrics = Blueprints.evaluate_match(car_bricks, car_bricks)
      assert metrics.matched_bricks == 12
      assert metrics.brick_match_pct == 100
      assert metrics.cell_overlap_pct == 100
    end
  end

  describe "Studio GenServer & HTTP Server" do
    test "supports drag-and-drop placement, undo/redo, template loading, and layer filtering" do
      studio = start_supervised!({Studio, name: nil, template: :race_car})

      initial = Studio.get_state(studio)
      assert initial.bricks == []
      assert initial.selected_template == :race_car

      after_place1 =
        Studio.dispatch(studio, %{
          "type" => "place_at",
          "kind" => "wheel_axle_2x2",
          "x" => 7,
          "y" => 5,
          "rotation" => 0,
          "color" => "slate"
        })

      assert length(after_place1.bricks) == 1
      assert hd(after_place1.bricks).pos.z == 0
      assert after_place1.can_undo

      after_place2 =
        Studio.dispatch(studio, %{
          "type" => "place_at",
          "kind" => "plate_2x6",
          "x" => 7,
          "y" => 5,
          "rotation" => 0,
          "color" => "white"
        })

      assert length(after_place2.bricks) == 2
      assert List.last(after_place2.bricks).pos.z == 1

      after_undo = Studio.dispatch(studio, %{"type" => "undo"})
      assert length(after_undo.bricks) == 1
      assert after_undo.can_redo

      after_redo = Studio.dispatch(studio, %{"type" => "redo"})
      assert length(after_redo.bricks) == 2

      after_load =
        Studio.dispatch(studio, %{"type" => "load_template", "template_id" => "airplane"})

      assert after_load.selected_template == :airplane
      assert length(after_load.bricks) == 14
      assert after_load.match_metrics.brick_match_pct == 100
      assert after_load.match_metrics.cell_overlap_pct == 100
      assert after_load.structural.connected_components == 1
      assert after_load.structural.all_grounded

      after_slice = Studio.dispatch(studio, %{"type" => "set_layer_limit", "layer_limit" => 1})
      assert Enum.all?(after_slice.guide_bricks, &(&1.pos.z <= 1))

      after_remove = Studio.dispatch(studio, %{"type" => "remove_brick", "id" => 14})
      assert length(after_remove.bricks) == 13
    end

    test "routes static assets and JSON endpoints cleanly" do
      studio = start_supervised!({Studio, name: nil, template: :gondola})

      {status_html, ct_html, body_html} = Server.route("GET", "/", "", studio)
      assert status_html == 200
      assert ct_html =~ "text/html"
      assert body_html =~ "RocK Studio"

      {status_cat, ct_cat, body_cat} = Server.route("GET", "/api/catalog", "", studio)
      assert status_cat == 200
      assert ct_cat =~ "application/json"
      {:ok, cat_json} = JSON.decode(body_cat)
      assert length(cat_json["specs"]) == 15
      assert length(cat_json["colors"]) == 8

      {status_tpl, _ct_tpl, body_tpl} = Server.route("GET", "/api/templates", "", studio)
      assert status_tpl == 200
      {:ok, tpl_json} = JSON.decode(body_tpl)
      assert length(tpl_json["templates"]) == 3

      action_body = JSON.encode!(%{"type" => "load_template", "template_id" => "gondola"})
      {status_act, _ct_act, body_act} = Server.route("POST", "/api/action", action_body, studio)
      assert status_act == 200
      {:ok, act_json} = JSON.decode(body_act)
      assert act_json["match_metrics"]["brick_match_pct"] == 100
      assert act_json["structural"]["all_grounded"] == true

      {status_css, ct_css, body_css} = Server.route("GET", "/studio.css", "", studio)
      assert status_css == 200
      assert ct_css =~ "text/css"
      assert body_css =~ ".studio-shell"

      {status_js, ct_js, body_js} = Server.route("GET", "/studio.js", "", studio)
      assert status_js == 200
      assert ct_js =~ "application/javascript"
      assert body_js =~ "renderWorkbench"

      {status_bad, _ct_bad, _body_bad} = Server.route("POST", "/api/action", "{invalid", studio)
      assert status_bad == 400

      {status_404, _ct_404, _body_404} = Server.route("GET", "/unknown", "", studio)
      assert status_404 == 404
    end
  end
end
