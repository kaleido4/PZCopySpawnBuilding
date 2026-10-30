# Copy Spawn Building

Project Zomboid (Build 42) mod: study a building you find on the map, then build a copy of it somewhere else.

- Right-click a building (or one of its walls) and choose **Study building**. Your character looks it over with the plans in hand; bigger buildings take longer.
- Under a roof that is not part of a building (carport, porch roof, shelter), choose **Study structure** instead.
- You can right-click a roof or an upper floor where you see it: one level up is drawn 3 squares further north-west on screen, so the click lands on the ground square 3 squares north-west of the roof, and the mod looks there too (`CSB.screenStack`).
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

### Structures

Carports, porch roofs and shelters often have no rooms, so the map does not know them as buildings. **Study structure** finds them by their roof: it starts at a roof piece over the square clicked (or a square next to it) and follows the roof in all 8 directions to its edges. Those roof columns then play the part of the rooms, and the floor under the roof is copied too, unless it is grass or dirt. A concrete pad that runs out past the roof is copied only under the roof. The copy is called "Shelter".

A roof that runs onto a building is part of that building, so a house's eaves or an attached porch are not structures. Roofs bigger than 400 columns are too big to study this way.

### Study report

Each study writes `Zomboid/Lua/CopySpawnBuilding_last_study.txt`: every piece kept, and everything left behind on the squares it covers with the tile's flags. If a copy is missing something (posts, trim), the report shows how that tile is flagged and why it was not taken.

## Building a copy

A copy fits where every square under it has ground and is not part of a building, not water, not under a vehicle and has nothing on it but plants, trees or items. Squares above the ground must be empty.

While placing, the copy's footprint is highlighted on the ground under the mouse, in the game's highlight colors (so they follow the colorblind option):

| Color | Meaning |
|---|---|
| good (green) | the copy fits |
| bad (red) | it does not; the square in the way is drawn stronger |
| yellow | plants, trees or items there will be removed |

The see-through building stands on the footprint; its upper levels and roof are drawn fainter so the footprint shows through.

When the copy is built, plants, trees and items lying on its squares are removed (items are deleted, not moved), and floors replace the grass. Undo does not bring them back.

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
