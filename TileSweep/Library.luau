local TweenService = game:GetService("TweenService")

local Library = {}

local function createRegistry(fallbackName)
	local registry = { Entries = {} }

	function registry.register(name, entry)
		registry.Entries[name] = entry
		return entry
	end

	function registry.get(nameOrFunction)
		if type(nameOrFunction) == "function" then
			return nameOrFunction
		end
		return registry.Entries[nameOrFunction] or registry.Entries[fallbackName]
	end

	function registry.has(name)
		return registry.Entries[name] ~= nil
	end

	function registry.list()
		local names = {}
		for name in registry.Entries do
			table.insert(names, name)
		end
		table.sort(names)
		return names
	end

	return registry
end

local Easing = createRegistry("Linear")
local Patterns = createRegistry("RadialIn")
local Styles = createRegistry("Fade")

local easings = Easing.Entries
local patterns = Patterns.Entries
local styles = Styles.Entries

local function registerFamily(name, exponent)
	easings[name .. "In"] = function(alpha)
		return alpha ^ exponent
	end
	easings[name .. "Out"] = function(alpha)
		return 1 - (1 - alpha) ^ exponent
	end
	easings[name .. "InOut"] = function(alpha)
		if alpha < 0.5 then
			return (2 * alpha) ^ exponent * 0.5
		end
		return 1 - (2 - 2 * alpha) ^ exponent * 0.5
	end
end

easings.Linear = function(alpha)
	return alpha
end

registerFamily("Quad", 2)
registerFamily("Cubic", 3)
registerFamily("Quart", 4)
registerFamily("Quint", 5)

easings.SineIn = function(alpha)
	return 1 - math.cos(alpha * math.pi * 0.5)
end

easings.SineOut = function(alpha)
	return math.sin(alpha * math.pi * 0.5)
end

easings.SineInOut = function(alpha)
	return -(math.cos(math.pi * alpha) - 1) * 0.5
end

easings.ExpoIn = function(alpha)
	return alpha <= 0 and 0 or 2 ^ (10 * alpha - 10)
end

easings.ExpoOut = function(alpha)
	return alpha >= 1 and 1 or 1 - 2 ^ (-10 * alpha)
end

easings.CircIn = function(alpha)
	return 1 - math.sqrt(math.max(0, 1 - alpha * alpha))
end

easings.CircOut = function(alpha)
	return math.sqrt(math.max(0, 1 - (alpha - 1) ^ 2))
end

local BACK = 1.70158

easings.BackIn = function(alpha)
	return (BACK + 1) * alpha ^ 3 - BACK * alpha ^ 2
end

easings.BackOut = function(alpha)
	return 1 + (BACK + 1) * (alpha - 1) ^ 3 + BACK * (alpha - 1) ^ 2
end

easings.ElasticOut = function(alpha)
	if alpha <= 0 then
		return 0
	elseif alpha >= 1 then
		return 1
	end
	return 2 ^ (-10 * alpha) * math.sin((alpha * 10 - 0.75) * (2 * math.pi / 3)) + 1
end

easings.BounceOut = function(alpha)
	local scale, divisor = 7.5625, 2.75
	if alpha < 1 / divisor then
		return scale * alpha * alpha
	elseif alpha < 2 / divisor then
		alpha -= 1.5 / divisor
		return scale * alpha * alpha + 0.75
	elseif alpha < 2.5 / divisor then
		alpha -= 2.25 / divisor
		return scale * alpha * alpha + 0.9375
	end
	alpha -= 2.625 / divisor
	return scale * alpha * alpha + 0.984375
end

local getRegisteredEasing = Easing.get

function Easing.get(nameOrFunction, easingDirection)
	if typeof(nameOrFunction) == "EnumItem" and nameOrFunction.EnumType == Enum.EasingStyle then
		local direction = easingDirection or Enum.EasingDirection.Out
		return function(alpha)
			return TweenService:GetValue(math.clamp(alpha, 0, 1), nameOrFunction, direction)
		end
	end
	return getRegisteredEasing(nameOrFunction)
end

local DEFAULT_ORIGIN = Vector2.new(0.5, 0.5)

local function offsetFromCenter(cell)
	return cell.X * 2 - 1, cell.Y * 2 - 1
end

local function offsetFromOrigin(cell, grid, options)
	local origin = options.Origin or DEFAULT_ORIGIN
	local offsetX = cell.X - origin.X
	if options.AspectCorrect then
		offsetX *= grid.Aspect or 1
	end
	return offsetX, cell.Y - origin.Y
end

local function circularOffsetFromOrigin(cell, grid, options)
	local origin = options.Origin or DEFAULT_ORIGIN
	return (cell.X - origin.X) * (grid.Aspect or 1), cell.Y - origin.Y
end

local function angleFraction(x, y)
	return (math.atan2(y, x) + math.pi) / (math.pi * 2)
end

patterns.Uniform = function()
	return 0
end

patterns.EdgesToCenter = function(cell)
	local x, y = offsetFromCenter(cell)
	return 1 - math.max(math.abs(x), math.abs(y))
end

patterns.CenterToEdges = function(cell)
	local x, y = offsetFromCenter(cell)
	return math.max(math.abs(x), math.abs(y))
end

patterns.RadialIn = function(cell, grid, options)
	local x, y = offsetFromOrigin(cell, grid, options)
	return -math.sqrt(x * x + y * y)
end

patterns.RadialOut = function(cell, grid, options)
	local x, y = offsetFromOrigin(cell, grid, options)
	return math.sqrt(x * x + y * y)
end

patterns.Rows = function(cell)
	return cell.Y
end

patterns.RowsReverse = function(cell)
	return 1 - cell.Y
end

