# clawd-wallpaper

A tiny pixel Claude Code mascot in a Santa hat that lives on your Mac desktop, under your icons and windows. It was made as a funny contrast to a very serious Berserk wallpaper.

![Poses](docs/poses.png)

macOS can't animate a still wallpaper, so this is a small native app that draws only the mascot in a transparent desktop-level window. Your wallpaper stays as it is. It uses about 1% CPU and stops updating while the display sleeps.

## What he does

- His eyes follow your cursor. Leave the cursor alone for 10 seconds and he looks at the moon or at Guts instead.
- Sometimes he waves at Guts. Guts never waves back.
- Hover over him for `> <` eyes and an excited wiggle.
- He blinks, bobs, tippy-taps his feet, and his pompom swings.
- A Claude Code-style status line sits under him, such as `✻ Compacting 200 years of trauma… (13s · esc to interrupt)`.

## Build and run

Needs macOS and the Xcode command line tools.

```sh
swiftc -O main.swift -o ClawdWallpaper
./ClawdWallpaper &
```

Stop it with `pkill ClawdWallpaper`. Only one copy runs at a time.

To bake him into a copy of an image instead, with no app running:

```sh
./ClawdWallpaper --bake wallpaper.jpg wallpaper-clawd.jpg
```

Don't use a baked image as your wallpaper while the app is running, or you'll see two of him.

`./ClawdWallpaper --sheet poses.png` renders the pose sheet above.

## Using your own wallpaper

No wallpaper is included. The positions at the top of `main.swift` are fractions of the image, and they're set up for one specific 16:9 picture:

- `anchorFrac`: where he floats
- `moonFrac` and `gutsFrac`: what he looks at when idle
- `baseUnit`: his size

The live mode assumes the wallpaper uses the **Crop** placement (Fill Screen), and it places him the same way on each display. The verbs are in the `verbs` array.

## Credits

This is a fan project, not affiliated with or endorsed by Anthropic. Claude, Claude Code and the mascot belong to Anthropic, and Berserk belongs to Kentaro Miura and his publishers. The MIT license covers the code in this repo only.
