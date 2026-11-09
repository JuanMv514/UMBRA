--!strict
-- MatchmakingService.luau
-- Manejador autoritativo de emparejamiento, círculo mágico y teletransporte a la expedición en UMBRA.
-- Responsabilidad: Operar exclusivamente en el Lobby (Santuario), registrar participantes en el círculo,
-- gestionar la cuenta regresiva de 15s y enviar al grupo al Place de Expedición mediante TeleportService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local ConfigFolder = ReplicatedStorage:WaitForChild("Config")
local PlacesConfig = require(ConfigFolder:WaitForChild("PlacesConfig") :: ModuleScript)

local GameManager = nil :: any

export type EstadoPortal = {
	Total: number,
	Maximo: number,
	CuentaAtras: number,
	CuentaActiva: boolean,
	MensajeAlerta: string?,
}

local MatchmakingService = {
	Activo = false,
	Participantes = {} :: { [Player]: boolean },
	MaxJugadores = 4,
	TiempoCuentaAtras = 15,
	SegundosRestantes = 15,
	CuentaActiva = false,
	HiloCuenta = nil :: thread?,
	BucleDeteccion = nil :: RBXScriptConnection?,
	PosicionCirculo = Vector3.new(0, 0.5, -45),
	RadioCirculo = 11,
	RemotePortal = nil :: RemoteEvent?,
	BillboardGui = nil :: BillboardGui?,
	TextoContador = nil :: TextLabel?,
	TextoTiempo = nil :: TextLabel?,
	PlataformaVisual = nil :: BasePart?,
	TeletransporteEnProgreso = false,
}

function MatchmakingService.Iniciar(gameManagerRef: any)
	GameManager = gameManagerRef
	MatchmakingService.Activo = true

	-- Asegurar RemoteEvent en ReplicatedStorage.Remotes
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 5)
	if remotesFolder then
		local remote = remotesFolder:FindFirstChild("SincronizarMatchmaking") :: RemoteEvent?
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = "SincronizarMatchmaking"
			remote.Parent = remotesFolder
		end
		MatchmakingService.RemotePortal = remote
	end

	-- Construir plataforma física del círculo mágico en el Lobby
	MatchmakingService.ConstruirPlataformaFisica()

	-- Bucle periódico de detección de presencia de jugadores dentro del radio (0.2s)
	local acumulador = 0
	MatchmakingService.BucleDeteccion = RunService.Heartbeat:Connect(function(dt: number)
		acumulador += dt
		if acumulador >= 0.2 then
			acumulador = 0
			MatchmakingService.ActualizarDeteccion()
		end
	end)

	-- Manejar desconexión de jugadores del círculo
	Players.PlayerRemoving:Connect(function(player)
		if MatchmakingService.Participantes[player] then
			MatchmakingService.Participantes[player] = nil
			MatchmakingService.OnParticipantesCambiados()
		end
	end)

	print("[UMBRA Server] MatchmakingService iniciado en el Santuario (Lobby).")
end

