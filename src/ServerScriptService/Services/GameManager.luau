--!strict
-- GameManager.luau
-- Servicio central de ciclo de vida de la sesión para UMBRA: La última luz.
-- Responsabilidad: Administrar estados de partida, sesiones de jugadores,
-- detección de derrota (individual y cooperativa), detención de servicios y retorno seguro al lobby.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local ConfigFolder = ReplicatedStorage:WaitForChild("Config")
local PlacesConfig = require(ConfigFolder:WaitForChild("PlacesConfig") :: ModuleScript)

export type EstadoPartida = "Waiting" | "Starting" | "Playing" | "GameOver" | "ReturningToLobby"

local TRANSICIONES_VALIDAS: { [EstadoPartida]: { [EstadoPartida]: boolean } } = {
	Waiting = { Starting = true, Playing = true },
	Starting = { Playing = true, Waiting = true },
	Playing = { GameOver = true, ReturningToLobby = true, Waiting = true },
	GameOver = { ReturningToLobby = true, Waiting = true },
	ReturningToLobby = { Waiting = true },
}

local GameManager = {
	EstadoActual = "Waiting" :: EstadoPartida,
	JugadoresConectados = {} :: { [Player]: boolean },
	JugadoresVivos = {} :: { [Player]: boolean },
	ConexionesPersonajes = {} :: { [Player]: { RBXScriptConnection } },
	TransicionEnProgreso = false,
	RemoteSincronizar = nil :: RemoteEvent?,
	SpawnerService = nil :: any,
	EnemyService = nil :: any,
	CombatService = nil :: any,
}

-- Vinculación de servicios de combate y hordas para control autoritativo
function GameManager.VincularServicios(spawnerRef: any, enemyRef: any, combatRef: any)
	GameManager.SpawnerService = spawnerRef
	GameManager.EnemyService = enemyRef
	GameManager.CombatService = combatRef
end

-- Inicializa el servicio y localiza canales de comunicación
function GameManager.Iniciar()
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 5)
	if remotesFolder then
		local remote = remotesFolder:WaitForChild("SincronizarEstadoPartida", 5) :: RemoteEvent?
		if remote and remote:IsA("RemoteEvent") then
			GameManager.RemoteSincronizar = remote
		else
			warn("[GameManager] Advertencia: No se encontró el RemoteEvent 'SincronizarEstadoPartida'.")
		end
	end

	GameManager.EstadoActual = "Waiting"
	GameManager.TransicionEnProgreso = false
	print("[UMBRA Server] GameManager iniciado. Estado inicial: Waiting.")
end

-- Retorna el estado actual de la sesión
function GameManager.ObtenerEstado(): EstadoPartida
	return GameManager.EstadoActual
end

-- Cuenta cuántos supervivientes siguen con vida en la expedición
function GameManager.ObtenerTotalJugadoresVivos(): number
	local totalVivos = 0
	for _, estaVivo in GameManager.JugadoresVivos do
		if estaVivo then
			totalVivos += 1
		end
	end
	return totalVivos
end

-- Valida y ejecuta un cambio de estado en la máquina de estados
function GameManager.CambiarEstado(nuevoEstado: EstadoPartida): boolean
	if GameManager.EstadoActual == nuevoEstado then
		return false
	end

	if GameManager.TransicionEnProgreso then
		warn(string.format("[GameManager] Transición rechazada: cambio en progreso (%s -> %s)", GameManager.EstadoActual, nuevoEstado))
		return false
	end

	local permitidas = TRANSICIONES_VALIDAS[GameManager.EstadoActual]
	if not permitidas or not permitidas[nuevoEstado] then
		warn(string.format("[GameManager] Transición INVÁLIDA rechazada: %s -> %s", GameManager.EstadoActual, nuevoEstado))
		return false
	end

	GameManager.TransicionEnProgreso = true
	local estadoAnterior = GameManager.EstadoActual
	GameManager.EstadoActual = nuevoEstado

	print(string.format("[UMBRA Server] Transición de sesión: %s -> %s", estadoAnterior, nuevoEstado))

	-- Notificar a todos los clientes conectados de forma autoritativa
	if GameManager.RemoteSincronizar then
		GameManager.RemoteSincronizar:FireAllClients(nuevoEstado)
	end

	-- Lógica de entrada a cada estado
	if nuevoEstado == "Starting" then
		task.spawn(function()
			task.wait(1)
			GameManager.TransicionEnProgreso = false
			local total = #Players:GetPlayers()
			if total > 0 then
				GameManager.CambiarEstado("Playing")
			else
				GameManager.CambiarEstado("Waiting")
			end
		end)
		return true

	elseif nuevoEstado == "Playing" then
		print("[UMBRA Server] ¡Expedición en curso! Supervivencia iniciada.")
		-- Registrar como vivos a todos los jugadores conectados con personaje activo
		for _, player in Players:GetPlayers() do
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				GameManager.JugadoresVivos[player] = true
			end
		end

	elseif nuevoEstado == "GameOver" then
		print("[UMBRA Server] DERROTA: Todos los supervivientes han caído.")

		-- 1. Detener INMEDIATAMENTE la generación de enemigos y cancelar tareas
		if GameManager.SpawnerService and GameManager.SpawnerService.Detener then
			GameManager.SpawnerService.Detener()
		end

		-- 2. Eliminar y limpiar TODOS los enemigos activos del mapa
		if GameManager.EnemyService and GameManager.EnemyService.Detener then
			GameManager.EnemyService.Detener()
		end

		-- 3. Detener el servicio de combate
		if GameManager.CombatService and GameManager.CombatService.Detener then
			GameManager.CombatService.Detener()
		end

		-- 4. Si estamos en la Expedición, preparar el retorno ordenado al Lobby
		if PlacesConfig.EsExpedicion() then
			-- Desactivar reaparición automática para evitar reaparecer en la arena destruida
			Players.CharacterAutoLoads = false

			-- Esperar 6 segundos para que los jugadores visualicen el resultado en pantalla
			task.delay(6, function()
				if GameManager.EstadoActual == "GameOver" then
					GameManager.CambiarEstado("ReturningToLobby")
				end
			end)
		else
			-- Si por alguna razón ocurrió en el lobby, resetear a Waiting tras 4 segundos
			task.delay(4, function()
				if GameManager.EstadoActual == "GameOver" then
					GameManager.CambiarEstado("Waiting")
				end
			end)
		end

	elseif nuevoEstado == "ReturningToLobby" then
		print("[UMBRA Server] Retornando supervivientes al Santuario (Lobby)...")

		if PlacesConfig.EsExpedicion() and PlacesConfig.LobbyPlaceId > 0 then
			local jugadoresParaTeleport = Players:GetPlayers()
			if #jugadoresParaTeleport > 0 then
				local exitoTP, errTP = pcall(function()
					TeleportService:TeleportPartyAsync(PlacesConfig.LobbyPlaceId, jugadoresParaTeleport)
				end)
				if not exitoTP then
					warn(string.format("[GameManager] Error al retornar al Lobby: %s", tostring(errTP)))
				end
			end
		else
			-- Entorno local o Place único
			GameManager.CambiarEstado("Waiting")
		end

	elseif nuevoEstado == "Waiting" then
		print("[UMBRA Server] Sesión en reposo. Esperando jugadores.")
	end

	GameManager.TransicionEnProgreso = false
	return true
