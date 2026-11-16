--!strict
-- GameManager.luau
-- Servicio central de ciclo de vida de la sesión para UMBRA: La última luz.
-- Responsabilidad: Administrar estados de partida, sesiones de jugadores,
-- detección de derrota (individual y cooperativa), detención de servicios y retorno seguro al lobby.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local ConfigFolder = ReplicatedStorage:WaitForChild("Config")
local ModulesFolder = ReplicatedStorage:WaitForChild("Modules")
local PlacesConfig = require(ConfigFolder:WaitForChild("PlacesConfig") :: ModuleScript)
local DevTestConfig = require(ConfigFolder:WaitForChild("DevTestConfig") :: ModuleScript)
local OleadasConfig = require(ConfigFolder:WaitForChild("OleadasConfig") :: ModuleScript)
local TiposAlpha = require(ModulesFolder:WaitForChild("TiposAlpha") :: ModuleScript)

export type EstadoPartida = TiposAlpha.EstadoPartida
export type EstadoJugador = TiposAlpha.EstadoJugador
export type ModoExpedicion = TiposAlpha.ModoExpedicion

local TRANSICIONES_VALIDAS: { [EstadoPartida]: { [EstadoPartida]: boolean } } = {
	Waiting = { Starting = true, Playing = true },
	Starting = { Playing = true, Waiting = true },
	Playing = { Victory = true, GameOver = true, ReturningToLobby = true, Waiting = true },
	Victory = { ReturningToLobby = true, Waiting = true },
	GameOver = { ReturningToLobby = true, Waiting = true },
	ReturningToLobby = { Waiting = true },
}

local GameManager = {
	EstadoActual = "Waiting" :: EstadoPartida,
	ModoExpedicion = "Solo" :: ModoExpedicion, -- Inmutable una vez comenzada la expedición
	ModoAutoritativoTeleport = nil :: ModoExpedicion?,
	JugadoresConectados = {} :: { [Player]: boolean },
	JugadoresVivos = {} :: { [Player]: boolean },
	EstadosJugadores = {} :: { [Player]: EstadoJugador },
	ParticipantesEquipo = {} :: { [number]: TiposAlpha.MiembroEquipoEspectador },
	TiempoMuerteJugador = {} :: { [Player]: number },
	EstadisticasFinalesJugador = {} :: { [Player]: any },
	NivelesFinalesJugador = {} :: { [Player]: number },
	ConexionesPersonajes = {} :: { [Player]: { RBXScriptConnection } },
	TransicionEnProgreso = false,
	RetornoEnProgreso = false,
	IntentosRetorno = 0,
	MaxIntentosRetorno = 2,
	-- Reloj lógico de expedición (Sección 15)
	TiempoLogicoSegundos = 0,
	DuracionObjetivoSegundos = DevTestConfig.DuracionExpedicionNormalSegundos,
	MultiplicadorTiempo = DevTestConfig.MultiplicadorPorDefecto,
	ModoAceleradoActivo = false,
	UltimoTiempoSync = 0,
	UltimoSyncEquipo = 0,
	MinutoLogicoPrevio = 0,
	ConexionRelojHeartbeat = nil :: RBXScriptConnection?,
	ConexionTeleportInitFailed = nil :: RBXScriptConnection?,
	RemoteSincronizar = nil :: RemoteEvent?,
	RemoteEstadoIndividual = nil :: RemoteEvent?,
	RemoteSolicitarRetorno = nil :: RemoteEvent?,
	RemoteSupervivientes = nil :: RemoteEvent?,
	RemoteSincronizarReloj = nil :: RemoteEvent?,
	RemoteComandoDev = nil :: RemoteEvent?,
	RemoteResultados = nil :: RemoteEvent?,
	SpawnerService = nil :: any,
	EnemyService = nil :: any,
	CombatService = nil :: any,
	ProgressionService = nil :: any,
	BossService = nil :: any,
	ReconnectionService = nil :: any,
}

