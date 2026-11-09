--!strict
-- MatchmakingService.luau
-- Manejador autoritativo de emparejamiento, circulo magico y transporte a la arena de supervivencia.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameManager = nil :: any
local SpawnerService = nil :: any
local CombatService = nil :: any

export type EstadoPortal = {
	Total: number,
	Maximo: number,
	CuentaAtras: number,
	CuentaActiva: boolean,
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
	PosicionArena = Vector3.new(0, 2, 60),
	RemotePortal = nil :: RemoteEvent?,
	BillboardGui = nil :: BillboardGui?,
	TextoContador = nil :: TextLabel?,
	TextoTiempo = nil :: TextLabel?,
	PlataformaVisual = nil :: BasePart?,
}

function MatchmakingService.Iniciar(gameManagerRef: any, spawnerRef: any, combatRef: any)
	GameManager = gameManagerRef
	SpawnerService = spawnerRef
	CombatService = combatRef
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

	-- Construir plataforma fisica del circulo magico
	MatchmakingService.ConstruirPlataformaFisica()

	-- Spawner y combate inician en pausa hasta entrar a la arena
	if SpawnerService and SpawnerService.Detener then
		SpawnerService.Detener()
	end

	-- Bucle periodico de deteccion (0.2s)
	local acumulador = 0
	MatchmakingService.BucleDeteccion = RunService.Heartbeat:Connect(function(dt: number)
		acumulador += dt
		if acumulador >= 0.2 then
			acumulador = 0
			MatchmakingService.ActualizarDeteccion()
		end
	end)

	-- Manejar desconexion
	Players.PlayerRemoving:Connect(function(player)
		if MatchmakingService.Participantes[player] then
			MatchmakingService.Participantes[player] = nil
			MatchmakingService.OnParticipantesCambiados()
		end
	end)

	print("[UMBRA Server] MatchmakingService iniciado con circulo magico de emparejamiento.")
end

function MatchmakingService.ConstruirPlataformaFisica()
	local contenedor = Workspace:FindFirstChild("ZonaEmparejamiento")
	if contenedor then contenedor:Destroy() end

	contenedor = Instance.new("Folder")
	contenedor.Name = "ZonaEmparejamiento"
	contenedor.Parent = Workspace

	-- Circulo base de piedra
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

	-- Anillo de runas luminosas (Neon purpura)
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

	-- 4 Pads de espera individuales alrededor del circulo
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

	-- Cartel Holografico suspendido
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
	billboard.Size = UDim2.new(0, 320, 0, 100)
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
	titulo.Text = "CIRCULO DE SUPERVIVENCIA"
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
	txtTiempo.Text = "Pisa el circulo para unirte"
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
						print(string.format("[Matchmaking] %s entro al circulo magico.", player.Name))
					end
				elseif not adentro and MatchmakingService.Participantes[player] then
					MatchmakingService.Participantes[player] = nil
					huboCambio = true
					print(string.format("[Matchmaking] %s salio del circulo magico.", player.Name))
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

	-- Manejar cuenta regresiva
	if total == 0 then
		MatchmakingService.CancelarCuentaAtras()
	elseif total >= 4 then
		-- Si se alcanza el maximo de 4, acelerar inicio inmediato o cuenta de 3s
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
	print("[Matchmaking] Circulo vacio. Cuenta regresiva cancelada.")
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

	print(string.format("[Matchmaking] ¡Partida confirmada! Transportando %d supervivientes a la Arena de Supervivencia...", #lista))

	-- 1. Transportar fisicamente a la arena de combate
	for i, player in lista do
		local character = player.Character
		if character then
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local offset = Vector3.new((i - 1) * 4, 3, 0)
				root.CFrame = CFrame.new(MatchmakingService.PosicionArena + offset)
			end
		end
	end

	-- 2. Limpiar participantes del portal para futuras partidas
	table.clear(MatchmakingService.Participantes)
	MatchmakingService.NotificarEstado()

	-- 3. Iniciar sistemas de supervivencia autoritativos en GameManager, Spawner y Combate
	if GameManager and GameManager.CambiarEstado then
		GameManager.CambiarEstado("Playing")
	end

	if SpawnerService and SpawnerService.Iniciar then
		SpawnerService.Iniciar(nil)
	end
end

function MatchmakingService.NotificarEstado()
	local total = MatchmakingService.ObtenerTotalParticipantes()

	-- Actualizar cartel holografico
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
			MatchmakingService.TextoTiempo.Text = "Pisa el circulo para unirte"
			MatchmakingService.TextoTiempo.TextColor3 = Color3.fromRGB(180, 160, 220)
		end
	end

	-- Sincronizar hacia los clientes
	if MatchmakingService.RemotePortal then
		MatchmakingService.RemotePortal:FireAllClients({
			Total = total,
			Maximo = MatchmakingService.MaxJugadores,
			CuentaAtras = MatchmakingService.SegundosRestantes,
			CuentaActiva = MatchmakingService.CuentaActiva,
		})
	end
end

return MatchmakingService
