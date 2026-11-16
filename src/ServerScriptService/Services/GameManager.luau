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
export type EstadoJugador = "Alive" | "Dead" | "Spectating" | "ReturningToLobby" | "Returned"
export type ModoExpedicion = "Solo" | "Coop"

local TRANSICIONES_VALIDAS: { [EstadoPartida]: { [EstadoPartida]: boolean } } = {
	Waiting = { Starting = true, Playing = true },
	Starting = { Playing = true, Waiting = true },
	Playing = { GameOver = true, ReturningToLobby = true, Waiting = true },
	GameOver = { ReturningToLobby = true, Waiting = true },
	ReturningToLobby = { Waiting = true },
}

local GameManager = {
	EstadoActual = "Waiting" :: EstadoPartida,
	ModoExpedicion = "Solo" :: ModoExpedicion, -- Inmutable una vez comenzada la expedición
	JugadoresConectados = {} :: { [Player]: boolean },
	JugadoresVivos = {} :: { [Player]: boolean },
	EstadosJugadores = {} :: { [Player]: EstadoJugador },
	ConexionesPersonajes = {} :: { [Player]: { RBXScriptConnection } },
	TransicionEnProgreso = false,
	RetornoEnProgreso = false,
	IntentosRetorno = 0,
	MaxIntentosRetorno = 2,
	ConexionTeleportInitFailed = nil :: RBXScriptConnection?,
	RemoteSincronizar = nil :: RemoteEvent?,
	RemoteEstadoIndividual = nil :: RemoteEvent?,
	RemoteSolicitarRetorno = nil :: RemoteEvent?,
	RemoteSupervivientes = nil :: RemoteEvent?,
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
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end

	local function asegurarRemote(nombre: string): RemoteEvent
		local r = remotesFolder:FindFirstChild(nombre) :: RemoteEvent?
		if not r or not r:IsA("RemoteEvent") then
			r = Instance.new("RemoteEvent")
			r.Name = nombre
			r.Parent = remotesFolder
		end
		return r
	end

	GameManager.RemoteSincronizar = asegurarRemote("SincronizarEstadoPartida")
	GameManager.RemoteEstadoIndividual = asegurarRemote("SincronizarEstadoIndividual")
	GameManager.RemoteSolicitarRetorno = asegurarRemote("SolicitarRetornoIndividual")
	GameManager.RemoteSupervivientes = asegurarRemote("ActualizarSupervivientes")

	-- Escuchar solicitudes autoritativas de retorno individual desde el cliente
	GameManager.RemoteSolicitarRetorno.OnServerEvent:Connect(function(player: Player)
		GameManager.SolicitarRetornoIndividual(player)
	end)

	GameManager.EstadoActual = "Waiting"
	GameManager.TransicionEnProgreso = false
	GameManager.RetornoEnProgreso = false
	GameManager.IntentosRetorno = 0

	-- Registrar escucha de fallos de inicialización de teletransporte autoritativo
	if not GameManager.ConexionTeleportInitFailed then
		GameManager.ConexionTeleportInitFailed = TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, errorMsg: string, targetPlaceId: number)
			warn(string.format("[GameManager] TeleportInitFailed: El teletransporte del jugador %s (UserId: %d) hacia el Place %d falló. Motivo: [%s] %s",
				player.Name, player.UserId, targetPlaceId, tostring(result), tostring(errorMsg)))
		end)
	end

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

-- Retorna la lista de supervivientes vivos con datos públicos para modo espectador
function GameManager.ObtenerSupervivientesVivos(): { { UserId: number, Name: string } }
	local lista = {}
	for player, vivo in GameManager.JugadoresVivos do
		if vivo and player and player:IsDescendantOf(Players) then
			table.insert(lista, {
				UserId = player.UserId,
				Name = player.Name,
			})
		end
	end
	return lista
end

