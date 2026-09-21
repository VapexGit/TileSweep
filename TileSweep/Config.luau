local Config = {}

Config.Phase = {
	Cover = "Cover",
	Reveal = "Reveal",
}

Config.State = {
	Hidden = "Hidden",
	Covering = "Covering",
	Covered = "Covered",
	Revealing = "Revealing",
	Interrupted = "Interrupted",
}

Config.Defaults = {
	TileSize = 72,
	TileScaleMode = "Adaptive",
	ReferenceViewport = Vector2.new(1920, 1080),
	MinTileScale = 0.3,
	MaxTileScale = 2.5,
	MinTileSize = 16,
	MaxTileSize = 512,
	MaxTiles = 4096,
	Overscan = 0,
	Bleed = 1,
	AutoRefresh = true,

	Pattern = "RadialIn",
	Style = "Fade",
	Easing = "QuadOut",
	EasingDirection = Enum.EasingDirection.Out,

	Duration = 0.26,
	Stagger = 0.45,
	TimeScale = 1,
	Jitter = 0,
	Invert = false,
	Normalize = true,

	Origin = Vector2.new(0.5, 0.5),
	AspectCorrect = false,
	Angle = 45,
	SpiralTurns = 2,
	SwirlArms = 3,
	SwirlTwist = 1.5,
	SwirlAmplitude = 0.35,
	SlideDirection = Vector2.new(0, -1),
	SlideDistance = 1.25,
	Rotation = 120,
	Overshoot = 0.25,

	Color = Color3.new(0, 0, 0),
	Transparency = 0,
	TransparencyProperties = { "BackgroundTransparency" },
	CornerRadius = 0,
	ZIndex = 1,

	GuiName = "TileSweep",
	DisplayOrder = 2147483647,
	IgnoreGuiInset = true,
	Modal = true,

	Cover = {},
	Reveal = { Invert = true },
}

local function applyLayer(resolved, layer)
	if type(layer) ~= "table" then
		return resolved
	end

	for key, value in layer do
		if Config.Phase[key] == nil then
			resolved[key] = value
		end
	end

	return resolved
end

local function phaseLayer(layer, phase)
	return type(layer) == "table" and layer[phase] or nil
end

function Config.resolve(phase, instanceConfig, callOverrides)
	local resolved = {}

	applyLayer(resolved, Config.Defaults)
	applyLayer(resolved, Config.Defaults[phase])
	applyLayer(resolved, instanceConfig)
	applyLayer(resolved, phaseLayer(instanceConfig, phase))
	applyLayer(resolved, callOverrides)
	applyLayer(resolved, phaseLayer(callOverrides, phase))

	return resolved
end

function Config.setDefaults(overrides)
	if type(overrides) ~= "table" then
		return Config.Defaults
	end

	for key, value in overrides do
		Config.Defaults[key] = value
	end

	return Config.Defaults
end

Config.applyLayer = applyLayer

return Config
