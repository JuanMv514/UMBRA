--!strict
-- ServerMain.server.luau
-- Punto de entrada único del Servidor (Server Bootstrap) para UMBRA: La última luz.
-- Responsabilidad: Orquestar la inicialización secuencial de servicios y captura de errores.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

print("=========================================")
print("      UMBRA — SERVIDOR INICIANDO         ")
print("=========================================")

local ServicesFolder = ServerScriptService:WaitForChild("Services")

-- Función protegida de inicialización de servicios
local function inicializarServicio(nombre: string, modulo: ModuleScript): (boolean, any)
	local exitoCarga, servicio = pcall(require, modulo)
	if not exitoCarga then
		warn(string.format("[ServerMain] ERROR CRÍTICO al cargar el módulo '%s': %s", nombre, tostring(servicio)))
		return false, nil
	end

	if typeof(servicio) == "table" and typeof(servicio.Iniciar) == "function" then
		local exitoInit, err = pcall(servicio.Iniciar)
		if not exitoInit then
			warn(string.format("[ServerMain] ERROR CRÍTICO al ejecutar Iniciar() en '%s': %s", nombre, tostring(err)))
			return false, servicio
		end
	end

	print(string.format("[ServerMain] Servicio '%s' inicializado con éxito.", nombre))
	return true, servicio
end

-- 1. Inicialización ordenada del GameManager
local gmModulo = ServicesFolder:WaitForChild("GameManager") :: ModuleScript
local exitoGM, GameManager = inicializarServicio("GameManager", gmModulo)

if not exitoGM or not GameManager then
	error("[ServerMain] No fue posible inicializar GameManager. Deteniendo arranque del servidor.")
end

-- 2. Registro protegido del ciclo de vida de jugadores
local function registrarJugador(player: Player)
	local exito, err = pcall(GameManager.OnPlayerAdded, player)
	if not exito then
		warn(string.format("[ServerMain] Error al registrar PlayerAdded para %s: %s", player.Name, tostring(err)))
	end
end

local function desregistrarJugador(player: Player)
	local exito, err = pcall(GameManager.OnPlayerRemoving, player)
	if not exito then
		warn(string.format("[ServerMain] Error al registrar PlayerRemoving para %s: %s", player.Name, tostring(err)))
	end
end

Players.PlayerAdded:Connect(registrarJugador)
Players.PlayerRemoving:Connect(desregistrarJugador)

for _, player in Players:GetPlayers() do
	task.spawn(registrarJugador, player)
end

print("=========================================")
print("     UMBRA — SERVIDOR LISTO Y ACTIVO     ")
print("=========================================")
