--!strict
-- ServerMain.server.luau
-- Punto de entrada único del Servidor (Server Bootstrap) para UMBRA: La última luz.
-- Responsabilidad: Reconocer autoritativamente si el servidor está ejecutando el LOBBY o la EXPEDICIÓN,
-- e inicializar únicamente los servicios correspondientes a ese entorno.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ConfigFolder = ReplicatedStorage:WaitForChild("Config")
local PlacesConfig = require(ConfigFolder:WaitForChild("PlacesConfig") :: ModuleScript)

print("=========================================")
print(string.format("   UMBRA SERVIDOR — INICIANDO (%s)   ", if PlacesConfig.EsLobby() then "LOBBY" else "EXPEDICIÓN"))
print(string.format("   PlaceId actual: %d                   ", game.PlaceId))
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

-- 1. Inicializar GameManager (Cerebro de la sesión, presente en ambos Places)
local gmModulo = ServicesFolder:WaitForChild("GameManager") :: ModuleScript
local exitoGM, GameManager = inicializarServicio("GameManager", gmModulo)
if not exitoGM or not GameManager then
	error("[ServerMain] No fue posible inicializar GameManager. Deteniendo arranque.")
end

local EnemyService = nil :: any
local SpawnerService = nil :: any
local CombatService = nil :: any
local MatchmakingService = nil :: any

if PlacesConfig.EsLobby() then
	-- =========================================================================
	-- PLACE 1: LOBBY (Santuario del Último Resplandor)
	-- No se cargan enemigos, ni oleadas, ni combate automático.
	-- Solo se inicia el portal de emparejamiento.
	-- =========================================================================
	print("[ServerMain] Configurando entorno de LOBBY: Hordas, Spawner y Combate DESHABILITADOS.")

	local matchmakingModulo = ServicesFolder:WaitForChild("MatchmakingService") :: ModuleScript
	local exitoMM, mmInst = inicializarServicio("MatchmakingService", matchmakingModulo, GameManager)
	MatchmakingService = mmInst

else
	-- =========================================================================
	-- PLACE 2: EXPEDICIÓN (Arena de Supervivencia)
	-- Se cargan e inician los sistemas de combate, oleadas y hordas.
	-- No se inicia el sistema de emparejamiento.
	-- =========================================================================
	print("[ServerMain] Configurando entorno de EXPEDICIÓN: Hordas, Spawner y Combate HABILITADOS.")

	local enemyModulo = ServicesFolder:WaitForChild("EnemyService") :: ModuleScript
	local _, enemyInst = inicializarServicio("EnemyService", enemyModulo)
	EnemyService = enemyInst

	local spawnerModulo = ServicesFolder:WaitForChild("SpawnerService") :: ModuleScript
	local _, spawnerInst = inicializarServicio("SpawnerService", spawnerModulo, EnemyService, GameManager)
	SpawnerService = spawnerInst

	local combatModulo = ServicesFolder:WaitForChild("CombatService") :: ModuleScript
	local _, combatInst = inicializarServicio("CombatService", combatModulo, EnemyService)
	CombatService = combatInst

	if GameManager.VincularServicios then
		GameManager.VincularServicios(SpawnerService, EnemyService, CombatService)
	end
end

-- 2. Gestión del ciclo de vida de jugadores
local function registrarJugador(player: Player)
	local exitoGMPlayer, errGM = pcall(GameManager.OnPlayerAdded, player)
	if not exitoGMPlayer then
		warn(string.format("[ServerMain] Error al registrar GameManager para %s: %s", player.Name, tostring(errGM)))
	end

	-- Registrar combate únicamente si estamos en la Expedición
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
print(string.format(" UMBRA — SERVIDOR ACTIVO [%s] ", if PlacesConfig.EsLobby() then "LOBBY" else "EXPEDICIÓN"))
print("=========================================")