-- Vinculación de servicios de combate, progresión, jefe, reconexión y hordas para control autoritativo
function GameManager.VincularServicios(spawnerRef: any, enemyRef: any, combatRef: any, progressionRef: any?, bossRef: any?, reconnectionRef: any?)
	GameManager.SpawnerService = spawnerRef
	GameManager.EnemyService = enemyRef
	GameManager.CombatService = combatRef
	GameManager.ProgressionService = progressionRef
	GameManager.BossService = bossRef
	GameManager.ReconnectionService = reconnectionRef
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
	GameManager.RemoteSincronizarReloj = asegurarRemote("SincronizarRelojExpedicion")
	GameManager.RemoteComandoDev = asegurarRemote("ComandoDevExpedicion")
	GameManager.RemoteResultados = asegurarRemote("PresentarResultadosExpedicion")

	-- Escuchar solicitudes autoritativas de retorno individual desde el cliente
	GameManager.RemoteSolicitarRetorno.OnServerEvent:Connect(function(player: Player)
		GameManager.SolicitarRetornoIndividual(player)
	end)

	-- Escuchar comandos de desarrollo con validación autoritativa estricta
	GameManager.RemoteComandoDev.OnServerEvent:Connect(function(player: Player, accion: any, valor: any)
		GameManager.ProcesarComandoDev(player, accion, valor)
	end)

	GameManager.EstadoActual = "Waiting"
	GameManager.TransicionEnProgreso = false
	GameManager.RetornoEnProgreso = false
	GameManager.IntentosRetorno = 0
	GameManager.TiempoLogicoSegundos = 0
	GameManager.MultiplicadorTiempo = DevTestConfig.MultiplicadorPorDefecto
	GameManager.ModoAceleradoActivo = false
	GameManager.UltimoTiempoSync = 0
	GameManager.MinutoLogicoPrevio = 0

	-- Bucle autoritativo del reloj lógico de expedición
	if not GameManager.ConexionRelojHeartbeat then
		GameManager.ConexionRelojHeartbeat = RunService.Heartbeat:Connect(function(dt: number)
			if not PlacesConfig.EsExpedicion() then return end
			if GameManager.EstadoActual ~= "Playing" then return end

			GameManager.TiempoLogicoSegundos += dt * GameManager.MultiplicadorTiempo

			local minutoActual = math.floor(GameManager.TiempoLogicoSegundos / 60)
			local ahora = os.clock()
			if minutoActual ~= GameManager.MinutoLogicoPrevio or (ahora - GameManager.UltimoTiempoSync) >= 1.0 then
				GameManager.MinutoLogicoPrevio = minutoActual
				GameManager.SincronizarRelojConClientes()
			end

			if GameManager.ModoExpedicion == "Coop" and (ahora - GameManager.UltimoSyncEquipo) >= 0.5 then
				GameManager.UltimoSyncEquipo = ahora
				GameManager.NotificarSupervivientes()
			end
		end)
	end

	-- Registrar escucha de fallos de inicialización de teletransporte autoritativo
	if not GameManager.ConexionTeleportInitFailed then
		GameManager.ConexionTeleportInitFailed = TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, errorMsg: string, targetPlaceId: number)
			warn(string.format("[GameManager] TeleportInitFailed: El teletransporte del jugador %s (UserId: %d) hacia el Place %d falló. Motivo: [%s] %s",
				player.Name, player.UserId, targetPlaceId, tostring(result), tostring(errorMsg)))
		end)
	end

	print("[UMBRA Server] GameManager iniciado. Estado inicial: Waiting.")
end

-- Retorna el estado actual del reloj lógico de la expedición
function GameManager.ObtenerEstadoReloj(): TiposAlpha.EstadoRelojExpedicion
	return {
		TiempoLogicoSegundos = GameManager.TiempoLogicoSegundos,
		DuracionObjetivoSegundos = GameManager.DuracionObjetivoSegundos,
		MultiplicadorTiempo = GameManager.MultiplicadorTiempo,
		ModoAceleradoActivo = GameManager.ModoAceleradoActivo,
	}
end

-- Retorna el tiempo lógico actual en segundos
function GameManager.ObtenerTiempoLogico(): number
	return GameManager.TiempoLogicoSegundos
end