patterns.Columns = function(cell)
	return cell.X
end

patterns.ColumnsReverse = function(cell)
	return 1 - cell.X
end

patterns.Diagonal = function(cell)
	return cell.X + cell.Y
end

patterns.DiagonalReverse = function(cell)
	return (1 - cell.X) + cell.Y
end

patterns.Angled = function(cell, _grid, options)
	local radians = math.rad(options.Angle or 45)
	return (cell.X - 0.5) * math.cos(radians) + (cell.Y - 0.5) * math.sin(radians)
end

patterns.Spiral = function(cell, grid, options)
	local x, y = circularOffsetFromOrigin(cell, grid, options)
	local turns = math.max(options.SpiralTurns or 2, 0.1)
	return math.sqrt(x * x + y * y) * turns + angleFraction(x, y)
end

patterns.Swirl = function(cell, grid, options)
	local x, y = circularOffsetFromOrigin(cell, grid, options)
	local radius = math.sqrt(x * x + y * y)
	local armCount = math.max(math.floor(options.SwirlArms or 3), 1)
	local twist = options.SwirlTwist or 1.5
	local amplitude = options.SwirlAmplitude or 0.35
	local wave = math.sin(armCount * math.atan2(y, x) + radius * twist * math.pi * 2)
	return radius * (1 + amplitude * wave)
end

patterns.Random = function(cell, _grid, options)
	local seed = options.Seed or 0
	local noise = math.sin(cell.Column * 127.1 + cell.Row * 311.7 + seed * 74.7) * 43758.5453
	return noise - math.floor(noise)
end

patterns.Checker = function(cell)
	return (cell.Column + cell.Row) % 2
end

local CENTER = Vector2.new(0.5, 0.5)
local DEFAULT_TRANSPARENCY = { "BackgroundTransparency" }
local DEFAULT_DIRECTION = Vector2.new(0, -1)

local function scaleSize(size, factorX, factorY)
	return UDim2.new(
		size.X.Scale * factorX,
		size.X.Offset * factorX,
		size.Y.Scale * factorY,
		size.Y.Offset * factorY
	)
end

local function setTransparency(frame, value, options)
	local properties = options.TransparencyProperties or DEFAULT_TRANSPARENCY
	for _, property in properties do
		frame[property] = value
	end
end

local function coveredTransparency(options)
	return options.Transparency or 0
end

local function fadedTransparency(coverage, options)
	return 1 - coverage * (1 - coveredTransparency(options))
end

styles.Fade = function(frame, coverage, _cell, options)
	setTransparency(frame, fadedTransparency(coverage, options), options)
end

styles.Scale = function(frame, coverage, cell, options)
	frame.Size = scaleSize(cell.Size, coverage, coverage)
	setTransparency(frame, coveredTransparency(options), options)
end

styles.Grow = function(frame, coverage, cell, options)
	frame.Size = scaleSize(cell.Size, coverage, coverage)
	setTransparency(frame, fadedTransparency(coverage, options), options)
end

styles.Pop = function(frame, coverage, cell, options)
	local overshoot = options.Overshoot or 0.25
	local factor = coverage * (1 + overshoot * math.sin(coverage * math.pi))
	frame.Size = scaleSize(cell.Size, factor, factor)
	setTransparency(frame, fadedTransparency(coverage, options), options)
end

styles.Flip = function(frame, coverage, cell, options)
	frame.Size = scaleSize(cell.Size, coverage, 1)
	setTransparency(frame, coveredTransparency(options), options)
end

styles.Blinds = function(frame, coverage, cell, options)
	frame.Size = scaleSize(cell.Size, 1, coverage)
	setTransparency(frame, coveredTransparency(options), options)
end

styles.Wipe = function(frame, coverage, cell, options)
	local direction = options.SlideDirection or DEFAULT_DIRECTION
	local growFrom = Vector2.new(0.5 + direction.X * 0.5, 0.5 + direction.Y * 0.5)

	frame.AnchorPoint = growFrom
	frame.Position = cell.Position
		+ UDim2.fromScale((growFrom.X - 0.5) * cell.Size.X.Scale, (growFrom.Y - 0.5) * cell.Size.Y.Scale)
	frame.Size = scaleSize(
		cell.Size,
		direction.X ~= 0 and coverage or 1,
		direction.Y ~= 0 and coverage or 1
	)
	setTransparency(frame, coveredTransparency(options), options)
end

styles.Slide = function(frame, coverage, cell, options)
	local direction = options.SlideDirection or DEFAULT_DIRECTION
	local travelled = (1 - coverage) * (options.SlideDistance or 1.25)

	frame.Position = cell.Position
		+ UDim2.fromScale(
			direction.X * travelled * cell.Size.X.Scale,
			direction.Y * travelled * cell.Size.Y.Scale
		)
	setTransparency(frame, fadedTransparency(coverage, options), options)
end

styles.Spin = function(frame, coverage, cell, options)
	frame.Rotation = (1 - coverage) * (options.Rotation or 120)
	frame.Size = scaleSize(cell.Size, coverage, coverage)
	setTransparency(frame, fadedTransparency(coverage, options), options)
end

styles.Instant = function(frame, coverage, _cell, options)
	setTransparency(frame, coverage >= 0.5 and coveredTransparency(options) or 1, options)
end

function Styles.reset(frame, cell, options)
	frame.AnchorPoint = CENTER
	frame.Position = cell.Position
	frame.Size = cell.Size
	frame.Rotation = 0
	setTransparency(frame, coveredTransparency(options), options)
end

Styles.setTransparency = setTransparency

Library.Easing = Easing
Library.Patterns = Patterns
Library.Styles = Styles
Library.createRegistry = createRegistry

return Library
