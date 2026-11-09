--!strict
-- ServerMain.server.luau
-- Punto de entrada único del Servidor (Server Bootstrap) para UMBRA: La última luz.
-- Responsabilidad: Orquestar secuencialmente el ciclo de vida, hordas, spawner y combate automático.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

print("=========================================")
print("      UMBRA — SERVIDOR INICIANDO         ")
print("=========================================")

local ServicesFolder = ServerScriptService:WaitForChild("Services")

-- Función protegida de inicialización de servicios
local function inicializarServicio(nombre: string, modulo: ModuleScript, ...: any): (boolean, any)
	local exitoCarga, servicio = pcall(require, modulo)
	if not exitoCarga then
		warn(string.format("[ServerMain] ERROR CRÍTICO al cargar el módulo '%s': %s", nombre, tostring(servicio)))
		return false, nil
	end

	if typeof(servicio) == "table" and typeof(servicio.Iniciar) == "function" then
		local exitoInit, err = pcall(servicio.Iniciar, ...)
		if not exitoInit then
			warn(string.format("[ServerMain] ERROR CRÍTICO al ejecutar Iniciar() en '%s': %s", nombre, tostring(err)))
			return false, servicio
		end
	end

	print(string.format("[ServerMain] Servicio '%s' inicializado con éxito.", nombre))
	return true, servicio
end

-- 1. Inicializar GameManager (Cerebro de la sesión)
local gmModulo = ServicesFolder:WaitForChild("GameManager") :: ModuleScript
local exitoGM, GameManager = inicializarServicio("GameManager", gmModulo)
if not exitoGM or not GameManager then
	error("[ServerMain] No fue posible inicializar GameManager. Deteniendo arranque.")
end

-- 2. Inicializar EnemyService (Simulación de Hordas)
local enemyModulo = ServicesFolder:WaitForChild("EnemyService") :: ModuleScript
local exitoEnemy, EnemyService = inicializarServicio("EnemyService", enemyModulo)

-- 3. Inicializar SpawnerService (Director de Oleadas perimetrales)
local spawnerModulo = ServicesFolder:WaitForChild("SpawnerService") :: ModuleScript
local exitoSpawner, SpawnerService = inicializarServicio("SpawnerService", spawnerModulo, EnemyService)

-- 4. Inicializar CombatService (Combate y Habilidades Automáticas)
local combatModulo = ServicesFolder:WaitForChild("CombatService") :: ModuleScript
local exitoCombat, CombatService = inicializarServicio("CombatService", combatModulo, EnemyService)

-- 5. Gestión del ciclo de vida de jugadores
local function registrarJugador(player: Player)
	local exitoGMPlayer, errGM = pcall(GameManager.OnPlayerAdded, player)
	if not exitoGMPlayer then
		warn(string.format("[ServerMain] Error al registrar GameManager para %s: %s", player.Name, tostring(errGM)))
	end

	if CombatService and typeof(CombatService.RegistrarJugador) == "function" then
		local exitoCombatReg, errCombat = pcall(CombatService.RegistrarJugador, player)
		if not exitoCombatReg then
			warn(string.format("[ServerMain] Error al registrar CombatService para %s: %s", player.Name, tostring(errCombat)))
		end
	end
end

local function desregistrarJugador(player: Player)
	if CombatService and typeof(CombatService.DesregistrarJugador) == "function" then
		pcall(CombatService.DesregistrarJugador, player)
	end

	pcall(GameManager.OnPlayerRemoving, player)
end

Players.PlayerAdded:Connect(registrarJugador)
Players.PlayerRemoving:Connect(desregistrarJugador)

for _, player in Players:GetPlayers() do
	task.spawn(registrarJugador, player)
end

print("=========================================")
print("  UMBRA — SERVIDOR ACTIVO CON COMBATE    ")
print("=========================================")
