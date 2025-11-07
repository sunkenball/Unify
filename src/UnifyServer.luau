--!nonstrict
local Players = game:GetService("Players")

-- Variables
local Root = script.Parent.Parent

local Network = Instance.new("Folder")

local OnRan = Instance.new("BindableEvent")
local Ran = false

-- Requires
local Promise = require("./Promise")

-- Module
local UnifyServer = {}

do
	UnifyServer.ServerModules = {}

	Network.Name = "Network"
	Network.Parent = Root
end

function UnifyServer:Get(module: string, timeout: number?)
	local start = os.clock()

	repeat
		task.wait()
	until self.ServerModules[module] or os.clock() - start > (timeout or 5)

	return self.ServerModules[module]
end

function UnifyServer:OnRan()
	if not Ran then
		return Promise.fromEvent(OnRan.Event)
	else
		return Promise.resolve()
	end
end

function UnifyServer:Add(path: Instance)
	return Promise.new(function(resolve, reject)
		local moduleCount = 0

		local success, response = pcall(function()
			for _, module in path:GetDescendants() do
				task.spawn(function()
					if not module:IsA("ModuleScript") then
						return
					end

					moduleCount += 1

					self.ServerModules[module.Name] = require(module)
				end)
			end

			return self.ServerModules
		end)

		if success then
			local count

			repeat
				count = 0

				for _ in self.ServerModules do
					count += 1
				end

				task.wait()
			until count == moduleCount

			self:ProcessModules()

			resolve(response)
		else
			reject(response)
		end

		OnRan:Fire()
		Ran = true
	end):catch(error)
end

function UnifyServer:ProcessModules()
	local serverModules = self.ServerModules

	for moduleName, module in serverModules do
		local clientTable = module.Client

		if not clientTable then
			continue
		end

		if not clientTable.Server then
			clientTable.Server = module
		end

		local moduleNetwork = Instance.new("Folder")

		moduleNetwork.Name = moduleName

		moduleNetwork.Parent = Network

		local remotes = {}

		for methodName, callback in clientTable do
			if type(callback) == "function" then
				local argumentCount = debug.info(callback, "a")
				local isMethod = argumentCount > 0

				if isMethod then
					local remoteFunction = Instance.new("RemoteFunction")

					remoteFunction.Name = methodName

					local debounces = {}

					remoteFunction.OnServerInvoke = function(player: Player, ...: any)
						if debounces[player] then
							return
						end

						return callback(clientTable, player, ...)
					end

					remotes[methodName] = remoteFunction

					clientTable[methodName] = setmetatable({
						Debounce = function(_: any, player: Player, time: number)
							debounces[player] = true

							task.delay(time, function()
								debounces[player] = nil
							end)
						end,
					}, {
						__index = function(_, key: string)
							return remoteFunction[key]
						end,
					})
				else
					local remoteEvent = Instance.new("RemoteEvent")

					remoteEvent.Name = methodName

					local debounces = {}

					remoteEvent.OnServerEvent:Connect(function(player: Player, ...)
						if debounces[player] then
							return
						end

						callback(player, ...)
					end)

					clientTable[methodName] = {
						Fire = function(_: any, player: Player | { Player }, ...: any)
							if type(player) == "table" then
								local players = player

								for _, _player in players do
									remoteEvent:FireClient(_player, ...)
								end
							else
								remoteEvent:FireClient(player, ...)
							end

							return
						end,
						FireAll = function(_: any, ...: any)
							return remoteEvent:FireAllClients(...)
						end,
						FireAllExcept = function(_: any, excluded: { Player }, ...: any)
							for _, player in Players:GetPlayers() do
								if table.find(excluded, player) then
									continue
								end

								remoteEvent:FireClient(player, ...)
							end
						end,
						Connect = function(_: any, callback: (...any) -> ...any)
							return remoteEvent.OnServerEvent:Connect(callback)
						end,
						Once = function(_: any, callback: (...any) -> ...any)
							return remoteEvent.OnServerEvent:Once(callback)
						end,
						Wait = function()
							return remoteEvent.OnServerEvent:Wait()
						end,
						Debounce = function(_: any, player: Player, time: number)
							debounces[player] = true

							task.delay(time, function()
								debounces[player] = nil
							end)
						end,
					}

					remotes[methodName] = remoteEvent
				end
			end
		end

		for name, remote in remotes do
			remote.Parent = moduleNetwork
		end
	end
end

return UnifyServer
