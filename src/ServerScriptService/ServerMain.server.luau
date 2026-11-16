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
local ProgressionService = nil :: any
local BossService = nil :: any
local ReconnectionService = nil :: any
local MatchmakingService = nil :: any

if PlacesConfig.EsLobby() then
	-- =========================================================================
	-- PLACE 1: LOBBY (Santuario del Último Resplandor)
	-- No se cargan enemigos, ni oleadas, ni combate automático.
	-- Solo se inicia el portal de emparejamiento y la reconexión.
	-- =========================================================================
	print("[ServerMain] Configurando entorno de LOBBY: Hordas, Spawner y Combate DESHABILITADOS.")

	local reconModulo = ServicesFolder:WaitForChild("ReconnectionService") :: ModuleScript
	local _, reconInst = inicializarServicio("ReconnectionService", reconModulo, GameManager)
	ReconnectionService = reconInst

	local matchmakingModulo = ServicesFolder:WaitForChild("MatchmakingService") :: ModuleScript
	local _, mmInst = inicializarServicio("MatchmakingService", matchmakingModulo, GameManager)
	MatchmakingService = mmInst

	if MatchmakingService and typeof(MatchmakingService.VincularReconnectionService) == "function" and ReconnectionService then
		MatchmakingService.VincularReconnectionService(ReconnectionService)
	end

else
	-- =========================================================================
	-- PLACE 2: EXPEDICIÓN (Arena de Supervivencia)
	-- Se cargan e inician los sistemas de combate, oleadas, progresión, jefe y reconexión.
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

	local progressionModulo = ServicesFolder:WaitForChild("ProgressionService") :: ModuleScript
	local _, progressionInst = inicializarServicio("ProgressionService", progressionModulo, CombatService, GameManager)
	ProgressionService = progressionInst

	if EnemyService and typeof(EnemyService.EstablecerCallbackEliminacion) == "function" and ProgressionService then
		EnemyService.EstablecerCallbackEliminacion(ProgressionService.OnEnemigoEliminado)
	end

	local bossModulo = ServicesFolder:WaitForChild("BossService") :: ModuleScript
	local _, bossInst = inicializarServicio("BossService", bossModulo, EnemyService, GameManager)
	BossService = bossInst

	local reconModulo = ServicesFolder:WaitForChild("ReconnectionService") :: ModuleScript
	local _, reconInst = inicializarServicio("ReconnectionService", reconModulo, GameManager, CombatService, ProgressionService, EnemyService)
	ReconnectionService = reconInst

	if EnemyService and typeof(EnemyService.VincularReconnectionService) == "function" and ReconnectionService then
		EnemyService.VincularReconnectionService(ReconnectionService)
	end
	if BossService and typeof(BossService.VincularReconnectionService) == "function" and ReconnectionService then
		BossService.VincularReconnectionService(ReconnectionService)
	end
	if SpawnerService and typeof(SpawnerService.VincularBossService) == "function" and BossService then
		SpawnerService.VincularBossService(BossService)
	end

	if GameManager.VincularServicios then
		GameManager.VincularServicios(SpawnerService, EnemyService, CombatService, ProgressionService, BossService, ReconnectionService)
	end
end

-- 2. Gestión del ciclo de vida de jugadores
local function registrarJugador(player: Player)
	-- Registrar combate y progresión antes de GameManager.OnPlayerAdded para permitir restauración de snapshot
	if CombatService and typeof(CombatService.RegistrarJugador) == "function" then
		local exitoCombatReg, errCombat = pcall(CombatService.RegistrarJugador, player)
		if not exitoCombatReg then
			warn(string.format("[ServerMain] Error al registrar CombatService para %s: %s", player.Name, tostring(errCombat)))
		end
	end

	if ProgressionService and typeof(ProgressionService.RegistrarJugador) == "function" then
		local exitoProgReg, errProg = pcall(ProgressionService.RegistrarJugador, player)
		if not exitoProgReg then
			warn(string.format("[ServerMain] Error al registrar ProgressionService para %s: %s", player.Name, tostring(errProg)))
		end
	end

	local exitoGMPlayer, errGM = pcall(GameManager.OnPlayerAdded, player)
	if not exitoGMPlayer then
		warn(string.format("[ServerMain] Error al registrar GameManager para %s: %s", player.Name, tostring(errGM)))
	end
end

local function desregistrarJugador(player: Player)
	-- GameManager.OnPlayerRemoving captura el snapshot antes de limpiar perfiles de combate y progresión
	pcall(GameManager.OnPlayerRemoving, player)

	if ProgressionService and typeof(ProgressionService.DesregistrarJugador) == "function" then
		pcall(ProgressionService.DesregistrarJugador, player)
	end

	if CombatService and typeof(CombatService.DesregistrarJugador) == "function" then
		pcall(CombatService.DesregistrarJugador, player)
	end
end

Players.PlayerAdded:Connect(registrarJugador)
Players.PlayerRemoving:Connect(desregistrarJugador)

for _, player in Players:GetPlayers() do
	task.spawn(registrarJugador, player)
end

print("=========================================")
print(string.format(" UMBRA — SERVIDOR ACTIVO [%s] ", if PlacesConfig.EsLobby() then "LOBBY" else "EXPEDICIÓN"))
print("=========================================")
