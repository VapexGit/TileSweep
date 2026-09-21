-- Tile Sweep
-- vapex0_ Discord
-- September 21, 2026
-- MIT licensed — Copyright (c) 2026 VapexGit (vapex0_)
-- https://github.com/VapexGit/TileSweep
-- https://create.roblox.com/store/asset/116996144631492/TileSweep


--[[
	USAGE EXAMPLE:

		local TileSweep = require(Location.TileSweep)
		local sweep = TileSweep.new({ TileSize = 64, Duration = 0.3, Stagger = 0.5 })

		sweep:Transition(0.35)              -- cover, hold, reveal
		sweep:Transition(function()         -- or run work while the screen is covered
			character:PivotTo(destination)
		end)

	API
		TileSweep.new(config?)                   -> sweep
		sweep:Cover(overrides?)                  -> Playback   tiles sweep in
		sweep:Reveal(overrides?)                 -> Playback   tiles sweep out
		sweep:Transition(whileCovered?, over?)   -> Sequence   seconds or a function
		sweep:Toggle(overrides?)                 -> Playback
		sweep:Snap(covered, overrides?)          -> sweep      jump straight to a state
		sweep:Scrub(overrides?)                  -> Playback   drive it yourself via :Seek(0..1)
		sweep:Configure(config) / :Cancel() / :Refresh() / :Destroy()

		Playback and Sequence both expose :Await(), :Cancel() and .Completed,
		so nothing yields unless you ask it to.

	STATE
		sweep.State   Hidden, Covering, Covered, Revealing, Interrupted
		signals       StateChanged, Started, Covered, Revealed, Completed, ViewportChanged
		readers       GetState GetPhase GetProgress GetOptions GetGrid GetTiles GetGui
		              GetContainer GetPlayback GetSequence GetRenderer IsCovered IsBusy

	CONFIG
		Config.Defaults -> the table passed to .new -> the overrides passed to a call,
		each layer beating the one before it. Any layer may carry Cover = {...} or
		Reveal = {...} to apply to just that phase.

	EXTENDING
		TileSweep.Patterns.register(name, function(cell, grid, options) return n end)
		TileSweep.Styles.register(name, function(frame, coverage, cell, options) end)
		TileSweep.Easing.register(name, function(alpha) return n end)

]]

local Config = require(script.Config)
local Engine = require(script.Engine)
local Library = require(script.Library)
local Signal = require(script.Signal)

local Renderer = Engine.Renderer
local Playback = Engine.Playback
local Plan = Engine.Plan

local Phase = Config.Phase
local States = Config.State

local Sequence = {}
Sequence.__index = Sequence

function Sequence.run(body)
	local self = setmetatable({
		Completed = Signal.new(),
		_cancelled = false,
		_finished = false,
		_activePlayback = nil,
	}, Sequence)

	task.spawn(function()
		local succeeded, failure = pcall(body, self)

		if not self._finished then
			self._finished = true
			self.Completed:Fire(not self._cancelled)
		end

		if not succeeded then
			task.spawn(error, failure)
		end
	end)

	return self
end

function Sequence:Track(playback)
	self._activePlayback = playback
	return playback
end

function Sequence:Cancel()
	if self._finished then
		return self
	end

	self._cancelled = true
	self._finished = true

	local playback = self._activePlayback
	self._activePlayback = nil
	if playback then
		playback:Cancel()
	end

	self.Completed:Fire(false)
	return self
end

function Sequence:Await()
	if self._finished then
		return self
	end
	self.Completed:Wait()
	return self
end

function Sequence:IsCancelled()
	return self._cancelled
end

function Sequence:IsActive()
	return not self._finished
end

function Sequence:Destroy()
	self:Cancel()
	self.Completed:Destroy()
end

local TileSweep = {}
TileSweep.__index = TileSweep

TileSweep.Config = Config
TileSweep.Engine = Engine
TileSweep.Library = Library
TileSweep.Easing = Library.Easing
TileSweep.Patterns = Library.Patterns
TileSweep.Styles = Library.Styles
TileSweep.Signal = Signal
TileSweep.Sequence = Sequence
TileSweep.Phase = Phase
TileSweep.States = States

function TileSweep.new(config)
	local self = setmetatable({
		State = States.Hidden,
		Started = Signal.new(),
		Covered = Signal.new(),
		Revealed = Signal.new(),
		Completed = Signal.new(),
		StateChanged = Signal.new(),
		ViewportChanged = Signal.new(),
		_config = config or {},
		_renderer = Renderer.new(),
		_options = nil,
		_lastOverrides = nil,
		_playback = nil,
		_sequence = nil,
		_destroyed = false,
	}, TileSweep)

	self._viewportConnection = self._renderer.ViewportChanged:Connect(function(viewport)
		self.ViewportChanged:Fire(viewport)
		self:_rebuildWhileCovered()
	end)

	return self
end

function TileSweep:_rebuildWhileCovered()
	local options = self._options
	if not options or options.AutoRefresh == false then
		return
	end

	if self._destroyed or self.State ~= States.Covered or self:IsBusy() then
		return
	end

	self:_snapTo(true, self._lastOverrides, true)
end

function TileSweep:_setState(state)
	if self.State == state then
		return self
	end

	local previous = self.State
	self.State = state
	self.StateChanged:Fire(state, previous)
	return self
end

function TileSweep:Configure(config)
	if type(config) == "table" then
		for key, value in config do
			self._config[key] = value
		end
	end
	return self
end

function TileSweep:Resolve(phase, overrides)
	return Config.resolve(phase or Phase.Cover, self._config, overrides)
end

