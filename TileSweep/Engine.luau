local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Library = require(script.Parent.Library)
local Signal = require(script.Parent.Signal)

local Easing = Library.Easing
local Patterns = Library.Patterns
local Styles = Library.Styles

local Engine = {}

local Grid = {}

local FALLBACK_VIEWPORT = Vector2.new(1920, 1080)
local DEFAULT_REFERENCE = Vector2.new(1920, 1080)

function Grid.viewportSize()
	local camera = workspace.CurrentCamera
	if camera and camera.ViewportSize.X > 1 and camera.ViewportSize.Y > 1 then
		return camera.ViewportSize
	end
	return FALLBACK_VIEWPORT
end

function Grid.viewportScale(viewport, options)
	local reference = options.ReferenceViewport or DEFAULT_REFERENCE
	local areaRatio = (viewport.X / math.max(reference.X, 1)) * (viewport.Y / math.max(reference.Y, 1))
	local scale = math.sqrt(math.max(areaRatio, 1e-6))
	return math.clamp(scale, options.MinTileScale or 0.3, options.MaxTileScale or 2.5)
end

function Grid.tileSize(viewport, options)
	local requestedSize = math.max(options.TileSize or 72, 1)

	if options.TileScaleMode == "Fixed" then
		return requestedSize
	end

	local scaledSize = requestedSize * Grid.viewportScale(viewport, options)
	return math.clamp(scaledSize, options.MinTileSize or 8, options.MaxTileSize or 1024)
end

function Grid.compute(viewport, options)
	local tileSize = Grid.tileSize(viewport, options)
	local padding = math.max(options.Overscan or 0, 0) * tileSize
	local width = math.max(viewport.X, 1) + padding * 2
	local height = math.max(viewport.Y, 1) + padding * 2

	local columns = math.max(1, math.floor(options.Columns or math.ceil(width / tileSize)))
	local rows = math.max(1, math.floor(options.Rows or math.ceil(height / tileSize)))

	local tileBudget = math.max(1, options.MaxTiles or 4096)
	if columns * rows > tileBudget then
		local shrink = math.sqrt(columns * rows / tileBudget)
		columns = math.max(1, math.floor(columns / shrink))
		rows = math.max(1, math.floor(rows / shrink))
	end

	local bleed = options.Bleed or 1
	local cells = table.create(columns * rows)
	local cellIndex = 0

	for row = 0, rows - 1 do
		for column = 0, columns - 1 do
			cellIndex += 1
			local centerX = (column + 0.5) / columns
			local centerY = (row + 0.5) / rows
			cells[cellIndex] = {
				Index = cellIndex,
				Column = column,
				Row = row,
				X = centerX,
				Y = centerY,
				Position = UDim2.fromScale(centerX, centerY),
				Size = UDim2.new(1 / columns, bleed, 1 / rows, bleed),
			}
		end
	end

	return {
		Columns = columns,
		Rows = rows,
		Cells = cells,
		TileSize = tileSize,
		Width = width,
		Height = height,
		Padding = padding,
		Viewport = viewport,
		Aspect = width / height,
	}
end

function Grid.signature(grid)
	return string.format("%dx%d", grid.Columns, grid.Rows)
end

local Plan = {}

function Plan.build(grid, tileFrames, options)
	local pattern = Patterns.get(options.Pattern)
	local cells = grid.Cells
	local tiles = table.create(#cells)
	local lowestWeight, highestWeight = math.huge, -math.huge

	for index, cell in cells do
		local weight = pattern(cell, grid, options)
		if type(weight) ~= "number" or weight ~= weight then
			weight = 0
		end

		tiles[index] = {
			Cell = cell,
			Frame = tileFrames[index],
			Weight = weight,
		}

		if weight < lowestWeight then
			lowestWeight = weight
		end
		if weight > highestWeight then
			highestWeight = weight
		end
	end

	local weightSpread = highestWeight - lowestWeight
	local shouldNormalize = options.Normalize ~= false and weightSpread > 1e-6
	local jitterAmount = math.max(options.Jitter or 0, 0)
	if jitterAmount ~= jitterAmount then
		jitterAmount = 0
	end

	local jitterSource = jitterAmount > 0 and Random.new(math.floor(options.Seed or os.clock() * 1e6)) or nil
	local stagger = math.max(options.Stagger or 0, 0)

	for _, tile in tiles do
		local weight = shouldNormalize and (tile.Weight - lowestWeight) / weightSpread
			or math.clamp(tile.Weight, 0, 1)

		if options.Invert then
			weight = 1 - weight
		end

		if jitterSource then
			weight = math.clamp(weight + (jitterSource:NextNumber() * 2 - 1) * jitterAmount, 0, 1)
		end

		tile.Delay = weight * stagger
	end

	table.sort(tiles, function(left, right)
		return left.Delay < right.Delay
	end)

	return {
		Tiles = tiles,
		Grid = grid,
		Options = options,
		TotalDuration = stagger + math.max(options.Duration or 0, 0),
	}
end

local Renderer = {}
Renderer.__index = Renderer

local function resolveGuiParent(options)
	if typeof(options.Parent) == "Instance" then
		return options.Parent
	end

	local player = Players.LocalPlayer
	if not player then
		error("TileSweep renders on the client only (Players.LocalPlayer is nil). Pass a Parent option to host it elsewhere.", 0)
	end

	return player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")
end

local function createDefaultTile(options)
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = options.Color
	frame.BackgroundTransparency = options.Transparency
	frame.ZIndex = options.ZIndex
	return frame
end

function Renderer.new()
	return setmetatable({
		ViewportChanged = Signal.new(),
		_tileFrames = {},
		_grid = nil,
		_gridSignature = nil,
		_appearanceSignature = nil,
	}, Renderer)
end

function Renderer:_describeAppearance(options)
	return table.concat({
		tostring(options.Color),
		tostring(options.Transparency),
		tostring(options.CornerRadius),
		tostring(options.ZIndex),
		tostring(options.TileTemplate),
		tostring(options.TileFactory),
	}, "|")
end

function Renderer:_createTile(options, index)
	local frame

	if type(options.TileFactory) == "function" then
		frame = options.TileFactory(index, options)
	elseif typeof(options.TileTemplate) == "Instance" then
		frame = options.TileTemplate:Clone()
	else
		frame = createDefaultTile(options)
	end

	if typeof(frame) ~= "Instance" or not frame:IsA("GuiObject") then
		error("TileSweep: TileFactory and TileTemplate must produce a GuiObject, got " .. typeof(frame), 0)
	end

	frame.Name = "Tile"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)

	local cornerRadius = options.CornerRadius or 0
	if cornerRadius > 0 and not frame:FindFirstChildOfClass("UICorner") then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, cornerRadius)
		corner.Parent = frame
	end

	frame.Parent = self._container
	return frame
