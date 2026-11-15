module [
    Lattice,
    baseplateSize,
    maxElevationPlates,
    empty,
    fromBricks,
    withinBounds,
    canPlace,
    snapElevation,
    insertBrick,
    removeBrick,
]

import Catalog
import Types exposing [
    BrickKind,
    GridPos,
    PlacedBrick,
    Rotation,
]

CellKey : (I32, I32, I32)

Lattice : Dict CellKey U64

baseplateSize : I32
baseplateSize = 16

maxElevationPlates : I32
maxElevationPlates = 36

empty : Lattice
empty = Dict.empty {}

cellKey : GridPos -> CellKey
cellKey = \pos -> (pos.x, pos.y, pos.z)

withinBounds : PlacedBrick -> Bool
withinBounds = \brick ->
    dims = Catalog.rotatedDimensions brick.kind brick.rotation
    minX = brick.pos.x
    minY = brick.pos.y
    minZ = brick.pos.z
    maxX = minX + dims.width
    maxY = minY + dims.depth
    maxZ = minZ + dims.heightPlates
    minX >= 0
    && minY >= 0
    && minZ >= 0
    && maxX <= baseplateSize
    && maxY <= baseplateSize
    && maxZ <= maxElevationPlates

canPlace : Lattice, PlacedBrick -> Bool
canPlace = \lattice, brick ->
    if !(withinBounds brick) then
        Bool.false
    else
        Catalog.occupiedCells brick
        |> List.all \cell ->
            !(Dict.contains lattice (cellKey cell))

insertBrick : Lattice, PlacedBrick -> Result Lattice [OutOfBounds, Collision]
insertBrick = \lattice, brick ->
    if !(withinBounds brick) then
        Err OutOfBounds
    else if !(canPlace lattice brick) then
        Err Collision
    else
        updated =
            Catalog.occupiedCells brick
            |> List.walk lattice \acc, cell ->
                Dict.insert acc (cellKey cell) brick.id
        Ok updated

fromBricks : List PlacedBrick -> Result Lattice [OutOfBounds, Collision]
fromBricks = \bricks ->
    List.walkTry bricks empty \acc, brick ->
        insertBrick acc brick

removeBrick : Lattice, U64 -> Lattice
removeBrick = \lattice, targetId ->
    Dict.walk lattice empty \acc, key, ownerId ->
        if ownerId == targetId then
            acc
        else
            Dict.insert acc key ownerId

snapElevation : Lattice, BrickKind, Rotation, I32, I32 -> I32
snapElevation = \lattice, kind, rotation, x, y ->
    dims = Catalog.rotatedDimensions kind rotation
    minX = x
    maxX = x + dims.width
    minY = y
    maxY = y + dims.depth
    Dict.walk lattice 0 \highestNextZ, (cx, cy, cz), _ownerId ->
        if cx >= minX && cx < maxX && cy >= minY && cy < maxY then
            candidateZ = cz + 1
            if candidateZ > highestNextZ then
                candidateZ
            else
                highestNextZ
        else
            highestNextZ

