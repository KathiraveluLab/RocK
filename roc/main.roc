app [main] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.15.0/SlwdbJ-3GR7uBWQo6zlmYWNYOxnvo8r6YABXD-45UOw.tar.br" }

import pf.Stdout
import Blueprints
import Catalog
import Connectivity
import Lattice
import Types exposing [
    BuildAction,
    PlacedBrick,
    Rotation,
    StudioModel,
    TemplateId,
]

initModel : TemplateId -> StudioModel
initModel = \templateId ->
    {
        bricks: [],
        nextId: 1,
        selectedTemplate: templateId,
        selectedKind: Brick2x4,
        selectedRotation: Deg0,
        selectedColor: Red,
        guideVisible: Bool.true,
        layerLimit: Err AllLayers,
        undoStack: [],
        redoStack: [],
    }

rotateCW : Rotation -> Rotation
rotateCW = \rot ->
    when rot is
        Deg0 -> Deg90
        Deg90 -> Deg180
        Deg180 -> Deg270
        Deg270 -> Deg0

applyPlacement : StudioModel, PlacedBrick -> StudioModel
applyPlacement = \model, candidate ->
    when Lattice.fromBricks model.bricks is
        Ok lattice ->
            if Lattice.canPlace lattice candidate then
                { model &
                    bricks: List.append model.bricks candidate,
                    nextId: model.nextId + 1,
                    undoStack: List.append model.undoStack model.bricks,
                    redoStack: [],
                }
            else
                model

        Err _ ->
            model

step : StudioModel, BuildAction -> StudioModel
step = \model, action ->
    when action is
        PlaceAt { kind, x, y, rotation, color } ->
            snapZ =
                when Lattice.fromBricks model.bricks is
                    Ok lattice -> Lattice.snapElevation lattice kind rotation x y
                    Err _ -> 0
            candidate = {
                id: model.nextId,
                kind,
                pos: { x, y, z: snapZ },
                rotation,
                color,
            }
            applyPlacement model candidate

        PlaceExact { kind, pos, rotation, color } ->
            candidate = {
                id: model.nextId,
                kind,
                pos,
                rotation,
                color,
            }
            applyPlacement model candidate

        RemoveBrick targetId ->
            filtered = List.dropIf model.bricks \b -> b.id == targetId
            if List.len filtered == List.len model.bricks then
                model
            else
                { model &
                    bricks: filtered,
                    undoStack: List.append model.undoStack model.bricks,
                    redoStack: [],
                }

        SelectTemplate templateId ->
            { model & selectedTemplate: templateId, layerLimit: Err AllLayers }

        LoadTemplate templateId ->
            template = Blueprints.templateBricks templateId
            maxExistingId =
                List.walk template 0 \acc, b ->
                    if b.id > acc then b.id else acc
            { model &
                bricks: template,
                nextId: maxExistingId + 1,
                selectedTemplate: templateId,
                layerLimit: Err AllLayers,
                undoStack: List.append model.undoStack model.bricks,
                redoStack: [],
            }

        SetLayerLimit limit ->
            { model & layerLimit: limit }

        ToggleGuide visible ->
            { model & guideVisible: visible }

        SelectKind kind ->
            { model & selectedKind: kind }

        SelectRotation rot ->
            { model & selectedRotation: rot }

        SelectColor color ->
            { model & selectedColor: color }

        RotateCW ->
            { model & selectedRotation: rotateCW model.selectedRotation }

        Undo ->
            when List.last model.undoStack is
                Ok prevBricks ->
                    { model &
                        bricks: prevBricks,
                        undoStack: List.dropLast model.undoStack 1,
                        redoStack: List.append model.redoStack model.bricks,
                    }

                Err ListWasEmpty ->
                    model

        Redo ->
            when List.last model.redoStack is
                Ok nextBricks ->
                    { model &
                        bricks: nextBricks,
                        undoStack: List.append model.undoStack model.bricks,
                        redoStack: List.dropLast model.redoStack 1,
                    }

                Err ListWasEmpty ->
                    model

        ClearBoard ->
            if List.isEmpty model.bricks then
                model
            else
                { model &
                    bricks: [],
                    undoStack: List.append model.undoStack model.bricks,
                    redoStack: [],
                }

main =
    carCount = List.len (Blueprints.templateBricks RaceCar) |> Num.toStr
    gondolaCount = List.len (Blueprints.templateBricks Gondola) |> Num.toStr
    airplaneCount = List.len (Blueprints.templateBricks Airplane) |> Num.toStr
    catalogCount = List.len Catalog.allSpecs |> Num.toStr
    Stdout.line! "RocK core initialized: $(catalogCount) brick types, templates (RaceCar=$(carCount), Gondola=$(gondolaCount), Airplane=$(airplaneCount))."

expect
    car = Blueprints.templateBricks RaceCar
    Result.isOk (Lattice.fromBricks car)

expect
    gondola = Blueprints.templateBricks Gondola
    Result.isOk (Lattice.fromBricks gondola)

expect
    airplane = Blueprints.templateBricks Airplane
    Result.isOk (Lattice.fromBricks airplane)

expect
    car = Blueprints.templateBricks RaceCar
    summary = Connectivity.structuralSummary car
    summary.connectedComponents == 1 && summary.allGrounded

expect
    gondola = Blueprints.templateBricks Gondola
    summary = Connectivity.structuralSummary gondola
    summary.connectedComponents == 1 && summary.allGrounded

expect
    airplane = Blueprints.templateBricks Airplane
    summary = Connectivity.structuralSummary airplane
    summary.connectedComponents == 1 && summary.allGrounded

expect
    m0 = initModel RaceCar
    m1 = step m0 (PlaceAt { kind: WheelAxle2x2, x: 7, y: 5, rotation: Deg0, color: Slate })
    m2 = step m1 (PlaceAt { kind: WheelAxle2x2, x: 7, y: 9, rotation: Deg0, color: Slate })
    m3 = step m2 (PlaceAt { kind: Plate2x6, x: 7, y: 5, rotation: Deg0, color: White })
    when List.last m3.bricks is
        Ok lastBrick -> lastBrick.pos.z == 1
        Err _ -> Bool.false

expect
    m0 = initModel Airplane
    m1 = step m0 (LoadTemplate Airplane)
    target = Blueprints.templateBricks Airplane
    metrics = Blueprints.evaluateMatch m1.bricks target
    metrics.brickMatchPct == 100 && metrics.cellOverlapPct == 100

