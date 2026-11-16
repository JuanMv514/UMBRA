--!strict
-- ReconnectionService.luau
-- Servicio autoritativo de desconexión, ventana de reconexión (3 minutos) y protección post-reconexión (10s) (Sección 13).

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local ConfigFolder = ReplicatedStorage:WaitForChild("Config")
local ModulesFolder = ReplicatedStorage:WaitForChild("Modules")
local PlacesConfig = require(ConfigFolder:WaitForChild("PlacesConfig") :: ModuleScript)
local TiposAlpha = require(ModulesFolder:WaitForChild("TiposAlpha") :: ModuleScript)

local GameManager = nil :: any
local CombatService = nil :: any
local ProgressionService = nil :: any
local EnemyService = nil :: any

export type SnapshotJugador = {
	UserId: number,
	Nombre: string,
	VidaActual: number,
	VidaMax: number,
	WalkSpeed: number,
	CombatSnapshot: any,
	ProgressionSnapshot: any,
	TiempoSobrevividoHastaDesconexion: number,
	TiempoExpiracion: number,
	HiloExpiracion: thread?,
}

type InfoProteccion = {
	Expira: number,
	AroVisual: Part?,
}

local MAPA_RECONEXION_NOMBRE = "UMBRA_Reconexion_v1"

local ReconnectionService = {
	Activo = false,
	VentanaReconexionSegundos = 180, -- 3 minutos
	DuracionProteccionSegundos = 10, -- 10 segundos
	RadioProteccionStuds = 16,

	ParticipantesAutorizados = {} :: { [number]: { Modo: TiposAlpha.ModoExpedicion, AccessCode: string? } },
	Snapshots = {} :: { [number]: SnapshotJugador },
	JugadoresProtegidos = {} :: { [Player]: InfoProteccion },
	AccesoCodigoServidor = nil :: string?,

	RemoteEstadoLobby = nil :: RemoteEvent?,
	RemoteSolicitarLobby = nil :: RemoteEvent?,
	ConexionHeartbeat = nil :: RBXScriptConnection?,
	CarpetaProteccion = nil :: Folder?,
}

local function obtenerMapaMemoryStore(): MemoryStoreSortedMap?
	local ok, mapa = pcall(function()
		return MemoryStoreService:GetSortedMap(MAPA_RECONEXION_NOMBRE)
	end)
	if ok then
		return mapa
	end
	return nil
end

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

function ReconnectionService.Iniciar(gmRef: any, combatRef: any?, progressionRef: any?, enemyRef: any?)
	GameManager = gmRef
	CombatService = combatRef
	ProgressionService = progressionRef
	EnemyService = enemyRef
	ReconnectionService.Activo = true

	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end

	if PlacesConfig.EsLobby() then
		ReconnectionService.RemoteEstadoLobby = asegurarRemote(remotesFolder, "EstadoReconexionLobby")
		ReconnectionService.RemoteSolicitarLobby = asegurarRemote(remotesFolder, "SolicitarReconexionLobby")

		if ReconnectionService.RemoteSolicitarLobby then
			ReconnectionService.RemoteSolicitarLobby.OnServerEvent:Connect(function(player: Player)
				ReconnectionService.ProcesarSolicitudReconexionLobby(player)
			end)
		end

		Players.PlayerAdded:Connect(function(player: Player)
			task.spawn(ReconnectionService.VerificarReconexionLobby, player)
		end)
		for _, player in Players:GetPlayers() do
			task.spawn(ReconnectionService.VerificarReconexionLobby, player)
		end

		print("[UMBRA Server] ReconnectionService iniciado en modo LOBBY.")
	else
		local carpeta = Workspace:FindFirstChild("ProteccionReconexion")
		if not carpeta then
			carpeta = Instance.new("Folder")
			carpeta.Name = "ProteccionReconexion"
			carpeta.Parent = Workspace
		end
		ReconnectionService.CarpetaProteccion = carpeta :: Folder

		if ReconnectionService.ConexionHeartbeat then
			ReconnectionService.ConexionHeartbeat:Disconnect()
		end
		ReconnectionService.ConexionHeartbeat = RunService.Heartbeat:Connect(function()
			if not ReconnectionService.Activo then return end
			ReconnectionService.ActualizarProtecciones()
		end)

		print("[UMBRA Server] ReconnectionService iniciado en modo EXPEDICIÓN (Ventana 180s / Protección 10s).")
	end
end

-- =========================================================================
-- GESTIÓN DE MEMORYSTORE Y LOBBY
-- =========================================================================

