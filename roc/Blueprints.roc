module [
    templateBricks,
    templateMeta,
    allTemplates,
    sliceByLayer,
    evaluateMatch,
]

import Catalog
import Types exposing [
    BlueprintMeta,
    BrickColor,
    BrickKind,
    MatchMetrics,
    PlacedBrick,
    Rotation,
    TemplateId,
]

makeBrick : U64, BrickKind, I32, I32, I32, Rotation, BrickColor -> PlacedBrick
makeBrick = \id, kind, x, y, z, rotation, color ->
    {
        id,
        kind,
        pos: { x, y, z },
        rotation,
        color,
    }

raceCarBricks : List PlacedBrick
raceCarBricks =
    [
        makeBrick 1 WheelAxle2x2 7 5 0 Deg0 Slate,
        makeBrick 2 WheelAxle2x2 7 9 0 Deg0 Slate,
        makeBrick 3 Plate1x2 7 7 0 Deg0 Slate,
        makeBrick 4 Plate1x2 8 7 0 Deg0 Slate,
        makeBrick 5 Plate2x6 7 5 1 Deg0 White,
        makeBrick 6 Brick1x2 7 5 2 Deg90 Yellow,
        makeBrick 7 Brick2x4 7 6 2 Deg0 Red,
        makeBrick 8 Brick1x2 7 10 2 Deg90 Red,
        makeBrick 9 Slope2x2 7 5 5 Deg0 Red,
        makeBrick 10 Cockpit2x2 7 7 5 Deg0 Cyan,
        makeBrick 11 Slope1x2 7 9 5 Deg0 Slate,
        makeBrick 12 Slope1x2 8 9 5 Deg0 Slate,
    ]

gondolaBricks : List PlacedBrick
gondolaBricks =
    [
        makeBrick 1 Plate2x4 7 4 0 Deg0 Slate,
        makeBrick 2 Plate2x6 7 8 0 Deg0 Slate,
        makeBrick 3 Slope2x2 7 4 1 Deg0 Red,
        makeBrick 4 Plate2x6 7 6 1 Deg0 White,
        makeBrick 5 Slope1x2 7 12 1 Deg0 Red,
        makeBrick 6 Slope1x2 8 12 1 Deg0 Red,
        makeBrick 7 Brick1x2 7 6 2 Deg90 Yellow,
        makeBrick 8 Cabin2x4 7 7 2 Deg0 Cyan,
        makeBrick 9 Brick1x2 7 11 2 Deg90 Yellow,
        makeBrick 10 Plate2x4 7 7 5 Deg0 White,
        makeBrick 11 Plate1x2 7 8 6 Deg90 Slate,
        makeBrick 12 Brick1x1 7 9 6 Deg0 Yellow,
        makeBrick 13 Brick1x1 8 9 6 Deg0 Yellow,
    ]

airplaneBricks : List PlacedBrick
airplaneBricks =
    [
        makeBrick 1 Plate2x6 7 4 0 Deg0 Slate,
        makeBrick 2 Plate2x4 7 10 0 Deg0 Slate,
        makeBrick 3 Slope2x2 7 4 1 Deg0 Red,
        makeBrick 4 Plate2x6 5 6 1 Deg90 White,
        makeBrick 5 Brick2x4 7 8 1 Deg0 White,
        makeBrick 6 Plate1x2 7 12 1 Deg90 White,
        makeBrick 7 Plate1x2 7 13 1 Deg90 White,
        makeBrick 8 WingLeft2x3 4 6 2 Deg90 Blue,
        makeBrick 9 WingRight2x3 9 6 2 Deg90 Blue,
        makeBrick 10 Slope2x2 7 6 2 Deg0 White,
        makeBrick 11 Plate2x4 6 12 2 Deg90 Blue,
        makeBrick 12 Brick1x2 7 12 3 Deg0 Red,
        makeBrick 13 Cockpit2x2 7 8 4 Deg0 Cyan,
        makeBrick 14 Slope1x2 7 12 6 Deg0 Red,
    ]

templateBricks : TemplateId -> List PlacedBrick
templateBricks = \templateId ->
    when templateId is
        RaceCar -> raceCarBricks
        Gondola -> gondolaBricks
        Airplane -> airplaneBricks

uniqueElevations : List PlacedBrick -> List I32
uniqueElevations = \bricks ->
    bricks
    |> List.map \b -> b.pos.z
    |> Set.fromList
    |> Set.toList
    |> List.sortAsc

templateMeta : TemplateId -> BlueprintMeta
templateMeta = \templateId ->
    bricks = templateBricks templateId
    elevations = uniqueElevations bricks
    when templateId is
        RaceCar ->
            {
                id: RaceCar,
                title: "Modular Roadster",
                subtitle: "Twin-axle chassis car with sloped hood, cockpit canopy, and split rear spoiler.",
                brickCount: List.len bricks,
                layerElevations: elevations,
            }

        Gondola ->
            {
                id: Gondola,
                title: "Venetian & Alpine Gondola",
                subtitle: "Staggered keel hull with central cabin, canopy roof, and top suspension crest.",
                brickCount: List.len bricks,
                layerElevations: elevations,
            }

        Airplane ->
            {
                id: Airplane,
                title: "Swept-Wing Skyplane",
                subtitle: "Transverse-spar fuselage with swept port/starboard wings, horizontal stabilizer, and tail fin.",
                brickCount: List.len bricks,
                layerElevations: elevations,
            }

allTemplates : List BlueprintMeta
allTemplates =
    [
        templateMeta RaceCar,
        templateMeta Gondola,
        templateMeta Airplane,
    ]

sliceByLayer : List PlacedBrick, I32 -> List PlacedBrick
sliceByLayer = \bricks, maxLayerZ ->
    List.keepIf bricks \brick -> brick.pos.z <= maxLayerZ

brickSignature : PlacedBrick -> (BrickKind, I32, I32, I32, Rotation)
brickSignature = \brick ->
    rotNorm =
        when brick.rotation is
            Deg0 | Deg180 -> Deg0
            Deg90 | Deg270 -> Deg90
    (brick.kind, brick.pos.x, brick.pos.y, brick.pos.z, rotNorm)

cellSignature : PlacedBrick -> List (I32, I32, I32)
cellSignature = \brick ->
    Catalog.occupiedCells brick
    |> List.map \c -> (c.x, c.y, c.z)

evaluateMatch : List PlacedBrick, List PlacedBrick -> MatchMetrics
evaluateMatch = \placed, target ->
    targetBrickSet = List.map target brickSignature |> Set.fromList
    placedBrickSet = List.map placed brickSignature |> Set.fromList
    matchedBricks = Set.len (Set.intersection targetBrickSet placedBrickSet)
    targetBricks = Set.len targetBrickSet

    targetCellsSet =
        target
        |> List.joinMap cellSignature
        |> Set.fromList

    placedCellsSet =
        placed
        |> List.joinMap cellSignature
        |> Set.fromList

    matchedCells = Set.len (Set.intersection targetCellsSet placedCellsSet)
    targetCells = Set.len targetCellsSet

    brickMatchPct =
        if targetBricks == 0 then
            100
        else
            (matchedBricks * 100) // targetBricks

    cellOverlapPct =
        if targetCells == 0 then
            100
        else
            (matchedCells * 100) // targetCells

    {
        matchedBricks,
        targetBricks,
        brickMatchPct,
        matchedCells,
        targetCells,
        cellOverlapPct,
    }

