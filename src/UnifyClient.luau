--!nonstrict

-- Variables
local Root = script.Parent.Parent

local Network = Root:WaitForChild("Network")

local OnRan = Instance.new("BindableEvent")
local Ran = false

-- Requires
local Promise = require("./Promise")

-- Module
local UnifyClient = {}

do
	UnifyClient.ClientModules = {}
	UnifyClient.ServerModules = {}
end

do
	local function onRemoteAdded(remote: RemoteEvent | RemoteFunction)
		if not remote:IsA("RemoteEvent") and not remote:IsA("RemoteFunction") then
			return
		end

		if not remote.Parent then
			return
		end

		local moduleName = remote.Parent.Name
		local serverModule = UnifyClient.ServerModules[moduleName]

		if remote:IsA("RemoteEvent") then
			serverModule[remote.Name] = {
				Connect = function(_: any, callback: (...any) -> ...any)
					return remote.OnClientEvent:Connect(callback)
				end,
				Once = function(_: any, callback: (...any) -> ...any)
					return remote.OnClientEvent:Once(callback)
				end,
				Wait = function()
					return remote.OnClientEvent:Wait()
				end,
				Fire = function(_: any, ...: any)
					return remote:FireServer(...)
				end,
			}
		else
			serverModule[remote.Name] = function(_: any, ...: any)
				local args = { ... }

				return Promise.new(function(resolve, reject)
					local success, response = pcall(function()
						return { remote:InvokeServer(table.unpack(args)) }
					end)

					if success then
						resolve(table.unpack(response))
					else
						reject(response)
					end
				end)
			end
		end
	end

	local function onModuleNetworkAdded(moduleNetwork: Folder)
		UnifyClient.ServerModules[moduleNetwork.Name] = {}

		for _, remote in moduleNetwork:GetChildren() do
			task.spawn(onRemoteAdded, remote)
		end

		moduleNetwork.ChildAdded:Connect(function(child: Instance)
			if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
				task.spawn(onRemoteAdded, child)
			end
		end)
	end

	for _, moduleNetwork in Network:GetChildren() do
		task.spawn(onModuleNetworkAdded, moduleNetwork)
	end

	Network.ChildAdded:Connect(onModuleNetworkAdded)
end

function UnifyClient:Get(module: string, timeout: number?)
	local start = os.clock()

	repeat
		task.wait()
	until (self.ServerModules[module] or self.ClientModules[module]) or os.clock() - start > (timeout or 5)

	return self.ServerModules[module] or self.ClientModules[module]
end

function UnifyClient:OnRan()
	if not Ran then
		return Promise.fromEvent(OnRan.Event)
	else
		return Promise.resolve()
	end
end

function UnifyClient:Add(path: Instance)
	return Promise.new(function(resolve, reject)
		local success, response = pcall(function()
			for _, module in path:GetDescendants() do
				task.spawn(function()
					if not module:IsA("ModuleScript") then
						return
					end

					self.ClientModules[module.Name] = require(module)
				end)
			end

			return self.ClientModules
		end)

		if success then
			resolve(response)
		else
			reject(response)
		end

		OnRan:Fire()
		Ran = true
	end):catch(error)
end

return UnifyClient