function MatchmakingService.ConstruirPlataformaFisica()
	local contenedor = Workspace:FindFirstChild("ZonaEmparejamiento")
	if contenedor then contenedor:Destroy() end

	contenedor = Instance.new("Folder")
	contenedor.Name = "ZonaEmparejamiento"
	contenedor.Parent = Workspace

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
	base.Parent = contenedor
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
	anillo.Parent = contenedor

	local luz = Instance.new("PointLight")
	luz.Color = Color3.fromRGB(160, 60, 255)
	luz.Range = 26
	luz.Brightness = 2.0
	luz.Parent = anillo

	-- 4 Pads de espera individuales alrededor del círculo
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
		pad.Parent = contenedor
	end

	-- Cartel Holográfico suspendido
	local soporteHolo = Instance.new("Part")
	soporteHolo.Name = "SoporteHolograma"
	soporteHolo.Size = Vector3.new(1, 1, 1)
	soporteHolo.Position = MatchmakingService.PosicionCirculo + Vector3.new(0, 12, 0)
	soporteHolo.Transparency = 1
	soporteHolo.Anchored = true
	soporteHolo.CanCollide = false
	soporteHolo.Parent = contenedor

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BillboardEmparejamiento"
	billboard.Size = UDim2.new(0, 340, 0, 100)
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
	titulo.Size = UDim2.new(1, 0, 0, 26)
	titulo.Position = UDim2.new(0, 0, 0, 6)
	titulo.BackgroundTransparency = 1
	titulo.TextColor3 = Color3.fromRGB(240, 220, 255)
	titulo.Font = Enum.Font.GothamBlack
	titulo.TextSize = 16
	titulo.Text = "PORTAL DE EXPEDICIÓN"
	titulo.Parent = frame

	local txtContador = Instance.new("TextLabel")
	txtContador.Name = "TextoContador"
	txtContador.Size = UDim2.new(1, 0, 0, 28)
	txtContador.Position = UDim2.new(0, 0, 0, 34)
	txtContador.BackgroundTransparency = 1
	txtContador.TextColor3 = Color3.fromRGB(80, 240, 255)
	txtContador.Font = Enum.Font.GothamBlack
	txtContador.TextSize = 20
	txtContador.Text = "JUGADORES: 0 / 4"
	txtContador.Parent = frame
	MatchmakingService.TextoContador = txtContador

	local txtTiempo = Instance.new("TextLabel")
	txtTiempo.Name = "TextoTiempo"
	txtTiempo.Size = UDim2.new(1, 0, 0, 22)
	txtTiempo.Position = UDim2.new(0, 0, 0, 64)
	txtTiempo.BackgroundTransparency = 1
	txtTiempo.TextColor3 = Color3.fromRGB(180, 160, 220)
	txtTiempo.Font = Enum.Font.GothamBold
	txtTiempo.TextSize = 13
	txtTiempo.Text = "Pisa el círculo para unirte"
	txtTiempo.Parent = frame
	MatchmakingService.TextoTiempo = txtTiempo
end

function MatchmakingService.ActualizarDeteccion()
	local posCentro = MatchmakingService.PosicionCirculo
	local radio = MatchmakingService.RadioCirculo
	local huboCambio = false

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 then
				local distXZ = (Vector3.new(root.Position.X, posCentro.Y, root.Position.Z) - posCentro).Magnitude
				local adentro = distXZ <= radio

				if adentro and not MatchmakingService.Participantes[player] then
					local totalActual = MatchmakingService.ObtenerTotalParticipantes()
					if totalActual < MatchmakingService.MaxJugadores then
						MatchmakingService.Participantes[player] = true
						huboCambio = true
						print(string.format("[Matchmaking] %s entró al portal de expedición.", player.Name))
					end
				elseif not adentro and MatchmakingService.Participantes[player] then
					MatchmakingService.Participantes[player] = nil
					huboCambio = true
					print(string.format("[Matchmaking] %s salió del portal de expedición.", player.Name))
				end
			end
		else
			if MatchmakingService.Participantes[player] then
				MatchmakingService.Participantes[player] = nil
				huboCambio = true
			end
		end
	end

	if huboCambio then
		MatchmakingService.OnParticipantesCambiados()
	end
end

function MatchmakingService.ObtenerTotalParticipantes(): number
	local count = 0
	for _ in MatchmakingService.Participantes do
		count += 1
	end
	return count
end

function MatchmakingService.OnParticipantesCambiados()
	local total = MatchmakingService.ObtenerTotalParticipantes()

	if total == 0 then
		MatchmakingService.CancelarCuentaAtras()
	elseif total >= 4 then
		-- Si se llena el cupo (4/4), acelerar inicio a 3 segundos
		if not MatchmakingService.CuentaActiva or MatchmakingService.SegundosRestantes > 3 then
			MatchmakingService.SegundosRestantes = 3
			MatchmakingService.IniciarCuentaAtras()
		end
	elseif total >= 1 and not MatchmakingService.CuentaActiva then
		MatchmakingService.SegundosRestantes = MatchmakingService.TiempoCuentaAtras
		MatchmakingService.IniciarCuentaAtras()
	end

	MatchmakingService.NotificarEstado()
