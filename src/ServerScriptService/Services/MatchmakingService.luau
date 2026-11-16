--!strict
-- MatchmakingService.luau
-- Manejador autoritativo de acceso a expediciones (Individual y Salas Públicas Cooperativas) en UMBRA.
-- Responsabilidad: Operar exclusivamente en el Lobby (Santuario), gestionar salas públicas de hasta 4 jugadores,
-- sucesión automática de responsable y teletransporte a servidores reservados de Expedición.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local ConfigFolder = ReplicatedStorage:WaitForChild("Config")
local ModulesFolder = ReplicatedStorage:WaitForChild("Modules")
local PlacesConfig = require(ConfigFolder:WaitForChild("PlacesConfig") :: ModuleScript)
local TiposAlpha = require(ModulesFolder:WaitForChild("TiposAlpha") :: ModuleScript)

local GameManager = nil :: any
local ReconnectionService = nil :: any

type ParticipanteInterno = {
	Player: Player,
	UserId: number,
	Nombre: string,
	Estado: TiposAlpha.EstadoParticipanteSala,
	OrdenLlegada: number,
}

type SalaInterna = {
	SalaId: string,
	TiempoCreacion: number,
	ResponsableUserId: number,
	CapacidadMaxima: number,
	Cerrada: boolean,
	IniciandoExpedicion: boolean,
	SiguienteOrden: number,
	Participantes: { ParticipanteInterno },
}

local MatchmakingService = {
	Activo = false,
	MaxJugadores = 4,
	ContadorSalas = 0,
	SalasActivas = {} :: { [string]: SalaInterna },
	SalaPorJugador = {} :: { [Player]: string },
	JugadoresTeletransportando = {} :: { [Player]: boolean },
	PosicionCirculo = Vector3.new(0, 0.5, -45),
	RemoteAccionLobby = nil :: RemoteEvent?,
	RemoteSincronizarSala = nil :: RemoteEvent?,
	PlataformaVisual = nil :: BasePart?,
	BillboardGui = nil :: BillboardGui?,
}

local function asegurarRemote(remotesFolder: Instance, nombre: string): RemoteEvent
	local existente = remotesFolder:FindFirstChild(nombre)
	if existente and existente:IsA("RemoteEvent") then
		return existente
	end
	local nuevo = Instance.new("RemoteEvent")
	nuevo.Name = nombre
	nuevo.Parent = remotesFolder
	return nuevo
end

function MatchmakingService.VincularReconnectionService(reconRef: any)
	ReconnectionService = reconRef
end

function MatchmakingService.Iniciar(gameManagerRef: any)
	GameManager = gameManagerRef
	MatchmakingService.Activo = true

	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end

	MatchmakingService.RemoteAccionLobby = asegurarRemote(remotesFolder, "AccionEmparejamientoLobby")
	MatchmakingService.RemoteSincronizarSala = asegurarRemote(remotesFolder, "SincronizarSalaCooperativa")

	if MatchmakingService.RemoteAccionLobby then
		MatchmakingService.RemoteAccionLobby.OnServerEvent:Connect(function(player: Player, accion: any)
			MatchmakingService.ProcesarAccionLobby(player, accion)
		end)
	end

	-- Construir plataforma física decorativa del círculo rúnico en el Lobby
	MatchmakingService.ConstruirPlataformaFisica()

	-- Manejar desconexión de jugadores en salas activas
	Players.PlayerRemoving:Connect(function(player: Player)
		MatchmakingService.JugadoresTeletransportando[player] = nil
		MatchmakingService.RetirarJugadorDeSala(player, true)
	end)

	print("[UMBRA Server] MatchmakingService iniciado en el Santuario (Salas Públicas e Individual).")
end

