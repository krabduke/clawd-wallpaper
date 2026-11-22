# clawd-wallpaper v2

A smaller, simpler Clawd: just the Claude Code mascot, a laptop, and a Santa hat that comes and goes. He floats in the dark sky above the art on an ASCII *Creation of Adam* wallpaper, and every few minutes his Santa hat makes an entrance.

v1, with all the looks and the Berserk scenes, is still in the folder above this one.

## Build and run

Needs macOS 14 or later and the Xcode command line tools.

```sh
cd v2
./build.sh --install
```

This builds `ClawdWallpaper.app`, copies it to `/Applications` (replacing v1 if it's there) and opens it. He adds himself to your login items, the same as v1.

- Stop him for now: `pkill ClawdWallpaper`
- Stop him opening at login: `/Applications/ClawdWallpaper.app/Contents/MacOS/ClawdWallpaper --no-login`
- Hat entrances more or less often: `ClawdWallpaper --every 1` (minutes per on-and-off round, default 3)

## What he does

- **Floats and breathes**, with a soft glow behind him.
- **Watches your cursor.** Leave the mouse alone for a while and he looks around instead. Hover over him and he squints happily and taps his feet.
- **Blinks**, sometimes twice.
- **Puts the laptop down, most of the time.** It spends about 70% of the time on the floor beside him: he bends down, swings it out to his right, sets it down level with his feet and floats back up, and it stays still while he bobs next to it. After a while he picks it up again and types for a bit, then puts it back.
- **Types.** While he's holding it, his arms go in, his hands go to the keys, the screen flickers, and he looks down at what he's writing.
- **The hat.** He's bare-headed about 70% of the time. About 4 seconds after launch, and then roughly every 3 minutes, the hat makes an entrance, a different one each time:
  - dropped from the sky, landing hard enough to squash him
  - flung back in like a boomerang, spinning
  - waiting in the air, so he crouches and jumps up into it
  - appearing out of nowhere with a flourish

  It lands with a burst of sparkles. After about a minute it leaves again, popped straight up or blown off by a gust.

## Smooth and cheap

Every part of him (body, eyes, arms, legs, laptop, hat, pompom) is its own little layer, moved along eased curves, springs and squash-and-stretch, instead of being redrawn as pixels.

- The loops that never stop (floating, breathing, the glow, the pompom) are Core Animation animations, which macOS plays without waking the app.
- Everything else runs on the display link only while it's happening: 60 fps for the hat, 30 for blinking, typing and eye movement, and not at all in between.
- He stops completely while your windows cover him.

Measured on an M4 MacBook Air: about 0.3% CPU on average and 12 MB of memory.

## Your own wallpaper

He sits on the MacBook's built-in screen. His position is a fraction of the wallpaper image, set at the top of `main.swift`:

- `imageSize`: the image's pixel size (2880 × 1864 here)
- `anchorFrac`: where he floats, x from the left and y from the top (0.30, 0.11: well left of centre, in the dark band above the art)
- `baseUnit`: his size

It assumes the **Fill Screen** placement.

## Testing

```sh
ClawdWallpaper --selftest                   # every entrance, a long pause in each, typing, eyes, the hat's and laptop's 70%
ClawdWallpaper --frames out/ wallpaper.png  # each entrance as a sheet of frames, and where he sits on the screen
```

## Credits

A fan project, not affiliated with or endorsed by Anthropic. Claude, Claude Code and the mascot belong to Anthropic. The MIT license covers the code in this repo only.
