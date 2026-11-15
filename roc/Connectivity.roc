module [
    ConnectionEdge,
    StructuralSummary,
    computeEdges,
    connectedComponentsCount,
    isGrounded,
    structuralSummary,
]

import Catalog
import Types exposing [
    GridPos,
    PlacedBrick,
]

ConnectionEdge : {
    lowerId : U64,
    upperId : U64,
    portCount : U64,
}

StructuralSummary : {
    brickCount : U64,
    edgeCount : U64,
    connectedComponents : U64,
    groundedBricks : U64,
    allGrounded : Bool,
}

posKey : GridPos -> (I32, I32, I32)
posKey = \pos -> (pos.x, pos.y, pos.z)

computeEdges : List PlacedBrick -> List ConnectionEdge
computeEdges = \bricks ->
    studOwnerMap =
        List.walk bricks (Dict.empty {}) \acc, brick ->
            Catalog.studPorts brick
            |> List.walk acc \inner, port ->
                Dict.insert inner (posKey port) brick.id

    pairCounts =
        List.walk bricks (Dict.empty {}) \acc, upperBrick ->
            Catalog.tubeReceptors upperBrick
            |> List.walk acc \inner, receptor ->
                when Dict.get studOwnerMap (posKey receptor) is
                    Ok lowerId ->
                        if lowerId != upperBrick.id then
                            edgeKey = (lowerId, upperBrick.id)
                            prev = Dict.get inner edgeKey |> Result.withDefault 0
                            Dict.insert inner edgeKey (prev + 1)
                        else
                            inner

                    Err KeyNotFound ->
                        inner

    Dict.toList pairCounts
    |> List.map \((lowerId, upperId), portCount) ->
        { lowerId, upperId, portCount }

buildUndirectedAdj : List PlacedBrick, List ConnectionEdge -> Dict U64 (List U64)
buildUndirectedAdj = \bricks, edges ->
    initial =
        List.walk bricks (Dict.empty {}) \acc, brick ->
            Dict.insert acc brick.id []

    List.walk edges initial \acc, edge ->
        accWithForward = addNeighbor acc edge.lowerId edge.upperId
        addNeighbor accWithForward edge.upperId edge.lowerId

addNeighbor : Dict U64 (List U64), U64, U64 -> Dict U64 (List U64)
addNeighbor = \adj, fromId, toId ->
    existing = Dict.get adj fromId |> Result.withDefault []
    if List.contains existing toId then
        adj
    else
        Dict.insert adj fromId (List.append existing toId)

traverseComponent : Dict U64 (List U64), List U64, Set U64 -> Set U64
traverseComponent = \adj, frontier, visited ->
    when frontier is
        [] -> visited
        [current, .. as rest] ->
            if Set.contains visited current then
                traverseComponent adj rest visited
            else
                nextVisited = Set.insert visited current
                neighbors = Dict.get adj current |> Result.withDefault []
                unseenNeighbors = List.dropIf neighbors \n -> Set.contains nextVisited n
                traverseComponent adj (List.concat rest unseenNeighbors) nextVisited

connectedComponentsCount : List PlacedBrick -> U64
connectedComponentsCount = \bricks ->
    edges = computeEdges bricks
    adj = buildUndirectedAdj bricks edges
    ids = List.map bricks .id

    stepComponents = \(visited, count), id ->
        if Set.contains visited id then
            (visited, count)
        else
            compVisited = traverseComponent adj [id] visited
            (compVisited, count + 1)

    (_, total) = List.walk ids (Set.empty {}, 0) stepComponents
    total

groundedIds : List PlacedBrick -> Set U64
groundedIds = \bricks ->
    edges = computeEdges bricks
    adj = buildUndirectedAdj bricks edges
    baseSeeds =
        bricks
        |> List.keepIf \brick -> brick.pos.z == 0
        |> List.map .id
    traverseComponent adj baseSeeds (Set.empty {})

isGrounded : List PlacedBrick -> Bool
isGrounded = \bricks ->
    if List.isEmpty bricks then
        Bool.true
    else
        grounded = groundedIds bricks
        List.all bricks \brick -> Set.contains grounded brick.id

structuralSummary : List PlacedBrick -> StructuralSummary
structuralSummary = \bricks ->
    edges = computeEdges bricks
    grounded = groundedIds bricks
    groundedCount = Set.len grounded
    components = connectedComponentsCount bricks
    brickCount = List.len bricks
    {
        brickCount,
        edgeCount: List.len edges,
        connectedComponents: components,
        groundedBricks: groundedCount,
        allGrounded: groundedCount == brickCount,
    }