function ReconnectionService.RegistrarSesionEnMemoryStore(userIds: { number }, accessCode: string, modo: TiposAlpha.ModoExpedicion)
	local mapa = obtenerMapaMemoryStore()
	if not mapa then return end

	local expiraUnix = os.time() + 2100
	for _, userId in userIds do
		pcall(function()
			mapa:SetAsync(tostring(userId), {
				AccessCode = accessCode,
				ModoExpedicion = modo,
				ExpiraUnix = expiraUnix,
			}, 2100)
		end)
	end
end

function ReconnectionService.ActualizarVentanaMemoryStore(userId: number, accessCode: string?, modo: TiposAlpha.ModoExpedicion, ttlSegundos: number)
	local mapa = obtenerMapaMemoryStore()
	if not mapa or not accessCode or accessCode == "" then return end

	pcall(function()
		mapa:SetAsync(tostring(userId), {
			AccessCode = accessCode,
			ModoExpedicion = modo,
			ExpiraUnix = os.time() + ttlSegundos,
		}, ttlSegundos)
	end)
end

function ReconnectionService.LimpiarMemoryStoreJugador(userId: number)
	local mapa = obtenerMapaMemoryStore()
	if not mapa then return end
	pcall(function()
		mapa:RemoveAsync(tostring(userId))
	end)
end

function ReconnectionService.VerificarReconexionLobby(player: Player)
	if not PlacesConfig.EsLobby() or not ReconnectionService.RemoteEstadoLobby then return end
	local mapa = obtenerMapaMemoryStore()
	if not mapa then return end

	local ok, data = pcall(function()
		return mapa:GetAsync(tostring(player.UserId))
	end)

	if ok and typeof(data) == "table" and typeof(data.ExpiraUnix) == "number" and typeof(data.AccessCode) == "string" then
		local restante = data.ExpiraUnix - os.time()
		if restante > 0 and restante <= ReconnectionService.VentanaReconexionSegundos then
			local payload: TiposAlpha.DatosReconexionLobby = {
				Disponible = true,
				SegundosRestantes = restante,
				ModoExpedicion = data.ModoExpedicion,
			}
			ReconnectionService.RemoteEstadoLobby:FireClient(player, payload)
			return
		end
	end

	ReconnectionService.RemoteEstadoLobby:FireClient(player, {
		Disponible = false,
		SegundosRestantes = 0,
		ModoExpedicion = nil,
	})
end

function ReconnectionService.ProcesarSolicitudReconexionLobby(player: Player)
	if not PlacesConfig.EsLobby() then return end
	if not player or not player:IsDescendantOf(Players) then return end

	local mapa = obtenerMapaMemoryStore()
	if not mapa then return end

	local ok, data = pcall(function()
		return mapa:GetAsync(tostring(player.UserId))
	end)

	if not ok or typeof(data) ~= "table" or typeof(data.AccessCode) ~= "string" or typeof(data.ExpiraUnix) ~= "number" then
		ReconnectionService.VerificarReconexionLobby(player)
		return
	end

	local restante = data.ExpiraUnix - os.time()
	if restante <= 0 then
		ReconnectionService.LimpiarMemoryStoreJugador(player.UserId)
		ReconnectionService.VerificarReconexionLobby(player)
		return
	end

	if PlacesConfig.ExpeditionPlaceId <= 0 or PlacesConfig.ExpeditionPlaceId == PlacesConfig.LobbyPlaceId then
		return
	end

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = data.AccessCode
	options:SetTeleportData({
		ModoExpedicion = data.ModoExpedicion or "Solo",
		EsReconexion = true,
		ReservedServerAccessCode = data.AccessCode,
	})

	local exitoTP, errTP = pcall(function()
		TeleportService:TeleportAsync(PlacesConfig.ExpeditionPlaceId, { player }, options)
	end)
	if not exitoTP then
		warn(string.format("[ReconnectionService] Error al reconectar a %s: %s", player.Name, tostring(errTP)))
	end
end

-- =========================================================================
-- GESTIÓN DE SNAPSHOTS Y PROTECCIÓN EN EXPEDICIÓN
-- =========================================================================

function ReconnectionService.RegistrarParticipanteAutorizado(userId: number, accessCode: string?, modo: TiposAlpha.ModoExpedicion)
	ReconnectionService.ParticipantesAutorizados[userId] = {
		Modo = modo,
		AccessCode = accessCode,
	}
	if accessCode and accessCode ~= "" then
		ReconnectionService.AccesoCodigoServidor = accessCode
	end
end

function ReconnectionService.TieneSnapshotVigente(userId: number): boolean
	local snap = ReconnectionService.Snapshots[userId]
	return snap ~= nil and os.clock() < snap.TiempoExpiracion
end

