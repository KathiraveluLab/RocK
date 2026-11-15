# RocK

Roc-based Lego-style block construction game and interactive 3D workbench.

## Architecture

RocK separates deterministic domain logic from host rendering and interactive input handling across two synchronized layers:

1. **Pure Roc Domain Core (`roc/`)**:
   - `roc/Types.roc`: Algebraic data types for discrete 3D stud-and-plate coordinates (`GridPos`), 90-degree rotations (`Rotation`), 15 interlocking block archetypes (`BrickKind`), an 8-color palette (`BrickColor`), blueprint metadata, and studio state transitions (`BuildAction`, `StudioModel`).
   - `roc/Catalog.roc`: Dimension tables, orientation-aware bounding footprint calculation, occupied cell enumeration, top stud ports, and bottom anti-stud tube receptors.
   - `roc/Lattice.roc`: Discrete $16 \times 16 \times 36$ spatial occupancy index enforcing boundary constraints, collision-free placement, and automatic drag-and-drop elevation snapping (`snapElevation`).
   - `roc/Connectivity.roc`: Directed stud-to-tube mechanical graph builder calculating connected components and baseplate grounding.
   - `roc/Blueprints.roc`: Canonical starter templates (`RaceCar`, `Gondola`, `Airplane`), layer slicing, and real-time blueprint matching metrics.
   - `roc/main.roc`: Application reducer and inline `expect` verification tests.

2. **Interactive Studio Host (`lib/` and `priv/static/`)**:
   - `lib/rock/`: Elixir OTP host (`Rock.Catalog`, `Rock.Lattice`, `Rock.Connectivity`, `Rock.Blueprints`, `Rock.Studio`, `Rock.Server`, `Rock.Application`) exposing a state-synchronized HTTP/JSON API and serving the studio UI.
   - `priv/static/`: Light-theme 3D isometric drag-and-drop studio (`index.html`, `studio.css`, `studio.js`) featuring a categorized draggable block catalog, color swatches, orientation controls (`R` key or toolbar buttons), live ghost-brick snap previews, step-by-step layer slicing, ghost blueprint overlays, and a dedicated 3D reference canvas.

## Starter Design Templates

- **Modular Roadster (`race_car`)**: 12 bricks across 4 elevation layers (`z = 0, 1, 2, 5`), featuring twin `WheelAxle2x2` assemblies, a `Plate2x6` chassis, `Brick2x4` and `Brick1x2` bodywork, a `Slope2x2` hood, a `Cockpit2x2` canopy, and split `Slope1x2` rear spoilers.
- **Venetian & Alpine Gondola (`gondola`)**: 13 bricks across 5 elevation layers (`z = 0, 1, 2, 5, 6`), combining a staggered running-bond keel (`Plate2x4` and `Plate2x6`), bow and stern slopes, a central `Cabin2x4` flanked by `Brick1x2` pillars, a canopy roof, and a symmetric top crest.
- **Swept-Wing Skyplane (`airplane`)**: 14 bricks across 6 elevation levels (`z = 0, 1, 2, 3, 4, 6`), featuring a central keel, transverse `Plate2x6` wing spar, port and starboard swept wings (`WingLeft2x3`, `WingRight2x3`), sloped nose cowling, `Cockpit2x2` canopy, horizontal tail stabilizer, and vertical tail fin.

## Running and Testing

Run the Elixir test suite and strict compiler check (`--warnings-as-errors`):

```bash
mix precommit
```

On Windows systems where Mix hard-link locking is unavailable, set `MIX_OS_CONCURRENCY_LOCK=0`:

```powershell
$env:MIX_OS_CONCURRENCY_LOCK="0"
mix precommit
```

Start the interactive browser studio server (default port `4000`):

```bash
mix rock.server
```

Run the pure Roc unit tests (requires the Roc toolchain installed on `PATH`):

```bash
roc test roc/main.roc
```