end

function MatchmakingService.IniciarCuentaAtras()
	if MatchmakingService.CuentaActiva and MatchmakingService.HiloCuenta then return end
	MatchmakingService.CuentaActiva = true

	MatchmakingService.HiloCuenta = task.spawn(function()
		while MatchmakingService.CuentaActiva and MatchmakingService.SegundosRestantes > 0 do
			MatchmakingService.NotificarEstado()
			task.wait(1)
			if not MatchmakingService.CuentaActiva then break end
			MatchmakingService.SegundosRestantes -= 1
		end

		if MatchmakingService.CuentaActiva and MatchmakingService.SegundosRestantes <= 0 then
			MatchmakingService.TransportarParticipantes()
		end
	end)
end

function MatchmakingService.CancelarCuentaAtras()
	MatchmakingService.CuentaActiva = false
	if MatchmakingService.HiloCuenta and MatchmakingService.HiloCuenta ~= coroutine.running() then
		task.cancel(MatchmakingService.HiloCuenta)
	end
	MatchmakingService.HiloCuenta = nil
	MatchmakingService.SegundosRestantes = MatchmakingService.TiempoCuentaAtras
	MatchmakingService.NotificarEstado()
	print("[Matchmaking] Portal vacío. Cuenta regresiva cancelada.")
end