end

function Renderer:_watchViewport()
	local camera = workspace.CurrentCamera
	if not camera or self._watchedCamera == camera then
		return
	end

	if self._viewportConnection then
		self._viewportConnection:Disconnect()
	end

	self._watchedCamera = camera
	self._viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		self.ViewportChanged:Fire(camera.ViewportSize)
	end)
end

function Renderer:_forgetGui(gui)
	if self._gui ~= gui then
		return
	end

	self._gui = nil
	self._container = nil
	table.clear(self._tileFrames)
	self._grid = nil
	self._gridSignature = nil
	self._appearanceSignature = nil
end

function Renderer:_ensureGui(options, isRetry)
	local parent = resolveGuiParent(options)

	if not self._gui then
		local gui = Instance.new("ScreenGui")
		gui.ResetOnSpawn = false
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.AutoLocalize = false
		gui.Enabled = false

		local container = Instance.new("Frame")
		container.Name = "Tiles"
		container.AnchorPoint = Vector2.new(0.5, 0.5)
		container.Position = UDim2.fromScale(0.5, 0.5)
		container.BackgroundTransparency = 1
		container.BorderSizePixel = 0
		container.Parent = gui

		gui.Destroying:Connect(function()
			self:_forgetGui(gui)
		end)

		self._gui = gui
		self._container = container
	end

	local applied = pcall(function()
		self._gui.Name = options.GuiName or "TileSweep"
		self._gui.DisplayOrder = options.DisplayOrder or 0
		self._gui.IgnoreGuiInset = options.IgnoreGuiInset ~= false
		self._container.Active = options.Modal ~= false

		if parent and self._gui.Parent ~= parent then
			self._gui.Parent = parent
		end
	end)

	if applied then
		return self._gui
	end

	if isRetry then
		error("TileSweep: unable to prepare its ScreenGui under " .. parent:GetFullName(), 0)
	end

	self:_forgetGui(self._gui)
	return self:_ensureGui(options, true)
end

function Renderer:_syncTiles(grid, options)
	local frames = self._tileFrames
	local requiredCount = #grid.Cells
	local appearance = self:_describeAppearance(options)

	if appearance ~= self._appearanceSignature then
		for _, frame in frames do
			frame:Destroy()
		end
		table.clear(frames)
		self._appearanceSignature = appearance
		self._gridSignature = nil
	end

	for index = #frames + 1, requiredCount do
		frames[index] = self:_createTile(options, index)
	end

	for index = #frames, requiredCount + 1, -1 do
		frames[index]:Destroy()
		frames[index] = nil
	end

	self._gridSignature = Grid.signature(grid)
	return frames
end

function Renderer:Prepare(options)
	self:_ensureGui(options)
	self:_watchViewport()

	local grid = Grid.compute(Grid.viewportSize(), options)
	self._grid = grid
	self._container.Size = UDim2.new(1, grid.Padding * 2, 1, grid.Padding * 2)

	return grid, self:_syncTiles(grid, options)
end

function Renderer:Refresh()
	self._gridSignature = nil
	self._appearanceSignature = nil
	return self
end

function Renderer:SetVisible(visible)
	if self._gui then
		self._gui.Enabled = visible and true or false
	end
	return self
end

function Renderer:IsVisible()
	return self._gui ~= nil and self._gui.Enabled