function TileSweep:_build(phase, overrides)
	if self._destroyed then
		error("TileSweep: this sweep has been destroyed", 3)
	end

	local options = self:Resolve(phase, overrides)
	local grid, tileFrames = self._renderer:Prepare(options)

	self._options = options
	self._lastOverrides = overrides

	return Plan.build(grid, tileFrames, options), options
end

function TileSweep:_cancelPlayback()
	local playback = self._playback
	self._playback = nil
	if playback then
		playback:Cancel()
	end
	return self
end

function TileSweep:_cancelSequence()
	local sequence = self._sequence
	self._sequence = nil
	if sequence then
		sequence:Cancel()
	end
	return self
end

function TileSweep:_snapTo(covered, overrides, silent)
	local phase = covered and Phase.Cover or Phase.Reveal
	local plan, options = self:_build(phase, overrides)
	local playback = Playback.new(plan, options, true)

	playback:Reset()
	playback:Fill(covered and 1 or 0)

	self._renderer:SetVisible(covered)
	self:_setState(covered and States.Covered or States.Hidden)

	if not silent then
		if covered then
			self.Covered:Fire(options)
		else
			self.Revealed:Fire(options)
		end
	end

	return self
end

function TileSweep:_play(phase, overrides, insideSequence)
	if not insideSequence then
		self:_cancelSequence()
	end

	self:_cancelPlayback()

	local plan, options = self:_build(phase, overrides)
	local isCovering = phase == Phase.Cover
	local playback = Playback.new(plan, options, isCovering)

	self._playback = playback
	self._renderer:SetVisible(true)

	playback.Completed:Connect(function(finished)
		if self._playback == playback then
			self._playback = nil
		end

		if not finished then
			return
		end

		if isCovering then
			self:_setState(States.Covered)
			self.Covered:Fire(options)
		else
			self._renderer:SetVisible(false)
			self:_setState(States.Hidden)
			self.Revealed:Fire(options)
		end

		self.Completed:Fire(phase, options)
	end)

	self:_setState(isCovering and States.Covering or States.Revealing)
	self.Started:Fire(phase, options)
	playback:Start()

	return playback
end

function TileSweep:Cover(overrides)
	return self:_play(Phase.Cover, overrides, false)
end

function TileSweep:Reveal(overrides)
	return self:_play(Phase.Reveal, overrides, false)
end

function TileSweep:Toggle(overrides)
	if self.State == States.Covered or self.State == States.Covering then
		return self:Reveal(overrides)
	end
	return self:Cover(overrides)
end

function TileSweep:Transition(whileCovered, overrides)
	self:_cancelSequence()

	local sequence = Sequence.run(function(scope)
		scope:Track(self:_play(Phase.Cover, overrides, true)):Await()
		if scope:IsCancelled() or self.State ~= States.Covered then
			return
		end

		local succeeded, failure = true, nil
		if type(whileCovered) == "number" then
			task.wait(whileCovered)
		elseif type(whileCovered) == "function" then
			succeeded, failure = pcall(whileCovered, self)
		end

		if not scope:IsCancelled() then
			scope:Track(self:_play(Phase.Reveal, overrides, true)):Await()
		end

		if not succeeded then
			task.spawn(error, failure)
		end
	end)

	self._sequence = sequence
	return sequence
end

function TileSweep:Snap(covered, overrides)
	self:Cancel()
	return self:_snapTo(covered and true or false, overrides, false)
end

function TileSweep:Scrub(overrides)
	self:Cancel()

	local plan, options = self:_build(Phase.Cover, overrides)
	local playback = Playback.new(plan, options, true)

	playback:Reset()
	playback:Seek(0)

	self._renderer:SetVisible(true)
	return playback
end

function TileSweep:Cancel()
	local wasRunning = self:IsBusy()

	self:_cancelSequence()
	self:_cancelPlayback()

	if wasRunning then
		self:_setState(States.Interrupted)
	end

	return self
end

function TileSweep:Refresh()
	self._renderer:Refresh()
	return self
end

function TileSweep:IsCovered()
	return self.State == States.Covered
end

function TileSweep:IsBusy()
	if self._sequence and self._sequence:IsActive() then
		return true
	end
	return self._playback ~= nil and self._playback:IsActive()
end

function TileSweep:IsDestroyed()
	return self._destroyed
end

function TileSweep:GetState()
	return self.State
end

function TileSweep:GetPhase()
	local playback = self._playback
	if not playback then
		return nil
	end
	return playback.IsCovering and Phase.Cover or Phase.Reveal
end

function TileSweep:GetProgress()
	local playback = self._playback
	if not playback then
		return self.State == States.Covered and 1 or 0
	end
	return playback:GetProgress()
end

function TileSweep:GetPlayback()
	return self._playback
end

function TileSweep:GetSequence()
	return self._sequence
end

function TileSweep:GetOptions()
	return self._options
end

function TileSweep:GetGrid()
	return self._renderer:GetGrid()
end

function TileSweep:GetTiles()
	return self._renderer:GetTiles()
end

function TileSweep:GetGui()
	return self._renderer:GetGui()
end

function TileSweep:GetContainer()
	return self._renderer:GetContainer()
end

function TileSweep:GetRenderer()
	return self._renderer
end

function TileSweep:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true

	self:Cancel()

	if self._viewportConnection then
		self._viewportConnection:Disconnect()
		self._viewportConnection = nil
	end

	self._renderer:Destroy()
	self.Started:Destroy()
	self.Covered:Destroy()
	self.Revealed:Destroy()
	self.Completed:Destroy()
	self.StateChanged:Destroy()
	self.ViewportChanged:Destroy()
end

return TileSweep
