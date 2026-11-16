--!strict
-- EnemyService.luau
-- Manejador de ciclo de vida, físicas ligeras y daño de la horda en UMBRA.
-- Diseñado para alto rendimiento (sin Humanoids pesados).
-- Responsabilidad: Generar, mover, dañar y limpiar autoritativamente a las entidades enemigas.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ConfigFolder = ReplicatedStorage:WaitForChild("Config")
local EnemigosConfig = require(ConfigFolder:WaitForChild("EnemigosConfig") :: ModuleScript)
local JefeConfig = require(ConfigFolder:WaitForChild("JefeConfig") :: ModuleScript)

export type EnemigoInstancia = {
	Id: string,
	TipoId: string,
	Modelo: Model,
	Part: Part,
	VidaActual: number,
	VidaMax: number,
	Velocidad: number,
	VelocidadBase: number,
	FinRalentizacion: number,
	Danio: number,
	XpOtorga: number,
	EsJefe: boolean?,
}

local EnemyService = {
	Activo = false,
	EnemigosActivos = {} :: { [string]: EnemigoInstancia },
	CarpetaContenedora = nil :: Folder?,
	ContadorIds = 0,
	BucleConexion = nil :: RBXScriptConnection?,
	CallbackEnemigoEliminado = nil :: ((tipoId: string, posicion: Vector3, xpOtorga: number) -> ())?,
	CallbackDanioJefe = nil :: ((vidaActual: number, vidaMax: number) -> ())?,
	CallbackJefeEliminado = nil :: (() -> ())?,
	ReconnectionService = nil :: any,
}

function EnemyService.VincularReconnectionService(reconRef: any)
	EnemyService.ReconnectionService = reconRef
end

function EnemyService.EstablecerCallbackEliminacion(callback: ((tipoId: string, posicion: Vector3, xpOtorga: number) -> ())?)
	EnemyService.CallbackEnemigoEliminado = callback
end

function EnemyService.EstablecerCallbacksJefe(onDanio: ((number, number) -> ())?, onEliminado: (() -> ())?)
	EnemyService.CallbackDanioJefe = onDanio
	EnemyService.CallbackJefeEliminado = onEliminado
end

function EnemyService.RegistrarEntidadJefe(instancia: EnemigoInstancia)
	if not EnemyService.Activo then return end
	instancia.EsJefe = true
	if EnemyService.CarpetaContenedora and instancia.Part then
		instancia.Part.Parent = EnemyService.CarpetaContenedora
	end
	EnemyService.EnemigosActivos[instancia.Id] = instancia
end

-- Inicializa el contenedor en Workspace y el bucle de movimiento
function EnemyService.Iniciar()
	if EnemyService.Activo then return end
	EnemyService.Activo = true

	local carpeta = Workspace:FindFirstChild("HordaEnemigos")
	if not carpeta then
		carpeta = Instance.new("Folder")
		carpeta.Name = "HordaEnemigos"
		carpeta.Parent = Workspace
	end
	EnemyService.CarpetaContenedora = carpeta :: Folder

	-- Bucle centralizado de movimiento en el servidor (RunService.Heartbeat)
	if not EnemyService.BucleConexion then
		EnemyService.BucleConexion = RunService.Heartbeat:Connect(function(dt: number)
			if not EnemyService.Activo then return end
			EnemyService.ActualizarMovimiento(dt)
		end)
	end

	print("[UMBRA Server] EnemyService iniciado (Sistema de Horda Ligero activo).")
end

-- Encuentra la posición del jugador más cercano
local function obtenerPosicionObjetivo(posEnemigo: Vector3): Vector3?
	local masCercano: Vector3? = nil
	local menorDistancia = math.huge

	for _, player in Players:GetPlayers() do
		if EnemyService.ReconnectionService and typeof(EnemyService.ReconnectionService.EstaJugadorProtegido) == "function" then
			if EnemyService.ReconnectionService.EstaJugadorProtegido(player) then
				continue
			end
		end
		local character = player.Character
		if character then
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 then
				local dist = (root.Position - posEnemigo).Magnitude
				if dist < menorDistancia then
					menorDistancia = dist
					masCercano = root.Position
				end
			end
		end
	end

	return masCercano
