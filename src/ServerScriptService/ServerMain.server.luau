--!strict
-- ServerMain.server.luau
-- Punto de entrada único del Servidor (Server Bootstrap) para UMBRA.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ServicesFolder = ServerScriptService:WaitForChild("Services")
local GameManager = require(ServicesFolder:WaitForChild("GameManager") :: ModuleScript)
local EnemyService = require(ServicesFolder:WaitForChild("EnemyService") :: ModuleScript)
local SpawnerService = require(ServicesFolder:WaitForChild("SpawnerService") :: ModuleScript)

print("=========================================")
print("        UMBRA - SERVIDOR INICIADO        ")
print("=========================================")

-- 1. Inicializar GameManager
GameManager.Iniciar()

-- 2. Inicializar subsistemas de horda
EnemyService.Iniciar()
SpawnerService.Iniciar(EnemyService)

-- 3. Gestión de ciclo de vida de jugadores
Players.PlayerAdded:Connect(GameManager.OnPlayerAdded)
Players.PlayerRemoving:Connect(GameManager.OnPlayerRemoving)

for _, player in Players:GetPlayers() do
	task.spawn(GameManager.OnPlayerAdded, player)
end
