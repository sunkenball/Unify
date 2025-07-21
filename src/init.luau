local RunService = game:GetService("RunService")

if RunService:IsServer() then
	return require(script.UnifyServer)
elseif RunService:IsClient() then
	return require(script.UnifyClient)
end
