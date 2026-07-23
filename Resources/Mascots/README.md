# Mascots

Every `*.png` in this folder becomes a walking mascot, chosen at random each time
one appears. **To add one: drop a PNG here and rebuild** (`./build.sh`) — no code
change needed. `build.sh` copies these into `AgentWatch.app/Contents/Resources/Mascots/`,
and `MascotView` discovers them at runtime.

Art tips:
- **Square, transparent PNG.** It's drawn scaled-to-fit in a 96×96 pt box.
- Export at ~2–3× (≈192–288 px) so it's crisp on Retina.
- The art can include its own speech bubble; image mascots show only a small
  profile chip above them (drawn mascots get the full speech bubble instead).

Built-in drawn characters (sponge, robot, blob) need no art and are always in the
rotation alongside whatever PNGs live here.