-- Notifica a todos los clientes la lista actualizada de supervivientes vivos
function GameManager.NotificarSupervivientes()
	if GameManager.RemoteSupervivientes then
		local lista = GameManager.ObtenerSupervivientesVivos()
		GameManager.RemoteSupervivientes:FireAllClients(lista)
	end
end

-- Sincroniza el estado individual de un jugador específico
function GameManager.NotificarEstadoIndividual(player: Player)
	if GameManager.RemoteEstadoIndividual and player and player:IsDescendantOf(Players) then
		local estado = GameManager.EstadosJugadores[player] or "Alive"
		GameManager.RemoteEstadoIndividual:FireClient(player, estado, GameManager.ModoExpedicion)
	end
end

-- Gestiona el retorno voluntario e individual de un jugador hacia el Lobby
function GameManager.SolicitarRetornoIndividual(player: Player)
	if not player or not player:IsDescendantOf(Players) then return end
	if not PlacesConfig.EsExpedicion() then return end

	local estadoActual = GameManager.EstadosJugadores[player]
	if estadoActual == "ReturningToLobby" or estadoActual == "Returned" then
		print(string.format("[GameManager] Solicitud de retorno ignorada para %s: ya está retornando o en el Lobby.", player.Name))
		return
	end

	print(string.format("[GameManager] Retorno voluntario individual solicitado por: %s (Estado actual: %s)", player.Name, tostring(estadoActual)))

	-- Si el jugador estaba vivo al salir, desarmar y actualizar conteo de vivos
	if GameManager.JugadoresVivos[player] then
		GameManager.JugadoresVivos[player] = false
		if GameManager.CombatService and typeof(GameManager.CombatService.DesregistrarJugador) == "function" then
			pcall(GameManager.CombatService.DesregistrarJugador, player)
		end

		-- Si era el último vivo durante partida en curso, declarar GameOver para el resto de la sesión
		if GameManager.EstadoActual == "Playing" and GameManager.ObtenerTotalJugadoresVivos() == 0 then
			print("[GameManager] El último superviviente vivo ha abandonado. Finalizando expedición.")
			GameManager.CambiarEstado("GameOver")
		else
			GameManager.NotificarSupervivientes()
		end
	end

	GameManager.EstadosJugadores[player] = "ReturningToLobby"
	GameManager.NotificarEstadoIndividual(player)

	task.spawn(function()
		if PlacesConfig.LobbyPlaceId <= 0 or PlacesConfig.LobbyPlaceId == PlacesConfig.ExpeditionPlaceId then
			warn("[GameManager] Error de retorno individual: PlaceId del Lobby inválido en PlacesConfig.")
			GameManager.EstadosJugadores[player] = if GameManager.ModoExpedicion == "Coop" then "Spectating" else "Dead"
			GameManager.NotificarEstadoIndividual(player)
			return
		end

		print(string.format("[GameManager] Teletransportando individualmente a %s (UserId: %d) hacia el Lobby...", player.Name, player.UserId))
		local exitoTP, errTP = pcall(function()
			TeleportService:TeleportAsync(PlacesConfig.LobbyPlaceId, { player })
		end)

		if exitoTP then
			print(string.format("[GameManager] Retorno individual despachado con éxito para %s.", player.Name))
		else
			warn(string.format("[GameManager] Error en retorno individual de %s: %s", player.Name, tostring(errTP)))
			if player:IsDescendantOf(Players) and GameManager.EstadosJugadores[player] == "ReturningToLobby" then
				GameManager.EstadosJugadores[player] = if GameManager.ModoExpedicion == "Coop" then "Spectating" else "Dead"
				GameManager.NotificarEstadoIndividual(player)
			end
		end
	end)
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

		-- Fijar autoritativamente el modo de expedición desde el inicio de la sesión
		-- No se recalcula durante la partida para mantener coherencia si mueren o salen participantes
		local totalConectados = #Players:GetPlayers()
		GameManager.ModoExpedicion = if totalConectados > 1 then "Coop" else "Solo"
		print(string.format("[UMBRA Server] Modo de Expedición fijado: %s (%d participantes iniciales)",
			GameManager.ModoExpedicion, totalConectados))

		-- Registrar como vivos a todos los jugadores conectados con personaje activo
		for _, player in Players:GetPlayers() do
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				GameManager.JugadoresVivos[player] = true
				GameManager.EstadosJugadores[player] = "Alive"
			else
				GameManager.EstadosJugadores[player] = "Alive"
			end
			GameManager.NotificarEstadoIndividual(player)
		end
		GameManager.NotificarSupervivientes()

	elseif nuevoEstado == "GameOver" then
		print("[UMBRA Server] DERROTA: Todos los supervivientes han caído.")
		GameManager.RetornoEnProgreso = false
		GameManager.IntentosRetorno = 0

		-- Actualizar estado de todos los jugadores conectados
		for player, _ in GameManager.JugadoresConectados do
			local est = GameManager.EstadosJugadores[player]
			if est ~= "ReturningToLobby" and est ~= "Returned" then
				GameManager.EstadosJugadores[player] = "Dead"
				GameManager.NotificarEstadoIndividual(player)
			end
		end

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

		if PlacesConfig.EsExpedicion() and PlacesConfig.LobbyPlaceId > 0 and PlacesConfig.LobbyPlaceId ~= PlacesConfig.ExpeditionPlaceId then
			if GameManager.RetornoEnProgreso then
				print("[GameManager] Retorno al Lobby ya en progreso. Evitando solicitud duplicada.")
				GameManager.TransicionEnProgreso = false
				return true
			end

			GameManager.RetornoEnProgreso = true
			GameManager.IntentosRetorno = 0

			local function ejecutarRetorno()
				-- Filtrar solo jugadores que sigan efectivamente conectados a la sesión y no hayan retornado individualmente
				local jugadoresParaTeleport: { Player } = {}
				for _, player in ipairs(Players:GetPlayers()) do
					if player and player:IsDescendantOf(Players) then
						local est = GameManager.EstadosJugadores[player]
						if est ~= "Returned" and est ~= "ReturningToLobby" then
							GameManager.EstadosJugadores[player] = "ReturningToLobby"
							table.insert(jugadoresParaTeleport, player)
						end
					end
				end

				if #jugadoresParaTeleport == 0 then
					print("[GameManager] No hay jugadores conectados en la sesión para retornar al Lobby.")
					GameManager.RetornoEnProgreso = false
					GameManager.CambiarEstado("Waiting")
					return
				end

				print(string.format("[GameManager] Solicitando teletransporte de retorno para %d jugador(es) hacia el Lobby (PlaceId: %d)...",
					#jugadoresParaTeleport, PlacesConfig.LobbyPlaceId))

				local exitoTP, errTP = pcall(function()
					TeleportService:TeleportAsync(PlacesConfig.LobbyPlaceId, jugadoresParaTeleport)
				end)

				if exitoTP then
					print(string.format("[GameManager] Solicitud de teletransporte hacia el Lobby (PlaceId: %d) despachada con éxito.", PlacesConfig.LobbyPlaceId))
				else
					warn(string.format("[GameManager] Error en TeleportService:TeleportAsync hacia el Lobby (PlaceId: %d): %s",
						PlacesConfig.LobbyPlaceId, tostring(errTP)))

					-- Reintento controlado si aún no se supera el límite de reintentos
					if GameManager.IntentosRetorno < GameManager.MaxIntentosRetorno then
						GameManager.IntentosRetorno += 1
						print(string.format("[GameManager] Programando reintento controlado de retorno (%d/%d) en 5 segundos...",
							GameManager.IntentosRetorno, GameManager.MaxIntentosRetorno))
						task.delay(5, function()
							if GameManager.EstadoActual == "ReturningToLobby" then
								ejecutarRetorno()
							end
						end)
					else
						warn("[GameManager] Se agotaron los reintentos controlados de retorno al Lobby. La sesión permanecerá disponible para reconexión.")
						GameManager.RetornoEnProgreso = false
					end
				end
			end

			task.spawn(ejecutarRetorno)
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
	GameManager.EstadosJugadores[player] = "Alive"
	GameManager.ConexionesPersonajes[player] = {}
	print(string.format("[UMBRA Server] Jugador conectado: %s (UserId: %d)", player.Name, player.UserId))

	-- Sincronizar estado global e individual inmediatamente
	if GameManager.RemoteSincronizar then
		GameManager.RemoteSincronizar:FireClient(player, GameManager.EstadoActual)
	end
	GameManager.NotificarEstadoIndividual(player)

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
	local estabaVivo = GameManager.JugadoresVivos[player]
	GameManager.JugadoresVivos[player] = nil
	GameManager.EstadosJugadores[player] = nil

	local conns = GameManager.ConexionesPersonajes[player]
	if conns then
		for _, conn in conns do
			conn:Disconnect()
		end
		GameManager.ConexionesPersonajes[player] = nil
	end

	print(string.format("[UMBRA Server] Jugador desconectado: %s", player.Name))

	-- Si estamos en juego y el jugador estaba vivo, actualizar lista de supervivientes
	if GameManager.EstadoActual == "Playing" then
		if estabaVivo then
			GameManager.NotificarSupervivientes()
		end

		local vivos = GameManager.ObtenerTotalJugadoresVivos()
		if vivos == 0 then
			print("[UMBRA Server] No quedan supervivientes activos en la expedición tras la desconexión.")
			GameManager.CambiarEstado("GameOver")
		end
	end
end

-- Manejador de ciclo de vida del personaje (muerte autoritativa)
function GameManager.OnCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then return end

	-- Si estamos en juego o comenzando, marcar jugador como vivo
	if GameManager.EstadoActual == "Playing" or GameManager.EstadoActual == "Starting" then
		GameManager.JugadoresVivos[player] = true
		GameManager.EstadosJugadores[player] = "Alive"
		GameManager.NotificarEstadoIndividual(player)
		GameManager.NotificarSupervivientes()
	end

	local connDied: RBXScriptConnection? = nil
	connDied = humanoid.Died:Connect(function()
		if connDied then
			connDied:Disconnect()
		end

		GameManager.JugadoresVivos[player] = false
		GameManager.EstadosJugadores[player] = "Dead"
		print(string.format("[UMBRA Server] Superviviente %s ha caído.", player.Name))

		-- Desactivar de inmediato cualquier participación en combate
		if GameManager.CombatService and typeof(GameManager.CombatService.DesregistrarJugador) == "function" then
			pcall(GameManager.CombatService.DesregistrarJugador, player)
		end

		-- Si la partida está en curso, verificar lógica según modo
		if GameManager.EstadoActual == "Playing" then
			local vivosRestantes = GameManager.ObtenerTotalJugadoresVivos()
			print(string.format("[UMBRA Server] Supervivientes restantes con vida: %d (Modo: %s)",
				vivosRestantes, GameManager.ModoExpedicion))

			if GameManager.ModoExpedicion == "Solo" or vivosRestantes == 0 then
				-- En modo individual O cuando caen todos los integrantes en cooperativo: Derrota global
				GameManager.CambiarEstado("GameOver")
			else
				-- En modo cooperativo con compañeros vivos: Activar espectador individual
				print(string.format("[UMBRA Server] Activando modo espectador para %s.", player.Name))
				GameManager.EstadosJugadores[player] = "Spectating"
				GameManager.NotificarEstadoIndividual(player)
				GameManager.NotificarSupervivientes()
			end
		end
	end)

	if GameManager.ConexionesPersonajes[player] and connDied then
		table.insert(GameManager.ConexionesPersonajes[player], connDied)
	end
end

return GameManager