end

-- Actualiza la posición de todos los enemigos hacia el jugador
function EnemyService.ActualizarMovimiento(dt: number)
	if not EnemyService.Activo then return end

	for id, enemigo in EnemyService.EnemigosActivos do
		if not enemigo.Part or not enemigo.Part.Parent then
			EnemyService.EnemigosActivos[id] = nil
			continue
		end

		if enemigo.FinRalentizacion > 0 and os.clock() >= enemigo.FinRalentizacion then
			enemigo.FinRalentizacion = 0
			enemigo.Velocidad = enemigo.VelocidadBase
		end

		local objetivo = obtenerPosicionObjetivo(enemigo.Part.Position)
		if objetivo then
			local posActual = enemigo.Part.Position
			local direccion = Vector3.new(objetivo.X - posActual.X, 0, objetivo.Z - posActual.Z)
			local distancia = direccion.Magnitude

			if distancia > 1.5 then
				local direccionNorm = direccion.Unit
				local nuevaPos = posActual + (direccionNorm * enemigo.Velocidad * dt)
				enemigo.Part.CFrame = CFrame.new(nuevaPos, Vector3.new(objetivo.X, nuevaPos.Y, objetivo.Z))
			else
				EnemyService.AplicarDanioAJugador(enemigo)
			end
		end
	end
end

-- Spawnea un enemigo de tipo específico en una posición dada
function EnemyService.CrearEnemigo(tipoId: string, posicion: Vector3, multiplicadorVida: number?): EnemigoInstancia?
	-- Impedir generación si el servicio no está explícitamente activo
	if not EnemyService.Activo then
		return nil
	end

	local config = EnemigosConfig[tipoId]
	if not config then return nil end

	EnemyService.ContadorIds += 1
	local enemigoId = string.format("Mob_%d", EnemyService.ContadorIds)
	local mult = multiplicadorVida or 1.0

	-- Crear representación visual ligera (Part única con material sombrío)
	local part = Instance.new("Part")
	part.Name = enemigoId
	part.Size = config.Tamanio
	part.Color = config.Color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.CFrame = CFrame.new(posicion)

	local highlight = Instance.new("Highlight")
	highlight.FillColor = config.Color
	highlight.OutlineColor = Color3.fromRGB(0, 0, 0)
	highlight.FillTransparency = 0.3
	highlight.OutlineTransparency = 0.1
	highlight.Adornee = part
	highlight.Parent = part

	if EnemyService.CarpetaContenedora then
		part.Parent = EnemyService.CarpetaContenedora
	else
		part.Parent = Workspace
	end

	local instancia: EnemigoInstancia = {
		Id = enemigoId,
		TipoId = tipoId,
		Modelo = nil :: any,
		Part = part,
		VidaActual = config.VidaBase * mult,
		VidaMax = config.VidaBase * mult,
		Velocidad = config.VelocidadBase,
		VelocidadBase = config.VelocidadBase,
		FinRalentizacion = 0,
		Danio = config.DanioBase,
		XpOtorga = config.XpOtorga,
	}

	EnemyService.EnemigosActivos[enemigoId] = instancia
	return instancia
end

-- Aplica ralentización temporal a un enemigo (ej. Nova de Escarcha)
function EnemyService.AplicarRalentizacion(enemigoId: string, factorVelocidad: number, duracionSegundos: number)
	if not EnemyService.Activo then return end
	local enemigo = EnemyService.EnemigosActivos[enemigoId]
	if not enemigo then return end

	local factor = math.clamp(factorVelocidad, 0.1, 1.0)
	if enemigo.EsJefe then
		local reduccion = (1 - factor) * JefeConfig.ResistenciaRalentizacion
		factor = 1 - reduccion
	end

	enemigo.Velocidad = enemigo.VelocidadBase * factor
	enemigo.FinRalentizacion = math.max(enemigo.FinRalentizacion, os.clock() + duracionSegundos)
end

