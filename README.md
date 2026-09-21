# TileSweep

Black squares sweep in from every edge of the screen, meet in the middle, then clear back out. Use it to hide a teleport, a loading step, or any change you do not want the player to see.

Client side only. One ModuleScript with four children. No dependencies.

## Install

Two ways:

- Get it from the [Creator Store](https://create.roblox.com/store/asset/116996144631492/TileSweep) and insert it from the Toolbox.
- Download `TileSweep.rbxm` from the [latest release](https://github.com/VapexGit/TileSweep/releases/latest) and drag it into Studio.

Then put `TileSweep` in `ReplicatedStorage`. That is all.

## Basic use

```lua
local TileSweep = require(game.ReplicatedStorage.TileSweep)

local sweep = TileSweep.new({ TileSize = 64, Duration = 0.3, Stagger = 0.5 })

sweep:Transition(0.35)
```

That covers the screen, waits 0.35 seconds, then clears it.

To run your own code while the screen is black:

```lua
sweep:Transition(function()
	character:PivotTo(destination)
	task.wait(0.2)
end)
```

The screen always clears again, even if your code throws an error.

## Main functions

| Call | What it does |
| --- | --- |
| `TileSweep.new(config)` | Makes a sweep |
| `sweep:Cover()` | Tiles fill the screen |
| `sweep:Reveal()` | Tiles clear off the screen |
| `sweep:Transition(hold)` | Cover, wait, reveal. `hold` is seconds or a function |
| `sweep:Toggle()` | Covers or reveals, based on the current state |
| `sweep:Snap(true)` | Jump straight to covered or clear, with no animation |
| `sweep:Scrub()` | Drive it yourself with `:Seek(0..1)` |
| `sweep:Cancel()` | Stop whatever is running |
| `sweep:Destroy()` | Clean everything up |

`Cover`, `Reveal` and `Transition` give you back an object with `:Await()`, `:Cancel()` and a `.Completed` signal. Nothing yields unless you call `:Await()`.

## Checking state

`sweep.State` is one of `Hidden`, `Covering`, `Covered`, `Revealing`, `Interrupted`.

```lua
sweep.StateChanged:Connect(function(state)
	print(state)
end)

if sweep:IsBusy() then
	return
end
```

Signals: `StateChanged`, `Started`, `Covered`, `Revealed`, `Completed`, `ViewportChanged`.

Readers: `GetState`, `GetPhase`, `GetProgress`, `GetOptions`, `GetGrid`, `GetTiles`, `GetGui`, `GetContainer`, `IsCovered`, `IsBusy`, `IsDestroyed`.

## Settings

There are three layers. Each one wins over the one before it.

1. `TileSweep.Config.Defaults`, edit `Config.luau` to change these for your whole game
2. the table you pass to `TileSweep.new()`
3. the table you pass to a single call

```lua
local sweep = TileSweep.new({ Pattern = "RadialIn", Color = Color3.new(0, 0, 0) })

sweep:Cover({ Style = "Pop", Duration = 0.4 })
```

Common settings: `TileSize`, `Pattern`, `Style`, `Easing`, `Duration`, `Stagger`, `Color`, `Transparency`, `Jitter`, `Origin`, `CornerRadius`, `DisplayOrder`, `Parent`, `TimeScale`. The full list with defaults is in `Config.luau`.

One sweep takes `Stagger + Duration` seconds.

You can give the cover and the reveal different settings:

```lua
TileSweep.new({
	Pattern = "RadialIn",
	Reveal = { Pattern = "RadialOut" },
})
```

## Patterns

The order the tiles arrive in.

`RadialIn` `RadialOut` `Swirl` `Spiral` `EdgesToCenter` `CenterToEdges` `Rows` `RowsReverse` `Columns` `ColumnsReverse` `Diagonal` `DiagonalReverse` `Angled` `Random` `Checker` `Uniform`

## Styles

How each tile shows up.

`Fade` `Scale` `Grow` `Pop` `Flip` `Blinds` `Wipe` `Slide` `Spin` `Instant`

## Easings

24 built in, including `Linear`, `QuadOut`, `CubicOut`, `QuartOut`, `QuintOut`, `SineInOut`, `ExpoOut`, `CircOut`, `BackOut`, `ElasticOut` and `BounceOut`. You can also pass an `Enum.EasingStyle` or your own function.

## Ten combinations worth trying

| Name | Settings |
| --- | --- |
| Radial pop | `Pattern = "RadialIn", Style = "Pop"` |
| Spin in | `Pattern = "EdgesToCenter", Style = "Spin", Easing = "BackOut"` |
| Diagonal wipe | `Pattern = "Diagonal", Style = "Wipe"` |
| Scatter | `Pattern = "Random", Style = "Grow", Jitter = 0.06` |
| Shutter | `Pattern = "Angled", Angle = 18, Style = "Flip", Easing = "CubicOut"` |
| Dissolve | `Pattern = "Random", Style = "Instant", Duration = 0.05` |
| Swirl | `Pattern = "Swirl", Style = "Pop", Easing = "QuintOut"` |
| Cascade | `Pattern = "Rows", Style = "Slide", SlideDistance = 1.6` |
| Iris | `Pattern = "RadialOut", Style = "Scale", Easing = "QuintOut"` |
| Checkerboard | `Pattern = "Checker", Style = "Grow", Easing = "BackOut"` |

## Screen sizes

Tiles are sized with scale, so the grid fills any screen with no gaps. The tile size also adjusts to the screen, so the number of tiles stays about the same everywhere and the sweep looks the same on every device.

| Screen | Grid | Tile |
| --- | --- | --- |
| 2560 x 1440 | 30 x 17 | 85 px |
| 1920 x 1080 | 30 x 17 | 64 px |
| 1024 x 768 | 26 x 20 | 39 px |
| 896 x 414 | 34 x 16 | 27 px |
| 390 x 844 | 16 x 34 | 26 px |

Set `TileScaleMode = "Fixed"` if you want exact pixel sizes, or set `Columns` and `Rows` yourself. `MaxTiles` caps the count on very large screens. If the player rotates their phone while the screen is covered, the grid rebuilds itself.

## Adding your own

Patterns, styles and easings are open lists. Add to them instead of editing the module.

```lua
TileSweep.Patterns.register("Wave", function(cell, grid, options)
	return cell.X + math.sin(cell.Y * math.pi * 3) * 0.25
end)

TileSweep.Styles.register("Squash", function(frame, coverage, cell, options)
	frame.Size = UDim2.fromScale(cell.Size.X.Scale, cell.Size.Y.Scale * coverage)
end)

sweep:Cover({ Pattern = "Wave", Style = "Squash" })
```

A pattern returns a number for each tile. The numbers get scaled to fit 0 to 1 across the whole grid, so only the order matters, not the size of the numbers.

A style gets `coverage`, which runs 0 to 1 while covering and 1 to 0 while revealing. 0 means the tile is invisible, 1 means it fully covers its cell.

For a different looking tile, pass `TileTemplate` (an instance to clone) or `TileFactory` (a function that returns one), and list the properties to animate in `TransparencyProperties`, such as `{ "ImageTransparency" }` for an ImageLabel.

One tip when writing a pattern. It looks good when it is either smooth everywhere or random everywhere. A smooth pattern with one sharp jump in it shows up as a tear across the screen. That is why `Spiral` looks rough, since its angle jumps from 1 back to 0 along one line, while `Random` looks fine.

## Speed

The whole sweep runs on one `RenderStepped` connection. Tiles are sorted by their start time and only the ones currently moving get touched each frame, so finished and waiting tiles cost nothing. Frames are reused between sweeps and the ScreenGui is turned off while nothing is showing.

## License

MIT. See [LICENSE](LICENSE).
