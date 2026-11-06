# clawd-wallpaper

A tiny pixel Claude Code mascot that lives on your Mac desktop, under your icons and windows. It was made as a funny contrast to a very serious Berserk wallpaper, and he can wear whatever you like.

![Outfits and expressions](docs/poses.png)

macOS can't animate a still wallpaper, so this is a small native app that draws only the mascot in a transparent desktop-level window. Your wallpaper stays as it is.

## Build and run

Needs macOS and the Xcode command line tools.

```sh
swiftc -O -framework IOKit main.swift -o ClawdWallpaper
./ClawdWallpaper &
```

Stop it with `pkill ClawdWallpaper`. Only one copy runs at a time.

## Choose what he wears

```sh
./ClawdWallpaper --hat santa              # always the Santa hat
./ClawdWallpaper --hat none --wear none   # just him
./ClawdWallpaper --hat crown --wear cape,sword
./ClawdWallpaper --hat helm --wear armor,cape,sword
./ClawdWallpaper --list                   # show every option
```

| Option | Choices |
| --- | --- |
| `--hat` | `auto`, `santa`, `wizard`, `crown`, `party`, `viking`, `helm`, `none` |
| `--wear` | `auto`, `none`, or any comma-separated mix of `cape`, `armor`, `scarf`, `sword` |

Without options, `auto` follows the calendar: the Santa hat in December, a wizard hat from September to November, and a cape the rest of the year.

### Add your own

Add a case to `Hat` or `Gear` in `main.swift`, then draw it in `drawHat` or at the top of `drawSprite` using sprite pixels. A new hat also needs its snow spots in `snowSpots`. The Swift compiler points at anything you've missed.

## What he does

**Most of the time**
- His eyes follow your cursor. Leave it alone for 10 seconds and he looks at the moon or at Guts instead.
- He blinks, bobs, tippy-taps his feet, and sometimes waves at Guts. Guts never waves back.
- A Claude Code-style status line sits under him, such as `✻ Compacting 200 years of trauma… (13s · esc to interrupt)`.

**When you interact**
- Hover over him for `> <` eyes and an excited wiggle.
- Click near him and he flinches. Click on him and he hops.
- Circle the cursor around him and he gets pulled along, then ends up dizzy with spiral eyes.

**Now and then**
- **The sword:** a slab of iron slides in tip first and keeps on arriving. Then he appears, pushing it. He lifts it 1 pixel, falls over, stares at Guts for approval, and hauls it away with his hat on crooked.
- **The Eclipse:** very rarely, the moon goes dark with a red ring. He panics, then acts like nothing happened.
- **Snow:** flakes drift past and settle on him until he shakes them off.
- **Sleep:** he dozes off if you're away for 5 minutes, or 1 minute late at night, and jolts awake when you move the mouse.
- **Low battery:** under 10% he gets visibly tired and runs on fumes.

To see a scene right away:

```sh
./ClawdWallpaper --demo sword     # also eclipse, snow, sleep, dizzy, battery, click
```

## Performance

He's built to cost almost nothing:

- He pauses completely while your windows cover him or the display is asleep.
- Art is drawn at low resolution and scaled by the GPU, and nothing redraws unless it changed.
- The update rate drops when nothing is happening, and further when he's asleep or in Low Power Mode.
- The sword and the Eclipse only exist while they're on screen.

Measured on an M4 MacBook Air, for the app's own process only, not including the work macOS does to draw it to the screen:

| State | CPU | Memory |
| --- | --- | --- |
| Covered by windows | 0.03% | 10 MB |
| Visible, idle | 0.6% | 10 MB |
| Sword scene | 0.8% | 10 MB |

Clicks are noticed with a system mouse monitor that only uses the click's position. It doesn't see keystrokes, and nothing is recorded or sent anywhere.

## Using your own wallpaper

No wallpaper is included. The positions at the top of `main.swift` are fractions of the image, set up for one specific 16:9 picture:

- `anchorFrac`: where he floats
- `moonFrac`, `moonRadiusFrac`: the moon, for looking at and for the Eclipse
- `gutsFrac`: what else he looks at
- `baseUnit`: his size

Live mode assumes the wallpaper uses the **Crop** placement (Fill Screen). The status lines are in the `verbs` array.

To bake him into a copy of an image instead, with no app running:

```sh
./ClawdWallpaper --bake wallpaper.jpg wallpaper-clawd.jpg --hat santa
```

Don't use a baked image as your wallpaper while the app is running, or you'll see two of him.

## Testing

```sh
./ClawdWallpaper --selftest                       # every outfit through every scene
./ClawdWallpaper --frames out/ wallpaper.jpg      # render each scene to a sheet of frames
./ClawdWallpaper --sheet poses.png                # the image at the top of this page
```

## Credits

This is a fan project, not affiliated with or endorsed by Anthropic. Claude, Claude Code and the mascot belong to Anthropic, and Berserk belongs to Kentaro Miura and his publishers. The MIT license covers the code in this repo only.