end

-- Manejador de conexión de nuevo jugador
function GameManager.OnPlayerAdded(player: Player)
	if GameManager.JugadoresConectados[player] then
		return
	end

	GameManager.JugadoresConectados[player] = true
	GameManager.JugadoresVivos[player] = false
	GameManager.ConexionesPersonajes[player] = {}
	print(string.format("[UMBRA Server] Jugador conectado: %s (UserId: %d)", player.Name, player.UserId))

	-- Sincronizar estado actual inmediatamente
	if GameManager.RemoteSincronizar then
		GameManager.RemoteSincronizar:FireClient(player, GameManager.EstadoActual)
	end

	-- Escuchar carga y reaparición del personaje
	local connChar = player.CharacterAdded:Connect(function(character)
		GameManager.OnCharacterAdded(player, character)
	end)
	table.insert(GameManager.ConexionesPersonajes[player], connChar)

	if player.Character then
		task.spawn(GameManager.OnCharacterAdded, player, player.Character)
	end

	-- En la expedición, si entra durante Waiting, preparar inicio
	if PlacesConfig.EsExpedicion() and GameManager.EstadoActual == "Waiting" then
		task.delay(1.5, function()
			if GameManager.EstadoActual == "Waiting" and #Players:GetPlayers() > 0 then
				GameManager.CambiarEstado("Starting")
			end
		end)
	end
end

-- Manejador de desconexión de jugador
function GameManager.OnPlayerRemoving(player: Player)
	GameManager.JugadoresConectados[player] = nil
	GameManager.JugadoresVivos[player] = nil

	local conns = GameManager.ConexionesPersonajes[player]
	if conns then
		for _, conn in conns do
			conn:Disconnect()
		end
		GameManager.ConexionesPersonajes[player] = nil
	end

	print(string.format("[UMBRA Server] Jugador desconectado: %s", player.Name))

	-- Si estamos en juego y ya no quedan jugadores vivos, finalizar
	if GameManager.EstadoActual == "Playing" then
		local vivos = GameManager.ObtenerTotalJugadoresVivos()
		if vivos == 0 then
			GameManager.CambiarEstado("GameOver")
		end
	end
end

-- Manejador de ciclo de vida del personaje (muerte autoritativa)
function GameManager.OnCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then return end

	-- Si estamos en juego, marcar jugador como vivo
	if GameManager.EstadoActual == "Playing" or GameManager.EstadoActual == "Starting" then
		GameManager.JugadoresVivos[player] = true
	end

	local connDied: RBXScriptConnection? = nil
	connDied = humanoid.Died:Connect(function()
		if connDied then
			connDied:Disconnect()
		end

		GameManager.JugadoresVivos[player] = false
		print(string.format("[UMBRA Server] Superviviente %s ha caído.", player.Name))

		-- Si la partida está en curso, verificar si quedan supervivientes vivos
		if GameManager.EstadoActual == "Playing" then
			local vivosRestantes = GameManager.ObtenerTotalJugadoresVivos()
			print(string.format("[UMBRA Server] Supervivientes restantes con vida: %d", vivosRestantes))

			-- Si no queda ningún superviviente vivo, declarar GameOver
			if vivosRestantes == 0 then
				GameManager.CambiarEstado("GameOver")
			end
		end
	end)

	if GameManager.ConexionesPersonajes[player] and connDied then
		table.insert(GameManager.ConexionesPersonajes[player], connDied)
	end
end

return GameManager
