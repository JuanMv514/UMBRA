--!strict
-- ServerMain.server.luau
-- Punto de entrada único del Servidor (Server Bootstrap) para UMBRA.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ServicesFolder = ServerScriptService:WaitForChild("Services")
local GameManager = require(ServicesFolder:WaitForChild("GameManager") :: ModuleScript)

print("=========================================")
print("        UMBRA - SERVIDOR INICIADO        ")
print("=========================================")

GameManager.Iniciar()

Players.PlayerAdded:Connect(GameManager.OnPlayerAdded)
Players.PlayerRemoving:Connect(GameManager.OnPlayerRemoving)

for _, player in Players:GetPlayers() do
	task.spawn(GameManager.OnPlayerAdded, player)
end