function MatchmakingService.TransportarParticipantes()
	MatchmakingService.CuentaActiva = false
	if MatchmakingService.HiloCuenta and MatchmakingService.HiloCuenta ~= coroutine.running() then
		task.cancel(MatchmakingService.HiloCuenta)
	end
	MatchmakingService.HiloCuenta = nil

	local lista = {}
	for player in MatchmakingService.Participantes do
		table.insert(lista, player)
	end

	if #lista == 0 then
		MatchmakingService.CancelarCuentaAtras()
		return
	end

	-- COMPROBACIÓN ESTRICTA DEL DESTINO:
	-- No simular teletransportes en el mismo lugar ni inventar PlaceIds.
	if PlacesConfig.ExpeditionPlaceId <= 0 or PlacesConfig.ExpeditionPlaceId == PlacesConfig.LobbyPlaceId then
		warn("[Matchmaking] ==========================================================================")
		warn("[Matchmaking] BLOQUEADO: El Place de Expedición todavía no está configurado.")
		warn(string.format("[Matchmaking] PlaceId actual del Lobby: %d | ExpeditionPlaceId configurado: %d", PlacesConfig.LobbyPlaceId, PlacesConfig.ExpeditionPlaceId))
		warn("[Matchmaking] Se requiere crear un segundo Place en la experiencia y registrar su PlaceId real en PlacesConfig.luau.")
		warn("[Matchmaking] ==========================================================================")

		MatchmakingService.MostrarAlerta(
			"EXPEDICIÓN PENDIENTE (FALTA PLACE ID)",
			"No se puede teletransportar: el Place de supervivencia no está configurado en PlacesConfig."
		)
		MatchmakingService.CancelarCuentaAtras()
		return
	end

	-- Evitar ejecuciones duplicadas de teletransporte
	if MatchmakingService.TeletransporteEnProgreso then
		return
	end
	MatchmakingService.TeletransporteEnProgreso = true

	print(string.format("[Matchmaking] Iniciando teletransporte de %d jugadores hacia el Place %d...", #lista, PlacesConfig.ExpeditionPlaceId))

	-- Iniciar teletransporte autoritativo a un servidor reservado del Place de Expedición
	task.spawn(function()
		local exitoReserva, codigoAccesoOErr = pcall(function()
			return TeleportService:ReserveServer(PlacesConfig.ExpeditionPlaceId)
		end)

		if not exitoReserva then
			warn(string.format("[Matchmaking] Error al reservar servidor para Place %d: %s", PlacesConfig.ExpeditionPlaceId, tostring(codigoAccesoOErr)))
			MatchmakingService.MostrarAlerta("ERROR DE RESERVA", "No fue posible crear el servidor de expedición.")
			MatchmakingService.TeletransporteEnProgreso = false
			MatchmakingService.CancelarCuentaAtras()
			return
		end

		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = codigoAccesoOErr

		local exitoTP, errTP = pcall(function()
			TeleportService:TeleportAsync(PlacesConfig.ExpeditionPlaceId, lista, options)
		end)

		if not exitoTP then
			warn(string.format("[Matchmaking] Error en TeleportService: %s", tostring(errTP)))
			MatchmakingService.MostrarAlerta("FALLO DE TELETRANSPORTE", tostring(errTP))
		else
			print("[Matchmaking] Teletransporte enviado con éxito.")
		end

		table.clear(MatchmakingService.Participantes)
		MatchmakingService.TeletransporteEnProgreso = false
		MatchmakingService.NotificarEstado()
	end)
end

function MatchmakingService.MostrarAlerta(textoHolo: string, mensajeClient: string)
	if MatchmakingService.TextoTiempo then
		MatchmakingService.TextoTiempo.Text = textoHolo
		MatchmakingService.TextoTiempo.TextColor3 = Color3.fromRGB(255, 70, 70)
	end

	if MatchmakingService.RemotePortal then
		MatchmakingService.RemotePortal:FireAllClients({
			Total = MatchmakingService.ObtenerTotalParticipantes(),
			Maximo = MatchmakingService.MaxJugadores,
			CuentaAtras = MatchmakingService.SegundosRestantes,
			CuentaActiva = false,
			MensajeAlerta = mensajeClient,
		})
	end

	task.delay(5, function()
		if not MatchmakingService.CuentaActiva and MatchmakingService.TextoTiempo then
			MatchmakingService.TextoTiempo.Text = "Pisa el círculo para unirte"
			MatchmakingService.TextoTiempo.TextColor3 = Color3.fromRGB(180, 160, 220)
		end
	end)
end

function MatchmakingService.NotificarEstado()
	local total = MatchmakingService.ObtenerTotalParticipantes()

	if MatchmakingService.TextoContador then
		MatchmakingService.TextoContador.Text = string.format("JUGADORES: %d / %d", total, MatchmakingService.MaxJugadores)
		if total == 4 then
			MatchmakingService.TextoContador.TextColor3 = Color3.fromRGB(100, 255, 140)
		else
			MatchmakingService.TextoContador.TextColor3 = Color3.fromRGB(80, 240, 255)
		end
	end

	if MatchmakingService.TextoTiempo then
		if MatchmakingService.CuentaActiva then
			MatchmakingService.TextoTiempo.Text = string.format("INICIANDO EN %d SEGUNDOS...", MatchmakingService.SegundosRestantes)
			MatchmakingService.TextoTiempo.TextColor3 = Color3.fromRGB(255, 220, 80)
		else
			MatchmakingService.TextoTiempo.Text = "Pisa el círculo para unirte"
			MatchmakingService.TextoTiempo.TextColor3 = Color3.fromRGB(180, 160, 220)
		end
	end

	if MatchmakingService.RemotePortal then
		MatchmakingService.RemotePortal:FireAllClients({
			Total = total,
			Maximo = MatchmakingService.MaxJugadores,
			CuentaAtras = MatchmakingService.SegundosRestantes,
			CuentaActiva = MatchmakingService.CuentaActiva,
			MensajeAlerta = nil,
		})
	end
end

return MatchmakingService
