--!strict
-- BossService.luau
-- Servicio autoritativo del Jefe Final del minuto 30 (Secciones 4, 9 y 11) en UMBRA: La Última Luz.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local ConfigFolder = ReplicatedStorage:WaitForChild("Config")
local ModulesFolder = ReplicatedStorage:WaitForChild("Modules")
local JefeConfig = require(ConfigFolder:WaitForChild("JefeConfig") :: ModuleScript)
local TiposAlpha = require(ModulesFolder:WaitForChild("TiposAlpha") :: ModuleScript)

local EnemyService = nil :: any
local GameManager = nil :: any
local ReconnectionService = nil :: any

local BossService = {
	Activo = false,
	JefeInvocado = false,
	JefeActivo = false,
	JefeId = JefeConfig.Id,
	JefesDerrotadosSesion = 0,
	HiloIA = nil :: thread?,
	ConexionHeartbeat = nil :: RBXScriptConnection?,
	RemoteSincronizarJefe = nil :: RemoteEvent?,
	CarpetaEfectosJefe = nil :: Folder?,
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

local function obtenerJugadoresVivosConPos(): { { Player: Player, Humanoid: Humanoid, Root: BasePart } }
	local lista = {}
	for _, player in Players:GetPlayers() do
		if GameManager and GameManager.JugadoresVivos and GameManager.JugadoresVivos[player] == false then
			continue
		end
		if ReconnectionService and typeof(ReconnectionService.EstaJugadorProtegido) == "function" and ReconnectionService.EstaJugadorProtegido(player) then
			continue
		end
		local char = player.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hum and root and hum.Health > 0 then
				table.insert(lista, { Player = player, Humanoid = hum, Root = root })
			end
		end
	end
	return lista
end

local function crearTelegrafoCirculo(posicion: Vector3, radio: number, duracion: number): Part
	local ring = Instance.new("Part")
	ring.Name = "TelegrafoJefe"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.25, radio * 2, radio * 2)
	ring.Color = Color3.fromRGB(255, 35, 55)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.48
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CFrame = CFrame.new(posicion.X, 0.4, posicion.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = BossService.CarpetaEfectosJefe or Workspace
	Debris:AddItem(ring, duracion + 0.15)
	return ring
end

local function crearTelegrafoLinea(origen: Vector3, direccion: Vector3, alcance: number, duracion: number)
	local centro = origen + direccion * (alcance * 0.5)
	local linea = Instance.new("Part")
	linea.Name = "TelegrafoLineaJefe"
	linea.Size = Vector3.new(1.1, 0.2, alcance)
	linea.Color = Color3.fromRGB(255, 45, 70)
	linea.Material = Enum.Material.Neon
	linea.Transparency = 0.52
	linea.Anchored = true
	linea.CanCollide = false
	linea.CanQuery = false
	linea.CanTouch = false
	linea.CFrame = CFrame.lookAt(Vector3.new(centro.X, 0.6, centro.Z), Vector3.new(origen.X + direccion.X * alcance, 0.6, origen.Z + direccion.Z * alcance))
	linea.Parent = BossService.CarpetaEfectosJefe or Workspace
	Debris:AddItem(linea, duracion + 0.1)
end

function BossService.Iniciar(enemyServiceRef: any, gameManagerRef: any)
	BossService.Detener()

	EnemyService = enemyServiceRef
	GameManager = gameManagerRef
	BossService.Activo = true
	BossService.JefeInvocado = false
	BossService.JefeActivo = false
	BossService.JefesDerrotadosSesion = 0

	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end
	BossService.RemoteSincronizarJefe = asegurarRemote(remotesFolder, "SincronizarJefeFinal")

	local carpeta = Workspace:FindFirstChild("EfectosJefe")
	if not carpeta then
		carpeta = Instance.new("Folder")
		carpeta.Name = "EfectosJefe"
		carpeta.Parent = Workspace
	end
	BossService.CarpetaEfectosJefe = carpeta :: Folder

	if EnemyService and typeof(EnemyService.EstablecerCallbacksJefe) == "function" then
		EnemyService.EstablecerCallbacksJefe(
			function(vidaActual: number, vidaMax: number)
				BossService.NotificarEstadoHUD(true, vidaActual, vidaMax)
			end,
			function()
				BossService.OnJefeDerrotado()
			end
		)
	end

	BossService.ConexionHeartbeat = RunService.Heartbeat:Connect(function()
		if not BossService.Activo or BossService.JefeInvocado then return end
		if not GameManager or typeof(GameManager.ObtenerEstado) ~= "function" then return end
		if GameManager.ObtenerEstado() ~= "Playing" then return end

		local tiempoLogico = if typeof(GameManager.ObtenerTiempoLogico) == "function"
			then GameManager.ObtenerTiempoLogico()
			else 0

		if tiempoLogico >= JefeConfig.MinutoAparicionSegundos then
			BossService.InvocarJefeFinal()
		end
	end)

	print("[UMBRA Server] BossService iniciado (Vigilando aparición en minuto 30).")
end

function BossService.EstaJefeActivo(): boolean
	return BossService.JefeActivo
end

function BossService.VincularReconnectionService(reconRef: any)
	ReconnectionService = reconRef
end

function BossService.ObtenerJefesDerrotados(): number
	return BossService.JefesDerrotadosSesion
end

function BossService.NotificarEstadoHUD(activo: boolean, vidaActual: number, vidaMax: number)
	if not BossService.RemoteSincronizarJefe then return end
	local payload: TiposAlpha.EstadoJefeHUD = {
		Activo = activo,
		Nombre = JefeConfig.Nombre,
		VidaActual = math.max(0, math.round(vidaActual)),
		VidaMax = math.max(1, math.round(vidaMax)),
	}
	BossService.RemoteSincronizarJefe:FireAllClients(payload)
end

function BossService.InvocarJefeFinal()
	if BossService.JefeInvocado or not EnemyService then return end
	BossService.JefeInvocado = true
	BossService.JefeActivo = true

	local vivos = obtenerJugadoresVivosConPos()
	local centroRef = if #vivos > 0 then vivos[1].Root.Position else Vector3.zero
	local angulo = math.random() * math.pi * 2
	local posSpawn = Vector3.new(
		centroRef.X + math.cos(angulo) * 32,
		JefeConfig.Tamanio.Y * 0.5,
		centroRef.Z + math.sin(angulo) * 32
	)

	local totalVivos = math.max(1, #vivos)
	local vidaMax = JefeConfig.VidaBase * (1 + (totalVivos - 1) * JefeConfig.EscaladoVidaPorJugadorExtra)

	local part = Instance.new("Part")
	part.Name = JefeConfig.Id
	part.Size = JefeConfig.Tamanio
	part.Color = JefeConfig.Color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.CFrame = CFrame.new(posSpawn)

	local highlight = Instance.new("Highlight")
	highlight.FillColor = JefeConfig.Color
	highlight.OutlineColor = Color3.fromRGB(255, 50, 80)
	highlight.FillTransparency = 0.2
	highlight.OutlineTransparency = 0
	highlight.Adornee = part
	highlight.Parent = part

	local luz = Instance.new("PointLight")
	luz.Color = Color3.fromRGB(190, 40, 255)
	luz.Range = 28
	luz.Brightness = 2.5
	luz.Parent = part

	EnemyService.RegistrarEntidadJefe({
		Id = JefeConfig.Id,
		TipoId = JefeConfig.Id,
		Modelo = nil :: any,
		Part = part,
		VidaActual = vidaMax,
		VidaMax = vidaMax,
		Velocidad = JefeConfig.VelocidadBase,
		VelocidadBase = JefeConfig.VelocidadBase,
		FinRalentizacion = 0,
		Danio = JefeConfig.DanioContacto,
		XpOtorga = 0,
		EsJefe = true,
	})

	BossService.NotificarEstadoHUD(true, vidaMax, vidaMax)
	print(string.format("[UMBRA Server] ¡JEFE FINAL INVOCADO! %s (VidaMax: %d)", JefeConfig.Nombre, math.round(vidaMax)))

	-- Bucle de IA alternando los 3 patrones de ataque con telégrafos visuales
	BossService.HiloIA = task.spawn(function()
		local indicePatron = 0
		local ordenPatrones = { "CuerpoACuerpo", "ADistancia", "AtaqueArea" }

		while BossService.Activo and BossService.JefeActivo do
			task.wait(JefeConfig.EnfriamientoEntrePatrones)
			if not BossService.Activo or not BossService.JefeActivo then break end

			local jefeEnt = EnemyService.EnemigosActivos[JefeConfig.Id]
			if not jefeEnt or not jefeEnt.Part or not jefeEnt.Part.Parent then break end

			indicePatron = (indicePatron % #ordenPatrones) + 1
			local patron = ordenPatrones[indicePatron]

			if patron == "CuerpoACuerpo" then
				BossService.EjecutarPatronCuerpoACuerpo(jefeEnt.Part)
			elseif patron == "ADistancia" then
				BossService.EjecutarPatronADistancia(jefeEnt.Part)
			elseif patron == "AtaqueArea" then
				BossService.EjecutarPatronAtaqueArea()
			end
		end
	end)
end

-- Patrón 1: Barrido Cuerpo a Cuerpo con telégrafo circular
function BossService.EjecutarPatronCuerpoACuerpo(jefePart: BasePart)
	local cfg = JefeConfig.Patrones.CuerpoACuerpo
	local posOrigen = jefePart.Position
	crearTelegrafoCirculo(posOrigen, cfg.Radio, cfg.TiempoTelegrafo)

	task.wait(cfg.TiempoTelegrafo)
	if not BossService.Activo or not BossService.JefeActivo or not jefePart.Parent then return end

	local posImpacto = jefePart.Position
	for _, jugador in obtenerJugadoresVivosConPos() do
		local distXZ = (Vector3.new(jugador.Root.Position.X, posImpacto.Y, jugador.Root.Position.Z) - posImpacto).Magnitude
		if distXZ <= cfg.Radio then
			jugador.Humanoid:TakeDamage(cfg.Danio)
		end
	end
end

-- Patrón 2: Ráfaga de 3 orbes oscuros a distancia con telégrafos lineales
function BossService.EjecutarPatronADistancia(jefePart: BasePart)
	local cfg = JefeConfig.Patrones.ADistancia
	local vivos = obtenerJugadoresVivosConPos()
	if #vivos == 0 then return end

	local origen = jefePart.Position
	local objetivo = vivos[math.random(1, #vivos)]
	local dirBase = Vector3.new(objetivo.Root.Position.X - origen.X, 0, objetivo.Root.Position.Z - origen.Z)
	if dirBase.Magnitude < 0.1 then return end
	dirBase = dirBase.Unit

	local direcciones: { Vector3 } = {}
	local mitad = (cfg.CantidadOrbes - 1) / 2
	for i = 0, cfg.CantidadOrbes - 1 do
		local angRad = math.rad((i - mitad) * cfg.AnguloDispersionGrados)
		local cf = CFrame.Angles(0, angRad, 0)
		local dir = (cf * dirBase).Unit
		table.insert(direcciones, dir)
		crearTelegrafoLinea(origen, dir, cfg.Alcance, cfg.TiempoTelegrafo)
	end

	task.wait(cfg.TiempoTelegrafo)
	if not BossService.Activo or not BossService.JefeActivo or not jefePart.Parent then return end

	local posLanzamiento = Vector3.new(jefePart.Position.X, 2.0, jefePart.Position.Z)
	for _, dir in direcciones do
		task.spawn(function()
			local orbe = Instance.new("Part")
			orbe.Name = "OrbeJefe"
			orbe.Shape = Enum.PartType.Ball
			orbe.Size = Vector3.new(2.2, 2.2, 2.2)
			orbe.Color = Color3.fromRGB(200, 30, 90)
			orbe.Material = Enum.Material.Neon
			orbe.Anchored = true
			orbe.CanCollide = false
			orbe.CanQuery = false
			orbe.CanTouch = false
			orbe.Position = posLanzamiento
			orbe.Parent = BossService.CarpetaEfectosJefe or Workspace

			local golpeados: { [Player]: boolean } = {}
			local recorrida = 0
			while recorrida < cfg.Alcance and BossService.Activo and orbe.Parent do
				local dt = task.wait(0.03)
				local paso = cfg.VelocidadProyectil * dt
				recorrida += paso
				orbe.Position += dir * paso

				for _, jugador in obtenerJugadoresVivosConPos() do
					if not golpeados[jugador.Player] then
						local d = (Vector3.new(jugador.Root.Position.X, orbe.Position.Y, jugador.Root.Position.Z) - orbe.Position).Magnitude
						if d <= 2.8 then
							golpeados[jugador.Player] = true
							jugador.Humanoid:TakeDamage(cfg.Danio)
						end
					end
				end
			end

			if orbe.Parent then
				orbe:Destroy()
			end
		end)
	end
end

-- Patrón 3: Cataclismo de 3 zonas en el suelo con telégrafo anticipado
function BossService.EjecutarPatronAtaqueArea()
	local cfg = JefeConfig.Patrones.AtaqueArea
	local vivos = obtenerJugadoresVivosConPos()
	if #vivos == 0 then return end

	local zonasPos: { Vector3 } = {}
	for i = 1, cfg.CantidadZonas do
		local objetivo = vivos[((i - 1) % #vivos) + 1]
		local offset = if i > #vivos
			then Vector3.new(math.random(-10, 10), 0, math.random(-10, 10))
			else Vector3.zero
		local pos = Vector3.new(objetivo.Root.Position.X + offset.X, 0.5, objetivo.Root.Position.Z + offset.Z)
		table.insert(zonasPos, pos)
		crearTelegrafoCirculo(pos, cfg.RadioZona, cfg.TiempoTelegrafo)
	end

	task.wait(cfg.TiempoTelegrafo)
	if not BossService.Activo or not BossService.JefeActivo then return end

	for _, posZona in zonasPos do
		for _, jugador in obtenerJugadoresVivosConPos() do
			local distXZ = (Vector3.new(jugador.Root.Position.X, posZona.Y, jugador.Root.Position.Z) - posZona).Magnitude
			if distXZ <= cfg.RadioZona then
				jugador.Humanoid:TakeDamage(cfg.Danio)
			end
		end
	end
end

function BossService.OnJefeDerrotado()
	if not BossService.JefeActivo then return end
	BossService.JefeActivo = false
	BossService.JefesDerrotadosSesion += 1

	BossService.NotificarEstadoHUD(false, 0, 1)
	print("[UMBRA Server] ¡JEFE FINAL DERROTADO! Declarando Victoria de la expedición.")

	if GameManager and typeof(GameManager.CambiarEstado) == "function" then
		GameManager.CambiarEstado("Victory")
	end
end

function BossService.Detener()
	BossService.Activo = false
	BossService.JefeActivo = false

	if BossService.ConexionHeartbeat then
		BossService.ConexionHeartbeat:Disconnect()
		BossService.ConexionHeartbeat = nil
	end

	if BossService.HiloIA and BossService.HiloIA ~= coroutine.running() then
		pcall(task.cancel, BossService.HiloIA)
	end
	BossService.HiloIA = nil

	if BossService.CarpetaEfectosJefe then
		BossService.CarpetaEfectosJefe:ClearAllChildren()
	end

	BossService.NotificarEstadoHUD(false, 0, 1)
end

return BossService
