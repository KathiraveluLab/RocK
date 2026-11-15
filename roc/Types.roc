module [
    GridPos,
    Rotation,
    BrickKind,
    BrickColor,
    BrickSpec,
    PlacedBrick,
    TemplateId,
    BlueprintMeta,
    MatchMetrics,
    BuildAction,
    StudioModel,
]

GridPos : {
    x : I32,
    y : I32,
    z : I32,
}

Rotation : [
    Deg0,
    Deg90,
    Deg180,
    Deg270,
]

BrickKind : [
    Brick1x1,
    Brick1x2,
    Brick1x4,
    Brick2x2,
    Brick2x4,
    Plate1x2,
    Plate2x4,
    Plate2x6,
    Slope1x2,
    Slope2x2,
    WheelAxle2x2,
    Cockpit2x2,
    WingLeft2x3,
    WingRight2x3,
    Cabin2x4,
]

BrickColor : [
    Red,
    Blue,
    Yellow,
    Green,
    White,
    Slate,
    Orange,
    Cyan,
]

BrickSpec : {
    kind : BrickKind,
    width : I32,
    depth : I32,
    heightPlates : I32,
    category : Str,
    label : Str,
}

PlacedBrick : {
    id : U64,
    kind : BrickKind,
    pos : GridPos,
    rotation : Rotation,
    color : BrickColor,
}

TemplateId : [
    RaceCar,
    Gondola,
    Airplane,
]

BlueprintMeta : {
    id : TemplateId,
    title : Str,
    subtitle : Str,
    brickCount : U64,
    layerElevations : List I32,
}

MatchMetrics : {
    matchedBricks : U64,
    targetBricks : U64,
    brickMatchPct : U64,
    matchedCells : U64,
    targetCells : U64,
    cellOverlapPct : U64,
}

BuildAction : [
    PlaceAt { kind : BrickKind, x : I32, y : I32, rotation : Rotation, color : BrickColor },
    PlaceExact { kind : BrickKind, pos : GridPos, rotation : Rotation, color : BrickColor },
    RemoveBrick U64,
    SelectTemplate TemplateId,
    LoadTemplate TemplateId,
    SetLayerLimit (Result I32 [AllLayers]),
    ToggleGuide Bool,
    SelectKind BrickKind,
    SelectRotation Rotation,
    SelectColor BrickColor,
    RotateCW,
    Undo,
    Redo,
    ClearBoard,
]

StudioModel : {
    bricks : List PlacedBrick,
    nextId : U64,
    selectedTemplate : TemplateId,
    selectedKind : BrickKind,
    selectedRotation : Rotation,
    selectedColor : BrickColor,
    guideVisible : Bool,
    layerLimit : Result I32 [AllLayers],
    undoStack : List (List PlacedBrick),
    redoStack : List (List PlacedBrick),
}

