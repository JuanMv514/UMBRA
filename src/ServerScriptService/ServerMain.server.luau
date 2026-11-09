--!strict
-- ServerMain.server.luau
-- Punto de entrada único del Servidor (Server Bootstrap) para UMBRA.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ServicesFolder = ServerScriptService:WaitForChild("Services")
local GameManager = require(ServicesFolder:WaitForChild("GameManager") :: ModuleScript)
local EnemyService = require(ServicesFolder:WaitForChild("EnemyService") :: ModuleScript)
local SpawnerService = require(ServicesFolder:WaitForChild("SpawnerService") :: ModuleScript)
local CombatService = require(ServicesFolder:WaitForChild("CombatService") :: ModuleScript)

print("=========================================")
print("        UMBRA - SERVIDOR INICIADO        ")
print("=========================================")

-- 1. Inicializar GameManager
GameManager.Iniciar()

-- 2. Inicializar subsistemas de horda y combate
EnemyService.Iniciar()
SpawnerService.Iniciar(EnemyService)
CombatService.Iniciar(EnemyService)

-- 3. Gestión de ciclo de vida de jugadores
local function onPlayerAdded(player: Player)
	GameManager.OnPlayerAdded(player)
	CombatService.RegistrarJugador(player)
end

local function onPlayerRemoving(player: Player)
	CombatService.DesregistrarJugador(player)
	GameManager.OnPlayerRemoving(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
