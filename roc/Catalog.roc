module [
    specFor,
    allSpecs,
    rotatedDimensions,
    occupiedCells,
    studPorts,
    tubeReceptors,
]

import Types exposing [
    BrickKind,
    BrickSpec,
    GridPos,
    PlacedBrick,
    Rotation,
]

specFor : BrickKind -> BrickSpec
specFor = \kind ->
    when kind is
        Brick1x1 -> { kind: Brick1x1, width: 1, depth: 1, heightPlates: 3, category: "Bricks", label: "Brick 1x1" }
        Brick1x2 -> { kind: Brick1x2, width: 1, depth: 2, heightPlates: 3, category: "Bricks", label: "Brick 1x2" }
        Brick1x4 -> { kind: Brick1x4, width: 1, depth: 4, heightPlates: 3, category: "Bricks", label: "Brick 1x4" }
        Brick2x2 -> { kind: Brick2x2, width: 2, depth: 2, heightPlates: 3, category: "Bricks", label: "Brick 2x2" }
        Brick2x4 -> { kind: Brick2x4, width: 2, depth: 4, heightPlates: 3, category: "Bricks", label: "Brick 2x4" }
        Plate1x2 -> { kind: Plate1x2, width: 1, depth: 2, heightPlates: 1, category: "Plates", label: "Plate 1x2" }
        Plate2x4 -> { kind: Plate2x4, width: 2, depth: 4, heightPlates: 1, category: "Plates", label: "Plate 2x4" }
        Plate2x6 -> { kind: Plate2x6, width: 2, depth: 6, heightPlates: 1, category: "Plates", label: "Plate 2x6" }
        Slope1x2 -> { kind: Slope1x2, width: 1, depth: 2, heightPlates: 3, category: "Slopes", label: "Slope 1x2" }
        Slope2x2 -> { kind: Slope2x2, width: 2, depth: 2, heightPlates: 3, category: "Slopes", label: "Slope 2x2" }
        WheelAxle2x2 -> { kind: WheelAxle2x2, width: 2, depth: 2, heightPlates: 1, category: "Vehicle & Aero Parts", label: "Wheel Axle 2x2" }
        Cockpit2x2 -> { kind: Cockpit2x2, width: 2, depth: 2, heightPlates: 3, category: "Vehicle & Aero Parts", label: "Cockpit 2x2" }
        WingLeft2x3 -> { kind: WingLeft2x3, width: 2, depth: 3, heightPlates: 1, category: "Vehicle & Aero Parts", label: "Wing Left 2x3" }
        WingRight2x3 -> { kind: WingRight2x3, width: 2, depth: 3, heightPlates: 1, category: "Vehicle & Aero Parts", label: "Wing Right 2x3" }
        Cabin2x4 -> { kind: Cabin2x4, width: 2, depth: 4, heightPlates: 3, category: "Vehicle & Aero Parts", label: "Cabin 2x4" }

allSpecs : List BrickSpec
allSpecs =
    [
        specFor Brick1x1,
        specFor Brick1x2,
        specFor Brick1x4,
        specFor Brick2x2,
        specFor Brick2x4,
        specFor Plate1x2,
        specFor Plate2x4,
        specFor Plate2x6,
        specFor Slope1x2,
        specFor Slope2x2,
        specFor WheelAxle2x2,
        specFor Cockpit2x2,
        specFor WingLeft2x3,
        specFor WingRight2x3,
        specFor Cabin2x4,
    ]

rotatedDimensions : BrickKind, Rotation -> { width : I32, depth : I32, heightPlates : I32 }
rotatedDimensions = \kind, rotation ->
    spec = specFor kind
    when rotation is
        Deg0 | Deg180 ->
            { width: spec.width, depth: spec.depth, heightPlates: spec.heightPlates }

        Deg90 | Deg270 ->
            { width: spec.depth, depth: spec.width, heightPlates: spec.heightPlates }

footprintCoords : I32, I32, I32, I32 -> List (I32, I32)
footprintCoords = \baseX, baseY, width, depth ->
    List.range { start: At 0, end: Before width }
    |> List.joinMap \dx ->
        List.range { start: At 0, end: Before depth }
        |> List.map \dy -> (baseX + dx, baseY + dy)

occupiedCells : PlacedBrick -> List GridPos
occupiedCells = \brick ->
    dims = rotatedDimensions brick.kind brick.rotation
    xyPairs = footprintCoords brick.pos.x brick.pos.y dims.width dims.depth
    xyPairs
    |> List.joinMap \(cx, cy) ->
        List.range { start: At 0, end: Before dims.heightPlates }
        |> List.map \dz ->
            { x: cx, y: cy, z: brick.pos.z + dz }

studPorts : PlacedBrick -> List GridPos
studPorts = \brick ->
    dims = rotatedDimensions brick.kind brick.rotation
    topZ = brick.pos.z + dims.heightPlates
    footprintCoords brick.pos.x brick.pos.y dims.width dims.depth
    |> List.map \(cx, cy) ->
        { x: cx, y: cy, z: topZ }

tubeReceptors : PlacedBrick -> List GridPos
tubeReceptors = \brick ->
    dims = rotatedDimensions brick.kind brick.rotation
    footprintCoords brick.pos.x brick.pos.y dims.width dims.depth
    |> List.map \(cx, cy) ->
        { x: cx, y: cy, z: brick.pos.z }

