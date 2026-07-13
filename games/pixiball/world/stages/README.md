# Ballpark stage modules

`PixelBallparkCanvas` is a thin orchestrator. Drawing lives in these stages:

| Module | Owns |
| --- | --- |
| `atmosphere.gd` | Sky, sea, weather notes, mist, vignette |
| `skyline.gd` | Wharf stamps, lighthouse, breakwater, windows |
| `playfield.gd` | Turf, clay, chalk, mound, bags, lamp pools |
| `stands.gd` | Grandstand, crowd clumps, bell, LED, fireworks |
| `views.gd` | Intro / pitching / batting / fielding / dugout compositions |

Shared design-grid landmarks (band datums, plate/mound/bags, projection lanes)
live in `../view_landmarks.gd` and are also consumed by
`presentation/broadcast_camera.gd`.