-- Envía el estado actual del reloj lógico, oleada actual y enemigos activos a todos los clientes conectados
function GameManager.SincronizarRelojConClientes()
	GameManager.UltimoTiempoSync = os.clock()
	if GameManager.RemoteSincronizarReloj then
		local minutos = GameManager.TiempoLogicoSegundos / 60
		local oleadaActual = #OleadasConfig
		for idx, fase in OleadasConfig do
			if minutos >= fase.MinutoInicio and minutos < fase.MinutoFin then
				oleadaActual = idx
				break
			end
		end

		local enemigosCount = 0
		if GameManager.EnemyService and GameManager.EnemyService.EnemigosActivos then
			for _ in GameManager.EnemyService.EnemigosActivos do
				enemigosCount += 1
			end
		end

		GameManager.RemoteSincronizarReloj:FireAllClients({
			TiempoLogicoSegundos = GameManager.TiempoLogicoSegundos,
			MultiplicadorTiempo = GameManager.MultiplicadorTiempo,
			ModoAceleradoActivo = GameManager.ModoAceleradoActivo,
			OleadaActual = oleadaActual,
			EnemigosActivosCount = enemigosCount,
		})
	end
end

-- Procesa solicitudes de desarrollo (Sección 15) validando permisos y entorno
function GameManager.ProcesarComandoDev(player: Player, accion: any, valor: any)
	if not player or not player:IsDescendantOf(Players) then
		return
	end

	if not DevTestConfig.EsJugadorAutorizado(player) or not PlacesConfig.EsExpedicion() then
		warn(string.format(
			"[GameManager] ComandoDevExpedicion bloqueado para %s (UserId: %d). Sin autorización o fuera de Expedición.",
			player.Name,
			player.UserId
		))
		return
	end

	if accion == "AlternarVelocidad" then
		if GameManager.ModoAceleradoActivo then
			GameManager.MultiplicadorTiempo = DevTestConfig.MultiplicadorPorDefecto
			GameManager.ModoAceleradoActivo = false
		else
			GameManager.MultiplicadorTiempo = DevTestConfig.MultiplicadorAcelerado
			GameManager.ModoAceleradoActivo = true
		end
		print(string.format("[DEV][GameManager] %s cambió multiplicador de tiempo a x%.1f", player.Name, GameManager.MultiplicadorTiempo))
		GameManager.SincronizarRelojConClientes()

	elseif accion == "SaltarTiempo" then
		local segundos = tonumber(valor)
		if segundos then
			local tiempoClamped = math.clamp(segundos, 0, GameManager.DuracionObjetivoSegundos)
			GameManager.TiempoLogicoSegundos = tiempoClamped
			GameManager.MinutoLogicoPrevio = math.floor(tiempoClamped / 60)
			print(string.format("[DEV][GameManager] %s saltó el reloj lógico a %.1f segundos.", player.Name, tiempoClamped))
			GameManager.SincronizarRelojConClientes()
		end
	end
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