function ReconnectionService.HayReconexionesPendientes(): boolean
	local ahora = os.clock()
	for _, snap in ReconnectionService.Snapshots do
		if ahora < snap.TiempoExpiracion then
			return true
		end
	end
	return false
end

function ReconnectionService.EstaJugadorProtegido(player: Player): boolean
	local info = ReconnectionService.JugadoresProtegidos[player]
	return info ~= nil and os.clock() < info.Expira
end

function ReconnectionService.GuardarSnapshotDesconexion(player: Player)
	if not PlacesConfig.EsExpedicion() then return end
	if not player then return end

	local char = player.Character
	local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
	local vidaActual = if hum then math.max(1, hum.Health) else 100
	local vidaMax = if hum then math.max(1, hum.MaxHealth) else 100
	local walkSpeed = if hum then hum.WalkSpeed else 16

	local combatSnap = if CombatService and typeof(CombatService.ExportarSnapshotJugador) == "function"
		then CombatService.ExportarSnapshotJugador(player)
		else nil
	local progSnap = if ProgressionService and typeof(ProgressionService.ExportarSnapshotJugador) == "function"
		then ProgressionService.ExportarSnapshotJugador(player)
		else nil
	local tiempoLogico = if GameManager and typeof(GameManager.ObtenerTiempoLogico) == "function"
		then GameManager.ObtenerTiempoLogico()
		else 0

	local prevSnap = ReconnectionService.Snapshots[player.UserId]
	if prevSnap and prevSnap.HiloExpiracion then
		pcall(task.cancel, prevSnap.HiloExpiracion)
	end

	local userId = player.UserId
	local hiloExp = task.delay(ReconnectionService.VentanaReconexionSegundos, function()
		local snapActual = ReconnectionService.Snapshots[userId]
		if snapActual then
			ReconnectionService.Snapshots[userId] = nil
			ReconnectionService.LimpiarMemoryStoreJugador(userId)
			print(string.format("[ReconnectionService] Ventana de reconexión (180s) expirada para UserId %d.", userId))
			if GameManager and typeof(GameManager.OnReconexionExpirada) == "function" then
				GameManager.OnReconexionExpirada(userId)
			end
		end
	end)

	ReconnectionService.Snapshots[userId] = {
		UserId = userId,
		Nombre = player.Name,
		VidaActual = vidaActual,
		VidaMax = vidaMax,
		WalkSpeed = walkSpeed,
		CombatSnapshot = combatSnap,
		ProgressionSnapshot = progSnap,
		TiempoSobrevividoHastaDesconexion = tiempoLogico,
		TiempoExpiracion = os.clock() + ReconnectionService.VentanaReconexionSegundos,
		HiloExpiracion = hiloExp,
	}

	local auth = ReconnectionService.ParticipantesAutorizados[userId]
	local accessCode = if auth and auth.AccessCode then auth.AccessCode else ReconnectionService.AccesoCodigoServidor
	local modo: TiposAlpha.ModoExpedicion = if auth then auth.Modo else "Solo"
	ReconnectionService.ActualizarVentanaMemoryStore(userId, accessCode, modo, ReconnectionService.VentanaReconexionSegundos)

	print(string.format("[ReconnectionService] Snapshot guardado para %s (UserId: %d). Ventana activa de 180s.", player.Name, userId))
end

local function calcularPosicionSeguraReconexion(playerExcluido: Player): Vector3
	for _, otro in Players:GetPlayers() do
		if otro ~= playerExcluido and otro.Character then
			local root = otro.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = otro.Character:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 then
				local ang = math.random() * math.pi * 2
				local dist = math.random(6, 10)
				return Vector3.new(root.Position.X + math.cos(ang) * dist, root.Position.Y + 1, root.Position.Z + math.sin(ang) * dist)
			end
		end
	end
	return Vector3.new(math.random(-24, 24), 4, math.random(-24, 24))
end

function ReconnectionService.ActivarProteccion(player: Player)
	local existente = ReconnectionService.JugadoresProtegidos[player]
	if existente and existente.AroVisual and existente.AroVisual.Parent then
		existente.AroVisual:Destroy()
	end

	local aro = Instance.new("Part")
	aro.Name = "AroProteccion_" .. player.Name
	aro.Shape = Enum.PartType.Cylinder
	aro.Size = Vector3.new(0.25, ReconnectionService.RadioProteccionStuds * 2, ReconnectionService.RadioProteccionStuds * 2)
	aro.Color = Color3.fromRGB(90, 235, 255)
	aro.Material = Enum.Material.Neon
	aro.Transparency = 0.65
	aro.Anchored = true
	aro.CanCollide = false
	aro.CanQuery = false
	aro.CanTouch = false
	aro.Parent = ReconnectionService.CarpetaProteccion or Workspace

	ReconnectionService.JugadoresProtegidos[player] = {
		Expira = os.clock() + ReconnectionService.DuracionProteccionSegundos,
		AroVisual = aro,
	}