end

function Renderer:GetGui()
	return self._gui
end

function Renderer:GetContainer()
	return self._container
end

function Renderer:GetGrid()
	return self._grid
end

function Renderer:GetTiles()
	return self._tileFrames
end

function Renderer:Destroy()
	if self._viewportConnection then
		self._viewportConnection:Disconnect()
		self._viewportConnection = nil
	end

	self.ViewportChanged:Destroy()

	local gui = self._gui
	self:_forgetGui(gui)
	if gui then
		gui:Destroy()
	end

	self._watchedCamera = nil
end

local Playback = {}
Playback.__index = Playback

local MINIMUM_TILE_DURATION = 1 / 240

function Playback.new(plan, options, isCovering)
	return setmetatable({
		Completed = Signal.new(),
		Plan = plan,
		Options = options,
		IsCovering = isCovering ~= false,
		Elapsed = 0,
		_easing = Easing.get(options.Easing, options.EasingDirection),
		_style = Styles.get(options.Style),
		_tileDuration = math.max(options.Duration or 0, MINIMUM_TILE_DURATION),
		_firstUnfinished = 1,
		_lastStarted = 0,
		_started = false,
		_running = false,
		_finished = false,
		_cancelled = false,
	}, Playback)
end

function Playback:_timeScale()
	local timeScale = self.Options.TimeScale or 1
	if timeScale ~= timeScale or timeScale < 0 then
		return 1
	end
	return timeScale
end

function Playback:Reset()
	for _, tile in self.Plan.Tiles do
		Styles.reset(tile.Frame, tile.Cell, self.Options)
	end
	return self
end

function Playback:_applyTile(tile, tileProgress)
	local eased = self._easing(tileProgress)
	local coverage = self.IsCovering and eased or 1 - eased
	self._style(tile.Frame, coverage, tile.Cell, self.Options)
end

function Playback:Fill(coverage)
	for _, tile in self.Plan.Tiles do
		self._style(tile.Frame, coverage, tile.Cell, self.Options)
	end
	return self
end

function Playback:Seek(progress)
	local tiles = self.Plan.Tiles
	self.Elapsed = math.clamp(progress, 0, 1) * self.Plan.TotalDuration
	self._firstUnfinished = 1
	self._lastStarted = 0

	for index, tile in tiles do
		local tileProgress = math.clamp((self.Elapsed - tile.Delay) / self._tileDuration, 0, 1)
		self:_applyTile(tile, tileProgress)

		if self.Elapsed >= tile.Delay then
			self._lastStarted = index
		end
		if tileProgress >= 1 then
			self._firstUnfinished = index + 1
		end
	end

	return self
end

function Playback:Step(deltaTime)
	if not self._running or deltaTime ~= deltaTime then
		return self
	end

	local tiles = self.Plan.Tiles
	local tileCount = #tiles
	self.Elapsed += deltaTime

	while self._lastStarted < tileCount and tiles[self._lastStarted + 1].Delay <= self.Elapsed do
		self._lastStarted += 1
	end

	for index = self._firstUnfinished, self._lastStarted do
		local tile = tiles[index]
		self:_applyTile(tile, math.clamp((self.Elapsed - tile.Delay) / self._tileDuration, 0, 1))
	end

	while
		self._firstUnfinished <= self._lastStarted
		and self.Elapsed - tiles[self._firstUnfinished].Delay >= self._tileDuration
	do
		self._firstUnfinished += 1
	end

	if self._firstUnfinished > tileCount then
		self:_finish()
	end

	return self
end

function Playback:Start()
	if self._running or self._finished or self._cancelled then
		return self
	end

	self._running = true
	self._started = true
	self.Elapsed = 0
	self._firstUnfinished = 1
	self._lastStarted = 0

	self:Reset()
	self:Fill(self.IsCovering and 0 or 1)

	self._connection = RunService.RenderStepped:Connect(function(deltaTime)
		self:Step(deltaTime * self:_timeScale())
	end)

	return self
end

function Playback:_stop()
	self._running = false
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
end

function Playback:_finish()
	self:_stop()
	self._finished = true
	self.Completed:Fire(true)
end

function Playback:Cancel()
	if self._finished or self._cancelled then
		return self
	end

	self:_stop()
	self._cancelled = true
	self.Completed:Fire(false)
	return self
end

function Playback:Await()
	if self._finished or self._cancelled or not self._started then
		return self
	end
	self.Completed:Wait()
	return self
end

function Playback:GetProgress()
	local total = self.Plan.TotalDuration
	if total <= 0 then
		return 1
	end
	return math.clamp(self.Elapsed / total, 0, 1)
end

function Playback:IsActive()
	return self._running
end

function Playback:IsFinished()
	return self._finished
end

function Playback:IsCancelled()
	return self._cancelled
end

function Playback:Destroy()
	self:_stop()
	self.Completed:Destroy()
end

Engine.Signal = Signal
Engine.Grid = Grid
Engine.Plan = Plan
Engine.Renderer = Renderer
Engine.Playback = Playback

return Engine
