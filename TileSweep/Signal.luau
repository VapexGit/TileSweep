local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end

	self.Connected = false

	local connections = self._signal._connections
	local index = table.find(connections, self)
	if index then
		table.remove(connections, index)
	end
end

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({
		_connections = {},
		_waitingThreads = {},
	}, Signal)
end

function Signal:Connect(callback)
	local connection = setmetatable({
		Connected = true,
		_signal = self,
		_callback = callback,
	}, Connection)

	table.insert(self._connections, connection)
	return connection
end

function Signal:Once(callback)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function Signal:Wait()
	table.insert(self._waitingThreads, coroutine.running())
	return coroutine.yield()
end

function Signal:Fire(...)
	for _, connection in table.clone(self._connections) do
		if connection.Connected then
			task.spawn(connection._callback, ...)
		end
	end

	local waiting = self._waitingThreads
	self._waitingThreads = {}
	for _, thread in waiting do
		task.spawn(thread, ...)
	end
end

function Signal:Destroy()
	for _, connection in table.clone(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)

	local waiting = self._waitingThreads
	self._waitingThreads = {}
	for _, thread in waiting do
		task.spawn(thread)
	end
end

return Signal