end

function ReconnectionService.IntentarReconectarJugador(player: Player): boolean
	if not PlacesConfig.EsExpedicion() then return false end
	local snap = ReconnectionService.Snapshots[player.UserId]
	if not snap then return false end

	if os.clock() >= snap.TiempoExpiracion then
		ReconnectionService.Snapshots[player.UserId] = nil
		ReconnectionService.LimpiarMemoryStoreJugador(player.UserId)
		return false
	end

	if snap.HiloExpiracion then
		pcall(task.cancel, snap.HiloExpiracion)
	end
	ReconnectionService.Snapshots[player.UserId] = nil

	-- Restaurar combate y progresión
	if CombatService and typeof(CombatService.RestaurarSnapshotJugador) == "function" and snap.CombatSnapshot then
		CombatService.RestaurarSnapshotJugador(player, snap.CombatSnapshot)
	end
	if ProgressionService and typeof(ProgressionService.RestaurarSnapshotJugador) == "function" and snap.ProgressionSnapshot then
		ProgressionService.RestaurarSnapshotJugador(player, snap.ProgressionSnapshot)
	end

	-- Restaurar atributos físicos del personaje y ubicación segura + 10s protección
	task.spawn(function()
		local char = player.Character or player.CharacterAdded:Wait()
		local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
		local root = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		if hum and root then
			hum.MaxHealth = snap.VidaMax
			hum.Health = math.clamp(snap.VidaActual, 1, snap.VidaMax)
			hum.WalkSpeed = snap.WalkSpeed
			root.CFrame = CFrame.new(calcularPosicionSeguraReconexion(player))
			ReconnectionService.ActivarProteccion(player)
		end
	end)

	print(string.format("[ReconnectionService] %s reconectado con éxito dentro de la ventana de 180s. Protección de 10s activa.", player.Name))
	return true
end

function ReconnectionService.ActualizarProtecciones()
	local ahora = os.clock()

	for player, info in ReconnectionService.JugadoresProtegidos do
		if ahora >= info.Expira or not player:IsDescendantOf(Players) then
			if info.AroVisual and info.AroVisual.Parent then
				info.AroVisual:Destroy()
			end
			ReconnectionService.JugadoresProtegidos[player] = nil
			continue
		end

		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		if root then
			if info.AroVisual and info.AroVisual.Parent then
				info.AroVisual.CFrame = CFrame.new(root.Position.X, 0.4, root.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
			end

			-- Repeler enemigos fuera del radio de 16 studs
			if EnemyService and EnemyService.EnemigosActivos then
				for _, enemigo in EnemyService.EnemigosActivos do
					if enemigo.Part and enemigo.Part.Parent then
						local delta = Vector3.new(enemigo.Part.Position.X - root.Position.X, 0, enemigo.Part.Position.Z - root.Position.Z)
						local dist = delta.Magnitude
						if dist < ReconnectionService.RadioProteccionStuds then
							local dir = if dist > 0.05 then delta.Unit else Vector3.new(1, 0, 0)
							local posNueva = Vector3.new(
								root.Position.X + dir.X * (ReconnectionService.RadioProteccionStuds + 0.5),
								enemigo.Part.Position.Y,
								root.Position.Z + dir.Z * (ReconnectionService.RadioProteccionStuds + 0.5)
							)
							enemigo.Part.CFrame = CFrame.new(posNueva)
						end
					end
				end
			end
		end
	end
end

function ReconnectionService.Detener()
	ReconnectionService.Activo = false

	if ReconnectionService.ConexionHeartbeat then
		ReconnectionService.ConexionHeartbeat:Disconnect()
		ReconnectionService.ConexionHeartbeat = nil
	end

	for _, snap in ReconnectionService.Snapshots do
		if snap.HiloExpiracion then
			pcall(task.cancel, snap.HiloExpiracion)
		end
		ReconnectionService.LimpiarMemoryStoreJugador(snap.UserId)
	end
	table.clear(ReconnectionService.Snapshots)

	for userId, _ in ReconnectionService.ParticipantesAutorizados do
		ReconnectionService.LimpiarMemoryStoreJugador(userId)
	end

	for _, info in ReconnectionService.JugadoresProtegidos do
		if info.AroVisual and info.AroVisual.Parent then
			info.AroVisual:Destroy()
		end
	end
	table.clear(ReconnectionService.JugadoresProtegidos)
end

return ReconnectionService