-- Aplica daño a un enemigo desde un ataque del jugador y retorna (danioEfectivo, fueEliminado)
function EnemyService.DanioEnemigo(enemigoId: string, cantidad: number): (number, boolean)
	if not EnemyService.Activo then return 0, false end

	local enemigo = EnemyService.EnemigosActivos[enemigoId]
	if not enemigo or enemigo.VidaActual <= 0 then return 0, false end

	local danioEfectivo = math.min(math.max(cantidad, 0), enemigo.VidaActual)
	enemigo.VidaActual -= danioEfectivo

	if enemigo.Part then
		local origColor = enemigo.Part.Color
		enemigo.Part.Color = Color3.fromRGB(255, 255, 255)
		task.delay(0.08, function()
			if enemigo.Part and enemigo.Part.Parent then
				enemigo.Part.Color = origColor
			end
		end)
	end

	if enemigo.EsJefe and danioEfectivo > 0 and EnemyService.CallbackDanioJefe then
		EnemyService.CallbackDanioJefe(math.max(0, enemigo.VidaActual), enemigo.VidaMax)
	end

	if enemigo.VidaActual <= 0 then
		EnemyService.EliminarEnemigo(enemigoId, true)
		return danioEfectivo, true
	end

	return danioEfectivo, false
end

-- Daño por contacto con el jugador
function EnemyService.AplicarDanioAJugador(enemigo: EnemigoInstancia)
	if not EnemyService.Activo then return end

	for _, player in Players:GetPlayers() do
		if EnemyService.ReconnectionService and typeof(EnemyService.ReconnectionService.EstaJugadorProtegido) == "function" then
			if EnemyService.ReconnectionService.EstaJugadorProtegido(player) then
				continue
			end
		end
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if humanoid and root and humanoid.Health > 0 then
				local dist = (root.Position - enemigo.Part.Position).Magnitude
				if dist <= 3 then
					humanoid:TakeDamage(enemigo.Danio * 0.05)
				end
			end
		end
	end
end

-- Destruye y desregistra a una entidad individual
function EnemyService.EliminarEnemigo(enemigoId: string, generoDrop: boolean)
	local enemigo = EnemyService.EnemigosActivos[enemigoId]
	if not enemigo then return end

	EnemyService.EnemigosActivos[enemigoId] = nil

	local posDrop = if enemigo.Part and enemigo.Part.Parent then enemigo.Part.Position else Vector3.zero
	if enemigo.Part then
		enemigo.Part:Destroy()
	end

	if generoDrop then
		if enemigo.EsJefe and EnemyService.CallbackJefeEliminado then
			EnemyService.CallbackJefeEliminado()
		elseif EnemyService.CallbackEnemigoEliminado then
			EnemyService.CallbackEnemigoEliminado(enemigo.TipoId, posDrop, enemigo.XpOtorga)
		end
	end
end

-- Limpia y destruye TODOS los enemigos activos inmediatamente
function EnemyService.LimpiarTodos()
	for id, enemigo in EnemyService.EnemigosActivos do
		if enemigo.Part then
			pcall(function() enemigo.Part:Destroy() end)
		end
	end
	table.clear(EnemyService.EnemigosActivos)

	if EnemyService.CarpetaContenedora then
		EnemyService.CarpetaContenedora:ClearAllChildren()
	end

	print("[UMBRA Server] Todos los enemigos activos han sido eliminados de Workspace.")
end

-- Detiene por completo el servicio de enemigos
function EnemyService.Detener()
	EnemyService.Activo = false
	if EnemyService.BucleConexion then
		EnemyService.BucleConexion:Disconnect()
		EnemyService.BucleConexion = nil
	end
	EnemyService.LimpiarTodos()
	print("[UMBRA Server] EnemyService detenido por completo.")
end

function EnemyService.ObtenerEnemigosEnRadio(centro: Vector3, radio: number): { EnemigoInstancia }
	local encontrados = {}
	if not EnemyService.Activo then return encontrados end

	for _, enemigo in EnemyService.EnemigosActivos do
		if enemigo.Part and enemigo.Part.Parent then
			local dist = (enemigo.Part.Position - centro).Magnitude
			if dist <= radio then
				table.insert(encontrados, enemigo)
			end
		end
	end
	return encontrados
end

return EnemyService
