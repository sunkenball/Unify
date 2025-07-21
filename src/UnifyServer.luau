-- Variables
local Root = script.Parent.Parent

local Network = Instance.new("Folder")

-- Requires
local Promise = require(Root:WaitForChild("Promise"))

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
	until (self.ServerModules[module] or self.ClientModules[module]) or os.clock() - start > (timeout or 5)

	return self.ServerModules[module] or self.ClientModules[module]
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
	end)
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

					remoteFunction.OnServerInvoke = function(player: Player, ...: any)
						return callback(clientTable, player, ...)
					end

					remotes[methodName] = remoteFunction
				else
					local remoteEvent = Instance.new("RemoteEvent")

					remoteEvent.Name = methodName

					remoteEvent.OnServerEvent:Connect(function(player: Player, ...)
						callback(player, ...)
					end)

					clientTable[methodName] = {
						Fire = function(_: any, player: Player, ...: any)
							return remoteEvent:FireClient(player, ...)
						end,
						FireAll = function(_: any, ...: any)
							return remoteEvent:FireAllClients(...)
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