-- Retorna la lista completa del equipo (vivos y eliminados) con nivel y salud en tiempo real
function GameManager.ObtenerSupervivientesVivos(): { TiposAlpha.MiembroEquipoEspectador }
	local lista: { TiposAlpha.MiembroEquipoEspectador } = {}

	-- Refrescar datos en tiempo real de jugadores conectados
	for player, _ in GameManager.JugadoresConectados do
		if player and player:IsDescendantOf(Players) then
			local estaVivo = GameManager.JugadoresVivos[player] == true
			local estado = GameManager.EstadosJugadores[player] or "Alive"
			local nivel = if GameManager.ProgressionService and typeof(GameManager.ProgressionService.ObtenerNivelJugador) == "function"
				then GameManager.ProgressionService.ObtenerNivelJugador(player)
				else 1
			local char = player.Character
			local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
			local saludAct = if hum and estaVivo then math.max(0, math.ceil(hum.Health)) else 0
			local saludMax = if hum then math.max(1, math.ceil(hum.MaxHealth)) else 100

			GameManager.ParticipantesEquipo[player.UserId] = {
				UserId = player.UserId,
				Name = player.Name,
				Vivo = estaVivo,
				Estado = estado,
				Nivel = nivel,
				SaludActual = saludAct,
				SaludMaxima = saludMax,
			}
		end
	end

	for _, miembro in GameManager.ParticipantesEquipo do
		table.insert(lista, miembro)
	end
	table.sort(lista, function(a, b)
		if a.Vivo ~= b.Vivo then
			return a.Vivo
		end
		return a.Name < b.Name
	end)
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

		GameManager.TiempoLogicoSegundos = 0
		GameManager.MultiplicadorTiempo = DevTestConfig.MultiplicadorPorDefecto
		GameManager.ModoAceleradoActivo = false
		GameManager.MinutoLogicoPrevio = 0
		table.clear(GameManager.TiempoMuerteJugador)
		table.clear(GameManager.EstadisticasFinalesJugador)
		table.clear(GameManager.NivelesFinalesJugador)
		GameManager.SincronizarRelojConClientes()

		-- Fijar autoritativamente el modo de expedición desde el inicio de la sesión
		-- Prioriza TeleportData recibido desde MatchmakingService; fallback por número de jugadores en Studio
		local totalConectados = #Players:GetPlayers()
		if GameManager.ModoAutoritativoTeleport == "Coop" or GameManager.ModoAutoritativoTeleport == "Solo" then
			GameManager.ModoExpedicion = GameManager.ModoAutoritativoTeleport
		else
			GameManager.ModoExpedicion = if totalConectados > 1 then "Coop" else "Solo"
		end
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

	elseif nuevoEstado == "Victory" or nuevoEstado == "GameOver" then
		if nuevoEstado == "Victory" then
			print("[UMBRA Server] ¡VICTORIA! La expedición ha sido completada con éxito.")
		else
			print("[UMBRA Server] DERROTA: Todos los supervivientes han caído.")
		end

		GameManager.RetornoEnProgreso = false
		GameManager.IntentosRetorno = 0
		GameManager.SincronizarRelojConClientes()

		-- Recopilar y enviar reporte individual de resultados ANTES de detener y limpiar servicios (Sección 14)
		local resultadoStr: "VICTORIA" | "DERROTA" = if nuevoEstado == "Victory" then "VICTORIA" else "DERROTA"
		local jefesDerrotados = if GameManager.BossService and typeof(GameManager.BossService.ObtenerJefesDerrotados) == "function"
			then GameManager.BossService.ObtenerJefesDerrotados()
			else 0
		local oroPlaceholder = if nuevoEstado == "Victory"
			then DevTestConfig.RecompensasPlaceholderAlpha.OroVictoria
			else DevTestConfig.RecompensasPlaceholderAlpha.OroDerrota
		local gemasPlaceholder = if nuevoEstado == "Victory"
			then DevTestConfig.RecompensasPlaceholderAlpha.GemasVictoria
			else DevTestConfig.RecompensasPlaceholderAlpha.GemasDerrota

		if GameManager.RemoteResultados then
			for player, _ in GameManager.JugadoresConectados do
				if player and player:IsDescendantOf(Players) then
					local nivel = GameManager.NivelesFinalesJugador[player]
						or (if GameManager.ProgressionService and typeof(GameManager.ProgressionService.ObtenerNivelJugador) == "function"
							then GameManager.ProgressionService.ObtenerNivelJugador(player)
							else 1)
					local statsCombate = GameManager.EstadisticasFinalesJugador[player]
						or (if GameManager.CombatService and typeof(GameManager.CombatService.ObtenerEstadisticasCombate) == "function"
							then GameManager.CombatService.ObtenerEstadisticasCombate(player)
							else { DanioTotalCausado = 0, EnemigosDerrotados = 0, Magias = {} })
					local tiempoSobrevivido = GameManager.TiempoMuerteJugador[player] or GameManager.TiempoLogicoSegundos

					local reporte: TiposAlpha.ResultadosExpedicionIndividual = {
						Resultado = resultadoStr,
						TiempoSobrevividoSegundos = math.max(0, math.floor(tiempoSobrevivido)),
						NivelAlcanzado = nivel,
						EnemigosDerrotados = statsCombate.EnemigosDerrotados or 0,
						JefesDerrotados = jefesDerrotados,
						OroObtenido = oroPlaceholder,
						GemasObtenidas = gemasPlaceholder,
						DanioTotalCausado = statsCombate.DanioTotalCausado or 0,
						MagiasUtilizadas = statsCombate.Magias or {},
					}
					GameManager.RemoteResultados:FireClient(player, reporte)
				end
			end
		end

		-- Actualizar estado de todos los jugadores conectados en caso de derrota
		if nuevoEstado == "GameOver" then
			for player, _ in GameManager.JugadoresConectados do
				local est = GameManager.EstadosJugadores[player]
				if est ~= "ReturningToLobby" and est ~= "Returned" then
					GameManager.EstadosJugadores[player] = "Dead"
					GameManager.NotificarEstadoIndividual(player)
				end
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

		-- 4. Detener el servicio de progresión y limpiar orbes
		if GameManager.ProgressionService and GameManager.ProgressionService.Detener then
			GameManager.ProgressionService.Detener()
		end

		-- 5. Detener el servicio del Jefe Final y limpiar telégrafos
		if GameManager.BossService and GameManager.BossService.Detener then
			GameManager.BossService.Detener()
		end

		-- 6. Detener el servicio de reconexión y limpiar ventanas activas
		if GameManager.ReconnectionService and GameManager.ReconnectionService.Detener then
			GameManager.ReconnectionService.Detener()
		end

		-- 7. Si estamos en la Expedición, desactivar reaparición y establecer timeout de seguridad de 180s
		if PlacesConfig.EsExpedicion() then
			Players.CharacterAutoLoads = false

			task.delay(180, function()
				if GameManager.EstadoActual == nuevoEstado then
					GameManager.CambiarEstado("ReturningToLobby")
				end
			end)
		else
			-- Si por alguna razón ocurrió en el lobby, resetear a Waiting tras 4 segundos
			task.delay(4, function()
				if GameManager.EstadoActual == nuevoEstado then
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

	-- Leer de forma segura TeleportData para respetar el modo enviado desde el Lobby y registrar reconexión
	if PlacesConfig.EsExpedicion() then
		local exitoJoin, joinData = pcall(function()
			return player:GetJoinData()
		end)
		if exitoJoin and typeof(joinData) == "table" and typeof(joinData.TeleportData) == "table" then
			local modoTP = joinData.TeleportData.ModoExpedicion
			local accessCode = joinData.TeleportData.ReservedServerAccessCode
			if not GameManager.ModoAutoritativoTeleport and (modoTP == "Coop" or modoTP == "Solo") then
				GameManager.ModoAutoritativoTeleport = modoTP
				print(string.format("[UMBRA Server] TeleportData detectado para %s -> ModoExpedicion: %s", player.Name, modoTP))
			end
			if GameManager.ReconnectionService and typeof(GameManager.ReconnectionService.RegistrarParticipanteAutorizado) == "function" then
				local modoReg = if modoTP == "Coop" or modoTP == "Solo" then modoTP else GameManager.ModoExpedicion
				GameManager.ReconnectionService.RegistrarParticipanteAutorizado(player.UserId, accessCode, modoReg)
			end
		end

		-- Si el jugador regresa dentro de la ventana de reconexión (180s)
		if GameManager.EstadoActual == "Playing" and GameManager.ReconnectionService
			and typeof(GameManager.ReconnectionService.TieneSnapshotVigente) == "function"
			and GameManager.ReconnectionService.TieneSnapshotVigente(player.UserId) then
			if GameManager.ReconnectionService.IntentarReconectarJugador(player) then
				GameManager.JugadoresVivos[player] = true
				GameManager.EstadosJugadores[player] = "Alive"
				GameManager.NotificarSupervivientes()
			end
		elseif GameManager.ParticipantesEquipo[player.UserId] then
			-- Si había muerto previamente en esta expedición, mantener eliminación permanente
			local prev = GameManager.ParticipantesEquipo[player.UserId]
			if prev.Estado == "Dead" or prev.Estado == "Spectating" then
				GameManager.JugadoresVivos[player] = false
				GameManager.EstadosJugadores[player] = if GameManager.ModoExpedicion == "Coop" then "Spectating" else "Dead"
			end
		end
	end

	-- Sincronizar estado global e individual inmediatamente
	if GameManager.RemoteSincronizar then
		GameManager.RemoteSincronizar:FireClient(player, GameManager.EstadoActual)
	end
	if PlacesConfig.EsExpedicion() and GameManager.RemoteSincronizarReloj then
		GameManager.RemoteSincronizarReloj:FireClient(player, {
			TiempoLogicoSegundos = GameManager.TiempoLogicoSegundos,
			MultiplicadorTiempo = GameManager.MultiplicadorTiempo,
			ModoAceleradoActivo = GameManager.ModoAceleradoActivo,
		})
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

	-- Si estamos en juego y el jugador estaba vivo, guardar snapshot de reconexión (180s)
	if GameManager.EstadoActual == "Playing" then
		if estabaVivo then
			if PlacesConfig.EsExpedicion() and GameManager.ReconnectionService and typeof(GameManager.ReconnectionService.GuardarSnapshotDesconexion) == "function" then
				GameManager.ReconnectionService.GuardarSnapshotDesconexion(player)
			end
			if GameManager.ParticipantesEquipo[player.UserId] then
				GameManager.ParticipantesEquipo[player.UserId].Vivo = false
				GameManager.ParticipantesEquipo[player.UserId].Estado = "Disconnected"
				GameManager.ParticipantesEquipo[player.UserId].SaludActual = 0
			end
			GameManager.NotificarSupervivientes()
		end

		local vivos = GameManager.ObtenerTotalJugadoresVivos()
		local hayPendientes = if GameManager.ReconnectionService and typeof(GameManager.ReconnectionService.HayReconexionesPendientes) == "function"
			then GameManager.ReconnectionService.HayReconexionesPendientes()
			else false

		if vivos == 0 and not hayPendientes then
			print("[UMBRA Server] No quedan supervivientes activos ni reconexiones pendientes en la expedición.")
			GameManager.CambiarEstado("GameOver")
		elseif vivos == 0 and hayPendientes then
			print("[UMBRA Server] Último jugador vivo desconectado. Esperando ventana de reconexión (180s)...")
		end
	end
end

-- Callback invocado por ReconnectionService cuando expira la ventana de 180s de un jugador
function GameManager.OnReconexionExpirada(userId: number)
	GameManager.ParticipantesEquipo[userId] = nil
	GameManager.NotificarSupervivientes()

	if GameManager.EstadoActual == "Playing" then
		local vivos = GameManager.ObtenerTotalJugadoresVivos()
		local hayPendientes = if GameManager.ReconnectionService and typeof(GameManager.ReconnectionService.HayReconexionesPendientes) == "function"
			then GameManager.ReconnectionService.HayReconexionesPendientes()
			else false

		if vivos == 0 and not hayPendientes then
			print("[UMBRA Server] Ventana de reconexión expirada sin supervivientes activos. Declarando GameOver.")
			GameManager.CambiarEstado("GameOver")
		end
	end
end

-- Manejador de ciclo de vida del personaje (muerte autoritativa)
function GameManager.OnCharacterAdded(player: Player, character: Model)
	-- Impedir revivir/reaparecer si el jugador ya fue eliminado en esta expedición (Sección 12)
	local estadoActualJugador = GameManager.EstadosJugadores[player]
	if PlacesConfig.EsExpedicion() and (estadoActualJugador == "Dead" or estadoActualJugador == "Spectating") then
		GameManager.JugadoresVivos[player] = false
		task.defer(function()
			if character and character.Parent then
				character:Destroy()
			end
		end)
		return
	end

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
		if not GameManager.TiempoMuerteJugador[player] then
			GameManager.TiempoMuerteJugador[player] = GameManager.TiempoLogicoSegundos
		end
		if GameManager.CombatService and typeof(GameManager.CombatService.ObtenerEstadisticasCombate) == "function" then
			GameManager.EstadisticasFinalesJugador[player] = GameManager.CombatService.ObtenerEstadisticasCombate(player)
		end
		if GameManager.ProgressionService and typeof(GameManager.ProgressionService.ObtenerNivelJugador) == "function" then
			GameManager.NivelesFinalesJugador[player] = GameManager.ProgressionService.ObtenerNivelJugador(player)
		end
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
