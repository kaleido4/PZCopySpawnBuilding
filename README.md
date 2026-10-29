# Copy Spawn Building

Project Zomboid (Build 42) mod: study a building you find on the map, then build a copy of it somewhere else.

- Right-click a building (or one of its walls) and choose **Study building**. Your character looks it over with the plans in hand; bigger buildings take longer.
- Right-click anywhere and choose **Build studied building**, then pick one. A see-through copy follows the cursor, green where it fits and red where it does not. Click to build it.
- In debug mode, **Undo last spawned building** takes the last copy down again.

Work in progress (milestone 1 of 4): building is free and single player only. Planned next: a Buildings tab in the build window (vanilla and Neat Building), sizes and materials with costs, sandbox options, multiplayer, rotation.

## What gets copied

Map buildings are not stored as buildings: the map is a list of tiles per square, and a `BuildingDef` only knows the building's rooms (rectangles, level, name). Studying goes over the squares around the building and keeps the pieces of its structure:

| Kept | Left behind |
|---|---|
| floors, walls, door frames, doors, windows, window frames, stairs, roofs, wall trim | furniture, containers, loot, plants, trees, grass, blood |

Which pieces belong to the building:

- everything structural on one of its room squares, and on any square the building covers on some level (gable walls sit on the level above the top room);
- walls, doors and windows sit on a square's west or north edge, so the east and south walls are on the squares just outside the building: an edge piece belongs when the square across its edge is covered;
- roofs within 2 squares of the building (eaves hang over the walls);
- floors outside the rooms only above the ground and over the building (flat roofs, balconies), not porches or sidewalks;
- over another building, only pieces on the shared edge.

Basements are left out: a copy is built on the ground, from level 0 up.

## Building a copy

A copy fits where every square under it has ground and is not part of a building, not water, not under a vehicle and has nothing on it but plants, trees or items. Squares above the ground must be empty. Plants and trees are cleared; floors replace the grass.

Pieces are made the way the map loader and the moveables code make them: doors as `IsoDoor`, windows as `IsoWindow`, window frames as `IsoWindowFrame`, everything else as a plain `IsoObject`. Map walls are plain objects, not the `IsoThumpable` walls players build, so zombies cannot break a copy's walls, the same as the original.

## Files

| File | |
|---|---|
| `shared/CopySpawnBuilding/CSB_Core.lua` | rules: what is structure, what belongs, where a copy fits (unit-tested) |
| `shared/CopySpawnBuilding/CSB_Capture.lua` | studying: reads a building into a blueprint |
| `shared/CopySpawnBuilding/CSB_Spawn.lua` | building and undoing a copy |
| `shared/CopySpawnBuilding/CSB_Store.lua` | blueprints in global mod data, known buildings on the character |
| `client/CopySpawnBuilding/CSB_StudyAction.lua` | the Study building timed action |
| `client/CopySpawnBuilding/CSB_ContextMenu.lua` | right-click options |
| `server/CopySpawnBuilding/CSB_Cursor.lua` | placement cursor (next to the game's `ISBuildingObject`, which loads from `server/`) |

## Tests

```bash
JAVAC="/c/Program Files/Java/jdk-21.0.11/bin/javac.exe" bash tests/run_tests.sh
```

Runs the tests with Kahlua from the game's own jar against a small mock world (`tests/harness.lua`).
