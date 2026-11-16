--!strict
-- CombatService.luau
-- Manejador de combate automático, las 8 magias Alpha, enfriamientos y telemetría de daño en UMBRA.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local ConfigFolder = ReplicatedStorage:WaitForChild("Config")
local ModulesFolder = ReplicatedStorage:WaitForChild("Modules")
local HabilidadesConfig = require(ConfigFolder:WaitForChild("HabilidadesConfig") :: ModuleScript)
local AtributosConfig = require(ConfigFolder:WaitForChild("AtributosConfig") :: ModuleScript)
local TiposAlpha = require(ModulesFolder:WaitForChild("TiposAlpha") :: ModuleScript)

local EnemyService = nil :: any -- Inyectado al iniciar

export type HabilidadActiva = {
	Id: string,
	Nivel: number,
	UltimoUso: number,
}

export type OrbitalGrupo = {
	Partes: { BasePart },
	Angulo: number,
	UltimosGolpes: { [string]: number },
}

export type PerfilCombate = {
	Jugador: Player,
	Habilidades: { [string]: HabilidadActiva },
	OrdenHabilidades: { string },
	Orbitales: { [string]: OrbitalGrupo },
	MultiplicadorDanio: number,
	FactorCooldown: number,
	DanioTotalCausado: number,
	DanioPorMagia: { [string]: number },
	EnemigosDerrotados: number,
}

