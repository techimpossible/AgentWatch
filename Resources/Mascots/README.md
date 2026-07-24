# Mascots

Every `*.png` in this folder becomes a walking mascot, chosen at random each time
one appears. **To add one: drop a PNG here and rebuild** (`./build.sh`) — no code
change needed. `build.sh` copies these into `AgentWatch.app/Contents/Resources/Mascots/`,
and `MascotView` discovers them at runtime.

**Animated mascots:** name frames `<name>-1.png`, `<name>-2.png`, … and they
group into one mascot ("Name") that cycles through its frames (~0.38 s per
frame, matching the drawn characters' stride), with a groove sway/bounce layered
on top so poses flow together. Two opposite-step frames read as a walk; the
bundled mascots use a 5-frame dance (crouch → leap → sway left → sway right →
moonwalk). A single un-suffixed PNG still works — it gets a gentle waddle
instead.

Art tips:
- **Square, transparent PNG.** It's drawn scaled-to-fit in a 96×96 pt box.
- Export at ~2–3× (≈192–288 px) so it's crisp on Retina.
- The art can include its own speech bubble; image mascots show only a small
  profile chip above them (drawn mascots get the full speech bubble instead).

Built-in drawn characters (sponge, robot, blob) need no art and are always in the
rotation alongside whatever PNGs live here.