-- Construye únicamente la estética decorativa del círculo rúnico del santuario (sin detección por pisado)
function MatchmakingService.ConstruirPlataformaFisica()
	local contenedor = Workspace:FindFirstChild("ZonaEmparejamiento")
	if contenedor then
		contenedor:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "ZonaEmparejamiento"
	folder.Parent = Workspace

	-- Círculo base de piedra
	local base = Instance.new("Part")
	base.Name = "PlataformaCirculo"
	base.Shape = Enum.PartType.Cylinder
	base.Size = Vector3.new(0.6, 24, 24)
	base.CFrame = CFrame.new(MatchmakingService.PosicionCirculo) * CFrame.Angles(0, 0, math.rad(90))
	base.Color = Color3.fromRGB(35, 30, 48)
	base.Material = Enum.Material.Cobblestone
	base.Anchored = true
	base.CanCollide = true
	base.Parent = folder
	MatchmakingService.PlataformaVisual = base

	-- Anillo de runas luminosas (Neon púrpura)
	local anillo = Instance.new("Part")
	anillo.Name = "AnilloMagico"
	anillo.Shape = Enum.PartType.Cylinder
	anillo.Size = Vector3.new(0.8, 22, 22)
	anillo.CFrame = CFrame.new(MatchmakingService.PosicionCirculo + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	anillo.Color = Color3.fromRGB(150, 40, 255)
	anillo.Material = Enum.Material.Neon
	anillo.Transparency = 0.45
	anillo.Anchored = true
	anillo.CanCollide = false
	anillo.Parent = folder

	local luz = Instance.new("PointLight")
	luz.Color = Color3.fromRGB(160, 60, 255)
	luz.Range = 26
	luz.Brightness = 2.0
	luz.Parent = anillo

	-- 4 Pads decorativos alrededor del círculo
	for i = 1, 4 do
		local ang = (i - 1) * (math.pi * 2 / 4)
		local px = MatchmakingService.PosicionCirculo.X + math.cos(ang) * 7.5
		local pz = MatchmakingService.PosicionCirculo.Z + math.sin(ang) * 7.5
		local pad = Instance.new("Part")
		pad.Name = string.format("PadSuperviviente_%d", i)
		pad.Shape = Enum.PartType.Cylinder
		pad.Size = Vector3.new(0.5, 4, 4)
		pad.CFrame = CFrame.new(px, MatchmakingService.PosicionCirculo.Y + 0.2, pz) * CFrame.Angles(0, 0, math.rad(90))
		pad.Color = Color3.fromRGB(80, 220, 255)
		pad.Material = Enum.Material.Neon
		pad.Transparency = 0.35
		pad.Anchored = true
		pad.CanCollide = false
		pad.Parent = folder
	end

	-- Cartel Holográfico decorativo suspendido
	local soporteHolo = Instance.new("Part")
	soporteHolo.Name = "SoporteHolograma"
	soporteHolo.Size = Vector3.new(1, 1, 1)
	soporteHolo.Position = MatchmakingService.PosicionCirculo + Vector3.new(0, 12, 0)
	soporteHolo.Transparency = 1
	soporteHolo.Anchored = true
	soporteHolo.CanCollide = false
	soporteHolo.Parent = folder

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BillboardSantuario"
	billboard.Size = UDim2.new(0, 340, 0, 82)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 100
	billboard.Adornee = soporteHolo
	billboard.Parent = soporteHolo
	MatchmakingService.BillboardGui = billboard

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(15, 12, 24)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(150, 50, 255)
	stroke.Thickness = 2
	stroke.Parent = frame

	local titulo = Instance.new("TextLabel")
	titulo.Name = "Titulo"
	titulo.Size = UDim2.new(1, 0, 0, 34)
	titulo.Position = UDim2.new(0, 0, 0, 10)
	titulo.BackgroundTransparency = 1
	titulo.TextColor3 = Color3.fromRGB(240, 220, 255)
	titulo.Font = Enum.Font.GothamBlack
	titulo.TextSize = 16
	titulo.Text = "SANTUARIO DE LA ÚLTIMA LUZ"
	titulo.Parent = frame

	local subtitulo = Instance.new("TextLabel")
	subtitulo.Name = "Subtitulo"
	subtitulo.Size = UDim2.new(1, 0, 0, 24)
	subtitulo.Position = UDim2.new(0, 0, 0, 44)
	subtitulo.BackgroundTransparency = 1
	subtitulo.TextColor3 = Color3.fromRGB(170, 215, 255)
	subtitulo.Font = Enum.Font.GothamMedium
	subtitulo.TextSize = 12
	subtitulo.Text = "Zona segura — Usa el panel de expedición"
	subtitulo.Parent = frame
end

function MatchmakingService.ConstruirEstadoSala(sala: SalaInterna, mensajeAlerta: string?): TiposAlpha.EstadoSalaCooperativa
	local participantesInfo: { TiposAlpha.ParticipanteSalaInfo } = {}
	for _, p in sala.Participantes do
		table.insert(participantesInfo, {
			UserId = p.UserId,
			Nombre = p.Nombre,
			EsResponsable = p.UserId == sala.ResponsableUserId,
			Estado = if p.Player:IsDescendantOf(Players) then p.Estado else "Ausente",
			OrdenLlegada = p.OrdenLlegada,
		})
	end

	return {
		SalaId = sala.SalaId,
		ResponsableUserId = sala.ResponsableUserId,
		PlazasOcupadas = #sala.Participantes,
		CapacidadMaxima = sala.CapacidadMaxima,
		Cerrada = sala.Cerrada,
		IniciandoExpedicion = sala.IniciandoExpedicion,
		Participantes = participantesInfo,
		MensajeAlerta = mensajeAlerta,
	}
end

function MatchmakingService.SincronizarSalaConParticipantes(sala: SalaInterna, mensajeAlerta: string?)
	if not MatchmakingService.RemoteSincronizarSala then return end
	local estado = MatchmakingService.ConstruirEstadoSala(sala, mensajeAlerta)
	for _, p in sala.Participantes do
		if p.Player and p.Player:IsDescendantOf(Players) then
			MatchmakingService.RemoteSincronizarSala:FireClient(p.Player, estado)
		end
	end
end

function MatchmakingService.NotificarFueraDeSala(player: Player, mensajeAlerta: string?)
	if not MatchmakingService.RemoteSincronizarSala then return end
	if player and player:IsDescendantOf(Players) then
		MatchmakingService.RemoteSincronizarSala:FireClient(player, nil, mensajeAlerta)
	end
end

function MatchmakingService.ValidarPlaceExpedicion(): boolean
	return PlacesConfig.ExpeditionPlaceId > 0 and PlacesConfig.ExpeditionPlaceId ~= PlacesConfig.LobbyPlaceId
end

function MatchmakingService.ProcesarAccionLobby(player: Player, accion: any)
	if not player or not player:IsDescendantOf(Players) then return end
	if not PlacesConfig.EsLobby() then return end

	if accion == "IniciarIndividual" then
		MatchmakingService.IniciarExpedicionIndividual(player)
	elseif accion == "BuscarCoop" then
		MatchmakingService.BuscarOUnirseSalaCoop(player)
	elseif accion == "AbandonarSala" then
		MatchmakingService.RetirarJugadorDeSala(player, false)
	elseif accion == "IniciarExpedicionSala" then
		MatchmakingService.IniciarExpedicionSala(player)
	else
		warn(string.format("[Matchmaking] Acción de lobby desconocida '%s' enviada por %s.", tostring(accion), player.Name))
	end
end

function MatchmakingService.IniciarExpedicionIndividual(player: Player)
	if MatchmakingService.JugadoresTeletransportando[player] then return end

	-- Si el jugador estaba en una sala cooperativa, retirarlo limpiamente primero
	MatchmakingService.RetirarJugadorDeSala(player, false)

	if not MatchmakingService.ValidarPlaceExpedicion() then
		warn("[Matchmaking] BLOQUEADO: ExpeditionPlaceId no configurado en PlacesConfig.")
		MatchmakingService.NotificarFueraDeSala(player, "El Place de Expedición no está configurado en PlacesConfig.")
		return
	end

	MatchmakingService.JugadoresTeletransportando[player] = true
	print(string.format("[Matchmaking] Iniciando expedición individual para %s...", player.Name))

	task.spawn(function()
		local exitoReserva, codigoAccesoOErr = pcall(function()
			return TeleportService:ReserveServer(PlacesConfig.ExpeditionPlaceId)
		end)

		if not exitoReserva then
			warn(string.format("[Matchmaking] Error al reservar servidor individual para %s: %s", player.Name, tostring(codigoAccesoOErr)))
			MatchmakingService.JugadoresTeletransportando[player] = nil
			MatchmakingService.NotificarFueraDeSala(player, "No fue posible reservar el servidor de expedición.")
			return
		end

		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = codigoAccesoOErr
		options:SetTeleportData({
			ModoExpedicion = "Solo",
			JugadoresEsperados = { player.UserId },
			ReservedServerAccessCode = codigoAccesoOErr,
		})

		if ReconnectionService and typeof(ReconnectionService.RegistrarSesionEnMemoryStore) == "function" then
			ReconnectionService.RegistrarSesionEnMemoryStore({ player.UserId }, codigoAccesoOErr, "Solo")
		end

		local exitoTP, errTP = pcall(function()
			TeleportService:TeleportAsync(PlacesConfig.ExpeditionPlaceId, { player }, options)
		end)

		if not exitoTP then
			warn(string.format("[Matchmaking] Error en TeleportAsync individual para %s: %s", player.Name, tostring(errTP)))
			MatchmakingService.JugadoresTeletransportando[player] = nil
			MatchmakingService.NotificarFueraDeSala(player, "Error al teletransportar: " .. tostring(errTP))
		else
			print(string.format("[Matchmaking] Teletransporte individual enviado para %s.", player.Name))
		end
	end)
end

function MatchmakingService.BuscarOUnirseSalaCoop(player: Player)
	if MatchmakingService.JugadoresTeletransportando[player] then return end

	-- Si ya está en una sala, re-sincronizar su estado actual
	local salaIdActual = MatchmakingService.SalaPorJugador[player]
	if salaIdActual and MatchmakingService.SalasActivas[salaIdActual] then
		MatchmakingService.SincronizarSalaConParticipantes(MatchmakingService.SalasActivas[salaIdActual])
		return
	end

	-- Buscar sala abierta con mayor número de jugadores actuales; empate: menor TiempoCreacion
	local mejorSala: SalaInterna? = nil
	for _, sala in MatchmakingService.SalasActivas do
		if not sala.Cerrada and not sala.IniciandoExpedicion and #sala.Participantes < sala.CapacidadMaxima then
			if not mejorSala then
				mejorSala = sala
			else
				local cantNueva = #sala.Participantes
				local cantMejor = #mejorSala.Participantes
				if cantNueva > cantMejor or (cantNueva == cantMejor and sala.TiempoCreacion < mejorSala.TiempoCreacion) then
					mejorSala = sala
				end
			end
		end
	end

	if mejorSala then
		table.insert(mejorSala.Participantes, {
			Player = player,
			UserId = player.UserId,
			Nombre = player.Name,
			Estado = "Conectado",
			OrdenLlegada = mejorSala.SiguienteOrden,
		})
		mejorSala.SiguienteOrden += 1
		MatchmakingService.SalaPorJugador[player] = mejorSala.SalaId
		print(string.format("[Matchmaking] %s se unió a la sala pública %s (%d/%d).",
			player.Name, mejorSala.SalaId, #mejorSala.Participantes, mejorSala.CapacidadMaxima))
		MatchmakingService.SincronizarSalaConParticipantes(mejorSala)
	else
		-- Crear nueva sala pública asignando al jugador como creador y responsable
		MatchmakingService.ContadorSalas += 1
		local nuevaSalaId = string.format("SALA_%d", MatchmakingService.ContadorSalas)
		local nuevaSala: SalaInterna = {
			SalaId = nuevaSalaId,
			TiempoCreacion = os.clock(),
			ResponsableUserId = player.UserId,
			CapacidadMaxima = MatchmakingService.MaxJugadores,
			Cerrada = false,
			IniciandoExpedicion = false,
			SiguienteOrden = 2,
			Participantes = {
				{
					Player = player,
					UserId = player.UserId,
					Nombre = player.Name,
					Estado = "Conectado",
					OrdenLlegada = 1,
				},
			},
		}
		MatchmakingService.SalasActivas[nuevaSalaId] = nuevaSala
		MatchmakingService.SalaPorJugador[player] = nuevaSalaId
		print(string.format("[Matchmaking] %s creó nueva sala pública %s (Responsable).", player.Name, nuevaSalaId))
		MatchmakingService.SincronizarSalaConParticipantes(nuevaSala)
	end
end

function MatchmakingService.RetirarJugadorDeSala(player: Player, porDesconexion: boolean)
	local salaId = MatchmakingService.SalaPorJugador[player]
	if not salaId then
		if not porDesconexion then
			MatchmakingService.NotificarFueraDeSala(player, nil)
		end
		return
	end

	MatchmakingService.SalaPorJugador[player] = nil
	local sala = MatchmakingService.SalasActivas[salaId]
	if not sala then
		if not porDesconexion then
			MatchmakingService.NotificarFueraDeSala(player, nil)
		end
		return
	end

	for idx, p in sala.Participantes do
		if p.Player == player or p.UserId == player.UserId then
			table.remove(sala.Participantes, idx)
			break
		end
	end

	if not porDesconexion then
		MatchmakingService.NotificarFueraDeSala(player, nil)
	end

	if #sala.Participantes == 0 then
		MatchmakingService.SalasActivas[salaId] = nil
		print(string.format("[Matchmaking] Sala %s destruida al quedar vacía.", salaId))
		return
	end

	-- Sucesión automática de autoridad: pasa al jugador con menor OrdenLlegada
	if player.UserId == sala.ResponsableUserId then
		local sucesor = sala.Participantes[1]
		for _, p in sala.Participantes do
			if p.OrdenLlegada < sucesor.OrdenLlegada then
				sucesor = p
			end
		end
		sala.ResponsableUserId = sucesor.UserId
		print(string.format("[Matchmaking] Sucesión en sala %s: nuevo responsable %s (UserId: %d).",
			salaId, sucesor.Nombre, sucesor.UserId))
	end

	MatchmakingService.SincronizarSalaConParticipantes(sala)
end

function MatchmakingService.IniciarExpedicionSala(player: Player)
	local salaId = MatchmakingService.SalaPorJugador[player]
	if not salaId then return end

	local sala = MatchmakingService.SalasActivas[salaId]
	if not sala then return end

	-- Validación autoritativa estricta: solo el responsable actual puede iniciar
	if player.UserId ~= sala.ResponsableUserId then
		warn(string.format("[Matchmaking] %s intentó iniciar la sala %s sin ser el responsable.", player.Name, salaId))
		return
	end

	if sala.IniciandoExpedicion then return end

	if not MatchmakingService.ValidarPlaceExpedicion() then
		warn("[Matchmaking] BLOQUEADO: ExpeditionPlaceId no configurado en PlacesConfig.")
		MatchmakingService.SincronizarSalaConParticipantes(sala, "El Place de Expedición no está configurado en PlacesConfig.")
		return
	end

	local listaJugadores: { Player } = {}
	local listaUserIds: { number } = {}
	for _, p in sala.Participantes do
		if p.Player and p.Player:IsDescendantOf(Players) then
			table.insert(listaJugadores, p.Player)
			table.insert(listaUserIds, p.UserId)
		end
	end

	if #listaJugadores == 0 then
		MatchmakingService.SalasActivas[salaId] = nil
		return
	end

	-- Cerrar la sala inmediatamente a nuevos participantes
	sala.Cerrada = true
	sala.IniciandoExpedicion = true
	for _, p in listaJugadores do
		MatchmakingService.JugadoresTeletransportando[p] = true
	end
	MatchmakingService.SincronizarSalaConParticipantes(sala)

	print(string.format("[Matchmaking] Responsable %s inició expedición cooperativa de sala %s (%d jugadores).",
		player.Name, salaId, #listaJugadores))

	task.spawn(function()
		local exitoReserva, codigoAccesoOErr = pcall(function()
			return TeleportService:ReserveServer(PlacesConfig.ExpeditionPlaceId)
		end)

		if not exitoReserva then
			warn(string.format("[Matchmaking] Error al reservar servidor para sala %s: %s", salaId, tostring(codigoAccesoOErr)))
			sala.Cerrada = false
			sala.IniciandoExpedicion = false
			for _, p in listaJugadores do
				MatchmakingService.JugadoresTeletransportando[p] = nil
			end
			MatchmakingService.SincronizarSalaConParticipantes(sala, "Error al reservar servidor de expedición.")
			return
		end

		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = codigoAccesoOErr
		options:SetTeleportData({
			ModoExpedicion = "Coop",
			SalaId = sala.SalaId,
			JugadoresEsperados = listaUserIds,
			ReservedServerAccessCode = codigoAccesoOErr,
		})

		if ReconnectionService and typeof(ReconnectionService.RegistrarSesionEnMemoryStore) == "function" then
			ReconnectionService.RegistrarSesionEnMemoryStore(listaUserIds, codigoAccesoOErr, "Coop")
		end

		local exitoTP, errTP = pcall(function()
			TeleportService:TeleportAsync(PlacesConfig.ExpeditionPlaceId, listaJugadores, options)
		end)

		if not exitoTP then
			warn(string.format("[Matchmaking] Error en TeleportAsync para sala %s: %s", salaId, tostring(errTP)))
			sala.Cerrada = false
			sala.IniciandoExpedicion = false
			for _, p in listaJugadores do
				MatchmakingService.JugadoresTeletransportando[p] = nil
			end
			MatchmakingService.SincronizarSalaConParticipantes(sala, "Fallo al teletransportar la sala: " .. tostring(errTP))
		else
			print(string.format("[Matchmaking] Teletransporte cooperativo de sala %s despachado con éxito.", salaId))
			for _, p in listaJugadores do
				MatchmakingService.SalaPorJugador[p] = nil
			end
			MatchmakingService.SalasActivas[salaId] = nil
		end
	end)
end

return MatchmakingService