local CombatService = {
	Activo = false,
	Perfiles = {} :: { [Player]: PerfilCombate },
	BucleConexion = nil :: RBXScriptConnection?,
	CarpetaEfectos = nil :: Folder?,
	RemoteSincronizarMagias = nil :: RemoteEvent?,
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

local function registrarImpactoMagia(player: Player, habilidadId: string, enemigoId: string, danio: number)
	if not EnemyService then return end
	local danioAplicado, eliminado = EnemyService.DanioEnemigo(enemigoId, danio)
	if danioAplicado <= 0 then return end

	local perfil = CombatService.Perfiles[player]
	if perfil then
		perfil.DanioTotalCausado += danioAplicado
		perfil.DanioPorMagia[habilidadId] = (perfil.DanioPorMagia[habilidadId] or 0) + danioAplicado
		if eliminado then
			perfil.EnemigosDerrotados += 1
		end
	end
end

local function crearPulsoAnillo(origen: Vector3, radioFinal: number, color: Color3, duracion: number)
	if not CombatService.CarpetaEfectos then return end
	local ring = Instance.new("Part")
	ring.Name = "PulsoMagia"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.35, 2, 2)
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.3
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CFrame = CFrame.new(origen) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = CombatService.CarpetaEfectos

	TweenService:Create(ring, TweenInfo.new(duracion, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, radioFinal * 2, radioFinal * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, duracion + 0.05)
end

local function crearHazElectrico(p1: Vector3, p2: Vector3, color: Color3)
	if not CombatService.CarpetaEfectos then return end
	local dist = (p2 - p1).Magnitude
	if dist < 0.1 then return end

	local beam = Instance.new("Part")
	beam.Name = "RayoCadena"
	beam.Size = Vector3.new(0.35, 0.35, dist)
	beam.Color = color
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.15
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CFrame = CFrame.lookAt((p1 + p2) * 0.5, p2)
	beam.Parent = CombatService.CarpetaEfectos

	TweenService:Create(beam, TweenInfo.new(0.16), { Transparency = 1 }):Play()
	Debris:AddItem(beam, 0.18)
end

-- Inicializa el servicio de combate
function CombatService.Iniciar(enemyServiceRef: any)
	EnemyService = enemyServiceRef
	CombatService.Activo = true

	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end
	CombatService.RemoteSincronizarMagias = asegurarRemote(remotesFolder, "SincronizarMagiasJugador")

	local carpeta = Workspace:FindFirstChild("EfectosCombate")
	if not carpeta then
		carpeta = Instance.new("Folder")
		carpeta.Name = "EfectosCombate"
		carpeta.Parent = Workspace
	end
	CombatService.CarpetaEfectos = carpeta :: Folder

	-- Bucle principal de ejecución de habilidades
	if CombatService.BucleConexion then
		CombatService.BucleConexion:Disconnect()
	end
	CombatService.BucleConexion = RunService.Heartbeat:Connect(function(dt: number)
		if not CombatService.Activo then return end
		CombatService.ActualizarHabilidades(dt)
	end)

	print("[UMBRA Server] CombatService iniciado (8 magias Alpha y telemetría activas).")
end

function CombatService.SincronizarMagias(player: Player)
	if not CombatService.RemoteSincronizarMagias then return end
	local perfil = CombatService.Perfiles[player]
	if not perfil then return end

	local lista: { TiposAlpha.RanuraMagiaHUD } = {}
	for i, habId in perfil.OrdenHabilidades do
		local hab = perfil.Habilidades[habId]
		local def = HabilidadesConfig.Catalogo[habId]
		if hab and def then
			table.insert(lista, {
				Orden = i,
				Id = habId,
				Nombre = def.Nombre,
				Nivel = hab.Nivel,
				MaxNivel = def.MaxNivel,
				Color = def.ColorVisual,
			})
		end
	end

	local payload: TiposAlpha.EstadoMagiasJugador = {
		MaxRanuras = HabilidadesConfig.MaxRanurasActivas,
		RanurasOcupadas = #lista,
		Magias = lista,
	}
	CombatService.RemoteSincronizarMagias:FireClient(player, payload)
end

-- Registra a un superviviente con únicamente Esfera Ígnea (Nivel 1)
function CombatService.RegistrarJugador(player: Player)
	local perfil: PerfilCombate = {
		Jugador = player,
		Habilidades = {},
		OrdenHabilidades = {},
		Orbitales = {},
		MultiplicadorDanio = 1.0,
		FactorCooldown = 1.0,
		DanioTotalCausado = 0,
		DanioPorMagia = {},
		EnemigosDerrotados = 0,
	}

	CombatService.Perfiles[player] = perfil
	CombatService.AgregarHabilidad(player, "EsferaIgnea")

	print(string.format("[UMBRA Server] Perfil de combate registrado para %s (Magia inicial: Esfera Ígnea Nv.1).", player.Name))
end

-- Desregistra y limpia efectos del jugador
function CombatService.DesregistrarJugador(player: Player)
	local perfil = CombatService.Perfiles[player]
	if perfil then
		for _, orbital in perfil.Orbitales do
			for _, part in orbital.Partes do
				if part and part.Parent then
					part:Destroy()
				end
			end
		end
		CombatService.Perfiles[player] = nil
	end
end

-- Añade una nueva habilidad respetando el límite de 6 ranuras activas
function CombatService.AgregarHabilidad(player: Player, habilidadId: string): boolean
	local perfil = CombatService.Perfiles[player]
	if not perfil then return false end

	local def = HabilidadesConfig.Catalogo[habilidadId]
	if not def then return false end
	if perfil.Habilidades[habilidadId] then return false end
	if #perfil.OrdenHabilidades >= HabilidadesConfig.MaxRanurasActivas then
		return false
	end

	perfil.Habilidades[habilidadId] = {
		Id = habilidadId,
		Nivel = 1,
		UltimoUso = 0,
	}
	table.insert(perfil.OrdenHabilidades, habilidadId)
	CombatService.SincronizarMagias(player)
	return true
end

-- Sube el nivel de una habilidad existente hasta MaxNivel (7)
function CombatService.MejorarHabilidad(player: Player, habilidadId: string): boolean
	local perfil = CombatService.Perfiles[player]
	if not perfil then return false end

	local habilidad = perfil.Habilidades[habilidadId]
	local config = HabilidadesConfig.Catalogo[habilidadId]
	if not habilidad or not config then return false end

	local limite = math.min(config.MaxNivel, HabilidadesConfig.NivelMaximoMagia)
	if habilidad.Nivel < limite then
		habilidad.Nivel += 1
		CombatService.SincronizarMagias(player)
		return true
	end
	return false
end

function CombatService.ObtenerHabilidadesJugador(player: Player): { [string]: HabilidadActiva }?
	local perfil = CombatService.Perfiles[player]
	return if perfil then perfil.Habilidades else nil
end

function CombatService.ContarRanurasHabilidades(player: Player): number
	local perfil = CombatService.Perfiles[player]
	return if perfil then #perfil.OrdenHabilidades else 0
end

function CombatService.ObtenerMultiplicadores(player: Player): (number, number)
	local perfil = CombatService.Perfiles[player]
	if not perfil then
		return 1.0, 1.0
	end
	return perfil.MultiplicadorDanio, perfil.FactorCooldown
end

function CombatService.EstablecerMultiplicadores(player: Player, multDanio: number, factorCooldown: number)
	local perfil = CombatService.Perfiles[player]
	if not perfil then return end
	perfil.MultiplicadorDanio = multDanio
	perfil.FactorCooldown = math.max(factorCooldown, 0.25)
end

-- Exporta snapshot completo del combate y telemetría para reconexión (Sección 13)
function CombatService.ExportarSnapshotJugador(player: Player): any?
	local perfil = CombatService.Perfiles[player]
	if not perfil then return nil end

	local habsCopia: { [string]: { Id: string, Nivel: number } } = {}
	for habId, hab in perfil.Habilidades do
		habsCopia[habId] = { Id = hab.Id, Nivel = hab.Nivel }
	end

	local ordenCopia: { string } = {}
	for _, habId in perfil.OrdenHabilidades do
		table.insert(ordenCopia, habId)
	end

	local danioCopia: { [string]: number } = {}
	for habId, d in perfil.DanioPorMagia do
		danioCopia[habId] = d
	end

	return {
		Habilidades = habsCopia,
		OrdenHabilidades = ordenCopia,
		MultiplicadorDanio = perfil.MultiplicadorDanio,
		FactorCooldown = perfil.FactorCooldown,
		DanioTotalCausado = perfil.DanioTotalCausado,
		DanioPorMagia = danioCopia,
		EnemigosDerrotados = perfil.EnemigosDerrotados,
	}
end

-- Restaura snapshot completo de combate tras reconexión (Sección 13)
function CombatService.RestaurarSnapshotJugador(player: Player, snapshot: any)
	if not snapshot or typeof(snapshot) ~= "table" then return end
	local perfil = CombatService.Perfiles[player]
	if not perfil then
		CombatService.RegistrarJugador(player)
		perfil = CombatService.Perfiles[player]
	end
	if not perfil then return end

	-- Limpiar orbitales previos si existieran
	for _, orbital in perfil.Orbitales do
		for _, part in orbital.Partes do
			if part and part.Parent then
				part:Destroy()
			end
		end
	end
	table.clear(perfil.Orbitales)
	table.clear(perfil.Habilidades)
	table.clear(perfil.OrdenHabilidades)

	if typeof(snapshot.Habilidades) == "table" then
		for habId, habData in snapshot.Habilidades do
			perfil.Habilidades[habId] = {
				Id = habData.Id or habId,
				Nivel = habData.Nivel or 1,
				UltimoUso = 0,
			}
		end
	end
	if typeof(snapshot.OrdenHabilidades) == "table" then
		for _, habId in snapshot.OrdenHabilidades do
			if perfil.Habilidades[habId] then
				table.insert(perfil.OrdenHabilidades, habId)
			end
		end
	end

	perfil.MultiplicadorDanio = snapshot.MultiplicadorDanio or 1.0
	perfil.FactorCooldown = snapshot.FactorCooldown or 1.0
	perfil.DanioTotalCausado = snapshot.DanioTotalCausado or 0
	perfil.DanioPorMagia = snapshot.DanioPorMagia or {}
	perfil.EnemigosDerrotados = snapshot.EnemigosDerrotados or 0

	CombatService.SincronizarMagias(player)
end

-- Retorna telemetría autoritativa de combate del jugador para resultados (Sección 14)
function CombatService.ObtenerEstadisticasCombate(player: Player): {
	DanioTotalCausado: number,
	EnemigosDerrotados: number,
	Magias: { TiposAlpha.EstadisticasMagiaResultado },
}
	local perfil = CombatService.Perfiles[player]
	if not perfil then
		return {
			DanioTotalCausado = 0,
			EnemigosDerrotados = 0,
			Magias = {},
		}
	end

	local magiasStats: { TiposAlpha.EstadisticasMagiaResultado } = {}
	for _, habId in perfil.OrdenHabilidades do
		local hab = perfil.Habilidades[habId]
		local def = HabilidadesConfig.Catalogo[habId]
		if hab and def then
			table.insert(magiasStats, {
				Id = habId,
				Nombre = def.Nombre,
				NivelFinal = hab.Nivel,
				DanioCausado = math.round(perfil.DanioPorMagia[habId] or 0),
			})
		end
	end

	return {
		DanioTotalCausado = math.round(perfil.DanioTotalCausado),
		EnemigosDerrotados = perfil.EnemigosDerrotados,
		Magias = magiasStats,
	}
end

-- Bucle de actualización por fotograma
function CombatService.ActualizarHabilidades(dt: number)
	local tiempoActual = os.clock()

	for player, perfil in CombatService.Perfiles do
		local character = player.Character
		if not character then continue end

		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 then continue end

		-- Regeneración automática de vida muy baja (Sección 6, no mejorable por atributos)
		if humanoid.Health < humanoid.MaxHealth then
			humanoid.Health = math.min(
				humanoid.MaxHealth,
				humanoid.Health + (AtributosConfig.RegeneracionVidaPasivaPorSegundo * dt)
			)
		end

		for _, habilidad in perfil.Habilidades do
			local config = HabilidadesConfig.Catalogo[habilidad.Id]
			if not config then continue end

			local cd = math.max(config.CooldownBase * (1 - (habilidad.Nivel - 1) * 0.07) * perfil.FactorCooldown, 0.15)
			if tiempoActual - habilidad.UltimoUso >= cd then
				habilidad.UltimoUso = tiempoActual
				CombatService.EjecutarHabilidad(player, root, habilidad, config, perfil.MultiplicadorDanio)
			end
		end

		-- Actualizar rotación y daño por contacto de habilidades orbitales activas
		for habilidadId, orbital in perfil.Orbitales do
			orbital.Angulo = (orbital.Angulo + dt * 3.6) % (math.pi * 2)
			local config = HabilidadesConfig.Catalogo[habilidadId]
			local radio = if config then config.RadioBase else 9.5
			local numPartes = #orbital.Partes

			local hab = perfil.Habilidades[habilidadId]
			local danioOrbital = if config and hab
				then config.DanioBase * (1 + (hab.Nivel - 1) * 0.25) * perfil.MultiplicadorDanio
				else 10

			for i, part in orbital.Partes do
				if part and part.Parent then
					local offsetAngulo = orbital.Angulo + (i * (math.pi * 2 / math.max(numPartes, 1)))
					local x = math.cos(offsetAngulo) * radio
					local z = math.sin(offsetAngulo) * radio
					local posOrb = root.Position + Vector3.new(x, 0.5, z)
					part.CFrame = CFrame.new(posOrb)

					if EnemyService then
						local cercanos = EnemyService.ObtenerEnemigosEnRadio(posOrb, 2.8)
						for _, enemigo in cercanos do
							local ultimoGolpe = orbital.UltimosGolpes[enemigo.Id] or 0
							if tiempoActual - ultimoGolpe >= 0.4 then
								orbital.UltimosGolpes[enemigo.Id] = tiempoActual
								registrarImpactoMagia(player, habilidadId, enemigo.Id, danioOrbital)
							end
						end
					end
				end
			end
		end
	end
end

-- Ejecutor específico según tipo de magia
function CombatService.EjecutarHabilidad(
	player: Player,
	root: BasePart,
	habilidad: HabilidadActiva,
	config: HabilidadesConfig.HabilidadDef,
	multiplicadorDanio: number
)
	local nivel = habilidad.Nivel
	local danio = config.DanioBase * (1 + (nivel - 1) * 0.25) * multiplicadorDanio

	if config.Tipo == "ProyectilDirigido" then
		CombatService.EjecutarProyectilDirigido(player, habilidad.Id, root.Position, danio, config.RadioBase, config.VelocidadBase or 62, config.ColorVisual)
	elseif config.Tipo == "AreaPersonaje" then
		CombatService.EjecutarAreaPersonaje(player, habilidad.Id, root.Position, danio, config.RadioBase * (1 + (nivel - 1) * 0.12), config.ColorVisual)
	elseif config.Tipo == "RelampagoCadena" then
		CombatService.EjecutarRelampagoCadena(player, habilidad.Id, root.Position, danio, config.RadioBase, 2 + math.floor(nivel / 2), config.ColorVisual)
	elseif config.Tipo == "Orbital" then
		CombatService.AsegurarOrbitales(player, habilidad.Id, nivel, config.ColorVisual)
	elseif config.Tipo == "NovaRalentizadora" then
		CombatService.EjecutarNovaEscarcha(player, habilidad.Id, root.Position, danio, config.RadioBase * (1 + (nivel - 1) * 0.1), config.ColorVisual)
	elseif config.Tipo == "ProyectilPerforante" then
		CombatService.EjecutarProyectilPerforante(player, habilidad.Id, root.Position, danio, config.RadioBase, config.VelocidadBase or 85, config.ColorVisual)
	elseif config.Tipo == "ImpactoZona" then
		CombatService.EjecutarImpactoZona(player, habilidad.Id, root.Position, danio, config.RadioBase, 10 + nivel, config.ColorVisual)
	elseif config.Tipo == "ZonaPersistente" then
		CombatService.EjecutarZonaPersistente(player, habilidad.Id, root.Position, danio, config.RadioBase, 9 + nivel * 0.7, 3.0 + nivel * 0.35, config.ColorVisual)
	end
end

-- 1. Proyectil Dirigido (Esfera Ígnea)
function CombatService.EjecutarProyectilDirigido(player: Player, habId: string, origen: Vector3, danio: number, rango: number, velocidad: number, color: Color3)
	if not EnemyService then return end
	local enemigos = EnemyService.ObtenerEnemigosEnRadio(origen, rango)
	if #enemigos == 0 then return end

	local objetivo = nil
	local menorDist = math.huge
	for _, enemigo in enemigos do
		if enemigo.Part and enemigo.Part.Parent then
			local d = (enemigo.Part.Position - origen).Magnitude
			if d < menorDist then
				menorDist = d
				objetivo = enemigo
			end
		end
	end
	if not objetivo or not objetivo.Part then return end

	local proj = Instance.new("Part")
	proj.Name = habId
	proj.Shape = Enum.PartType.Ball
	proj.Size = Vector3.new(1.3, 1.3, 1.3)
	proj.Color = color
	proj.Material = Enum.Material.Neon
	proj.Anchored = true
	proj.CanCollide = false
	proj.CanQuery = false
	proj.CanTouch = false
	proj.CFrame = CFrame.new(origen + Vector3.new(0, 1, 0))
	proj.Parent = CombatService.CarpetaEfectos

	task.spawn(function()
		local duracion = 0
		local maxTiempo = rango / velocidad
		local targetId = objetivo.Id

		while duracion < maxTiempo and proj.Parent do
			local dt = task.wait(0.03)
			duracion += dt

			local targetInst = EnemyService.EnemigosActivos[targetId]
			local posDestino = if targetInst and targetInst.Part and targetInst.Part.Parent
				then targetInst.Part.Position
				else (proj.CFrame * CFrame.new(0, 0, -2)).Position

			local dir = posDestino - proj.Position
			if dir.Magnitude < 2.5 then
				if targetInst then
					registrarImpactoMagia(player, habId, targetId, danio)
				end
				break
			else
				proj.CFrame = CFrame.new(proj.Position + (dir.Unit * velocidad * dt), posDestino)
			end
		end

		if proj.Parent then
			proj.Size = Vector3.new(2.4, 2.4, 2.4)
			proj.Transparency = 0.5
			task.wait(0.05)
			proj:Destroy()
		end
	end)
end

-- 2. Área alrededor del Personaje (Anillo de Incineración)
function CombatService.EjecutarAreaPersonaje(player: Player, habId: string, origen: Vector3, danio: number, radio: number, color: Color3)
	if not EnemyService then return end
	local enemigos = EnemyService.ObtenerEnemigosEnRadio(origen, radio)
	for _, enemigo in enemigos do
		registrarImpactoMagia(player, habId, enemigo.Id, danio)
	end
	crearPulsoAnillo(origen, radio, color, 0.32)
end

-- 3. Relámpago en Cadena (Descarga Relámpago)
function CombatService.EjecutarRelampagoCadena(player: Player, habId: string, origen: Vector3, danio: number, rango: number, maxSaltos: number, color: Color3)
	if not EnemyService then return end
	local enemigos = EnemyService.ObtenerEnemigosEnRadio(origen, rango)
	if #enemigos == 0 then return end

	local primero = nil
	local menorDist = math.huge
	for _, enemigo in enemigos do
		if enemigo.Part and enemigo.Part.Parent then
			local d = (enemigo.Part.Position - origen).Magnitude
			if d < menorDist then
				menorDist = d
				primero = enemigo
			end
		end
	end
	if not primero or not primero.Part then return end

	local visitados: { [string]: boolean } = {}
	local puntoAnterior = origen + Vector3.new(0, 1.5, 0)
	local actual = primero

	for salto = 1, maxSaltos do
		if not actual or not actual.Part or not actual.Part.Parent then break end
		visitados[actual.Id] = true
		local posActual = actual.Part.Position
		crearHazElectrico(puntoAnterior, posActual, color)
		registrarImpactoMagia(player, habId, actual.Id, danio * (0.85 ^ (salto - 1)))

		puntoAnterior = posActual
		local siguientes = EnemyService.ObtenerEnemigosEnRadio(posActual, 20)
		local proximo = nil
		local minDist = math.huge
		for _, cand in siguientes do
			if not visitados[cand.Id] and cand.Part and cand.Part.Parent then
				local d = (cand.Part.Position - posActual).Magnitude
				if d < minDist then
					minDist = d
					proximo = cand
				end
			end
		end
		actual = proximo
	end
end

-- 4. Orbitales (Orbes Umbríos)
function CombatService.AsegurarOrbitales(player: Player, habilidadId: string, nivel: number, color: Color3)
	local perfil = CombatService.Perfiles[player]
	if not perfil then return end

	local orbital = perfil.Orbitales[habilidadId]
	local cantidadRequerida = math.min(2 + math.floor(nivel / 2), 6)

	if not orbital then
		orbital = {
			Partes = {},
			Angulo = 0,
			UltimosGolpes = {},
		}
		perfil.Orbitales[habilidadId] = orbital
	end

	while #orbital.Partes < cantidadRequerida do
		local orb = Instance.new("Part")
		orb.Name = "OrbeUmbrio"
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(1.5, 1.5, 1.5)
		orb.Color = color
		orb.Material = Enum.Material.Neon
		orb.Anchored = true
		orb.CanCollide = false
		orb.CanQuery = false
		orb.CanTouch = false
		orb.Parent = CombatService.CarpetaEfectos
		table.insert(orbital.Partes, orb)
	end
end

-- 5. Nova Ralentizadora (Nova de Escarcha)
function CombatService.EjecutarNovaEscarcha(player: Player, habId: string, origen: Vector3, danio: number, radio: number, color: Color3)
	if not EnemyService then return end
	local enemigos = EnemyService.ObtenerEnemigosEnRadio(origen, radio)
	for _, enemigo in enemigos do
		registrarImpactoMagia(player, habId, enemigo.Id, danio)
		EnemyService.AplicarRalentizacion(enemigo.Id, 0.65, 2.5) -- 35% ralentización por 2.5s
	end
	crearPulsoAnillo(origen, radio, color, 0.4)
end

-- 6. Proyectil Perforante (Lanza Abisal)
function CombatService.EjecutarProyectilPerforante(player: Player, habId: string, origen: Vector3, danio: number, rango: number, velocidad: number, color: Color3)
	if not EnemyService then return end
	local enemigos = EnemyService.ObtenerEnemigosEnRadio(origen, rango)
	if #enemigos == 0 then return end

	local objetivo = nil
	local menorDist = math.huge
	for _, enemigo in enemigos do
		if enemigo.Part and enemigo.Part.Parent then
			local d = (enemigo.Part.Position - origen).Magnitude
			if d < menorDist then
				menorDist = d
				objetivo = enemigo
			end
		end
	end
	if not objetivo or not objetivo.Part then return end

	local dirPlano = Vector3.new(objetivo.Part.Position.X - origen.X, 0, objetivo.Part.Position.Z - origen.Z)
	if dirPlano.Magnitude < 0.1 then return end
	local dirNorm = dirPlano.Unit

	local lanza = Instance.new("Part")
	lanza.Name = habId
	lanza.Size = Vector3.new(0.6, 0.6, 3.6)
	lanza.Color = color
	lanza.Material = Enum.Material.Neon
	lanza.Anchored = true
	lanza.CanCollide = false
	lanza.CanQuery = false
	lanza.CanTouch = false
	local inicio = Vector3.new(origen.X, 1.5, origen.Z)
	lanza.CFrame = CFrame.lookAt(inicio, inicio + dirNorm)
	lanza.Parent = CombatService.CarpetaEfectos

	task.spawn(function()
		local golpeados: { [string]: boolean } = {}
		local recorrida = 0
		while recorrida < rango and lanza.Parent do
			local dt = task.wait(0.03)
			local paso = velocidad * dt
			recorrida += paso
			lanza.CFrame = lanza.CFrame + (dirNorm * paso)

			local cercanos = EnemyService.ObtenerEnemigosEnRadio(lanza.Position, 3.0)
			for _, enemigo in cercanos do
				if not golpeados[enemigo.Id] then
					golpeados[enemigo.Id] = true
					registrarImpactoMagia(player, habId, enemigo.Id, danio)
				end
			end
		end
		if lanza.Parent then
			lanza:Destroy()
		end
	end)
end

-- 7. Impacto de Zona (Meteorito Astral)
function CombatService.EjecutarImpactoZona(player: Player, habId: string, origen: Vector3, danio: number, rango: number, radioImpacto: number, color: Color3)
	if not EnemyService then return end
	local enemigos = EnemyService.ObtenerEnemigosEnRadio(origen, rango)
	if #enemigos == 0 then return end

	local elegido = enemigos[math.random(1, #enemigos)]
	if not elegido or not elegido.Part then return end
	local posImpacto = Vector3.new(elegido.Part.Position.X, 1.0, elegido.Part.Position.Z)

	local meteoro = Instance.new("Part")
	meteoro.Name = habId
	meteoro.Shape = Enum.PartType.Ball
	meteoro.Size = Vector3.new(3.2, 3.2, 3.2)
	meteoro.Color = color
	meteoro.Material = Enum.Material.Neon
	meteoro.Anchored = true
	meteoro.CanCollide = false
	meteoro.CanQuery = false
	meteoro.CanTouch = false
	meteoro.Position = posImpacto + Vector3.new(0, 26, 0)
	meteoro.Parent = CombatService.CarpetaEfectos

	TweenService:Create(meteoro, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = posImpacto,
	}):Play()

	task.delay(0.33, function()
		if meteoro.Parent then
			meteoro:Destroy()
		end
		if not CombatService.Activo or not EnemyService then return end
		local afectados = EnemyService.ObtenerEnemigosEnRadio(posImpacto, radioImpacto)
		for _, enemigo in afectados do
			registrarImpactoMagia(player, habId, enemigo.Id, danio)
		end
		crearPulsoAnillo(posImpacto, radioImpacto, color, 0.35)
	end)
end

-- 8. Zona Persistente (Vórtice del Vacío)
function CombatService.EjecutarZonaPersistente(player: Player, habId: string, origen: Vector3, danioPulso: number, rango: number, radioZona: number, duracion: number, color: Color3)
	if not EnemyService then return end
	local enemigos = EnemyService.ObtenerEnemigosEnRadio(origen, rango)
	if #enemigos == 0 then return end

	local elegido = enemigos[math.random(1, #enemigos)]
	if not elegido or not elegido.Part then return end
	local posZona = Vector3.new(elegido.Part.Position.X, 0.5, elegido.Part.Position.Z)

	local zona = Instance.new("Part")
	zona.Name = habId
	zona.Shape = Enum.PartType.Cylinder
	zona.Size = Vector3.new(0.3, radioZona * 2, radioZona * 2)
	zona.Color = color
	zona.Material = Enum.Material.Neon
	zona.Transparency = 0.55
	zona.Anchored = true
	zona.CanCollide = false
	zona.CanQuery = false
	zona.CanTouch = false
	zona.CFrame = CFrame.new(posZona) * CFrame.Angles(0, 0, math.rad(90))
	zona.Parent = CombatService.CarpetaEfectos

	task.spawn(function()
		local transcurrido = 0
		while transcurrido < duracion and CombatService.Activo and zona.Parent do
			local afectados = EnemyService.ObtenerEnemigosEnRadio(posZona, radioZona)
			for _, enemigo in afectados do
				registrarImpactoMagia(player, habId, enemigo.Id, danioPulso)
			end
			task.wait(0.6)
			transcurrido += 0.6
		end
		if zona.Parent then
			zona:Destroy()
		end
	end)
end

-- Detiene por completo el sistema de combate y limpia efectos
function CombatService.Detener()
	CombatService.Activo = false

	if CombatService.BucleConexion then
		CombatService.BucleConexion:Disconnect()
		CombatService.BucleConexion = nil
	end

	for player, _ in CombatService.Perfiles do
		CombatService.DesregistrarJugador(player)
	end
	table.clear(CombatService.Perfiles)

	if CombatService.CarpetaEfectos then
		CombatService.CarpetaEfectos:ClearAllChildren()
	end

	print("[UMBRA Server] CombatService detenido por completo.")
end

return CombatService
