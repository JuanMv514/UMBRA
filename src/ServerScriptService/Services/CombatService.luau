--!strict
-- CombatService.luau
-- Manejador de combate automático, enfriamiento de habilidades y daño a hordas en UMBRA.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local ConfigFolder = ReplicatedStorage:WaitForChild("Config")
local HabilidadesConfig = require(ConfigFolder:WaitForChild("HabilidadesConfig") :: ModuleScript)

local EnemyService = nil :: any -- Inyectado al iniciar

export type HabilidadActiva = {
	Id: string,
	Nivel: number,
	UltimoUso: number,
}

export type PerfilCombate = {
	Jugador: Player,
	Habilidades: { [string]: HabilidadActiva },
	Orbitales: { [string]: { Partes: { BasePart }, Angulo: number } },
}

local CombatService = {
	Activo = false,
	Perfiles = {} :: { [Player]: PerfilCombate },
	BucleConexion = nil :: RBXScriptConnection?,
	CarpetaEfectos = nil :: Folder?,
}

-- Inicializa el servicio de combate
function CombatService.Iniciar(enemyServiceRef: any)
	EnemyService = enemyServiceRef
	CombatService.Activo = true

	local carpeta = Workspace:FindFirstChild("EfectosCombate")
	if not carpeta then
		carpeta = Instance.new("Folder")
		carpeta.Name = "EfectosCombate"
		carpeta.Parent = Workspace
	end
	CombatService.CarpetaEfectos = carpeta :: Folder

	-- Bucle principal de ejecución de habilidades
	CombatService.BucleConexion = RunService.Heartbeat:Connect(function(dt: number)
		if not CombatService.Activo then return end
		CombatService.ActualizarHabilidades(dt)
	end)

	print("[UMBRA Server] CombatService iniciado (Ataques automáticos activos).")
end

-- Registra a un superviviente con sus habilidades iniciales
function CombatService.RegistrarJugador(player: Player)
	local perfil: PerfilCombate = {
		Jugador = player,
		Habilidades = {},
		Orbitales = {},
	}

	CombatService.Perfiles[player] = perfil

	-- Habilidad inicial gratuita: Aura Umbría y Chispa Espiritual
	CombatService.AgregarHabilidad(player, "AuraOscura")
	CombatService.AgregarHabilidad(player, "ChispaEspiritual")

	print(string.format("[UMBRA Server] Perfil de combate registrado para: %s", player.Name))
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

-- Añade una nueva habilidad o ignora si ya existe
function CombatService.AgregarHabilidad(player: Player, habilidadId: string)
	local perfil = CombatService.Perfiles[player]
	if not perfil then return end
	if not HabilidadesConfig[habilidadId] then return end

	if not perfil.Habilidades[habilidadId] then
		perfil.Habilidades[habilidadId] = {
			Id = habilidadId,
			Nivel = 1,
			UltimoUso = 0,
		}
	end
end

-- Sube el nivel de una habilidad existente
function CombatService.MejorarHabilidad(player: Player, habilidadId: string): boolean
	local perfil = CombatService.Perfiles[player]
	if not perfil then return false end

	local habilidad = perfil.Habilidades[habilidadId]
	local config = HabilidadesConfig[habilidadId]
	if not habilidad or not config then return false end

	if habilidad.Nivel < config.MaxNivel then
		habilidad.Nivel += 1
		return true
	end
	return false
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

		for _, habilidad in perfil.Habilidades do
			local config = HabilidadesConfig[habilidad.Id]
			if not config then continue end

			-- Cooldown escalado con nivel
			local cd = math.max(config.CooldownBase * (1 - (habilidad.Nivel - 1) * 0.08), 0.15)
			if tiempoActual - habilidad.UltimoUso >= cd then
				habilidad.UltimoUso = tiempoActual
				CombatService.EjecutarHabilidad(player, root, habilidad, config)
			end
		end

		-- Actualizar rotación de habilidades orbitales activas
		for habilidadId, orbital in perfil.Orbitales do
			orbital.Angulo = (orbital.Angulo + dt * 3.5) % (math.pi * 2)
			local config = HabilidadesConfig[habilidadId]
			local radio = config and config.RadioBase or 9
			local numPartes = #orbital.Partes

			for i, part in orbital.Partes do
				if part and part.Parent then
					local offsetAngulo = orbital.Angulo + (i * (math.pi * 2 / math.max(numPartes, 1)))
					local x = math.cos(offsetAngulo) * radio
					local z = math.sin(offsetAngulo) * radio
					part.CFrame = CFrame.new(root.Position + Vector3.new(x, 0.5, z))
				end
			end
		end
	end
end

-- Ejecutor específico según tipo de habilidad
function CombatService.EjecutarHabilidad(player: Player, root: BasePart, habilidad: HabilidadActiva, config: any)
	local nivel = habilidad.Nivel
	local danio = config.DanioBase * (1 + (nivel - 1) * 0.3)

	if config.Tipo == "Aura" then
		CombatService.EjecutarAura(root.Position, danio, config.RadioBase * (1 + (nivel - 1) * 0.15))
	elseif config.Tipo == "Proyectil" then
		CombatService.EjecutarProyectil(root.Position, danio, config.RadioBase, config.VelocidadBase or 60)
	elseif config.Tipo == "Orbital" then
		CombatService.AsegurarOrbitales(player, root, habilidad.Id, nivel)
	end
end

-- HABILIDAD: AURA OSCURA (Pulsación en área circular)
function CombatService.EjecutarAura(origen: Vector3, danio: number, radio: number)
	if not EnemyService then return end

	local enemigos = EnemyService.ObtenerEnemigosEnRadio(origen, radio)
	for _, enemigo in enemigos do
		EnemyService.DanioEnemigo(enemigo.Id, danio)
	end

	-- Efecto visual: Anillo expansivo de sombra
	if CombatService.CarpetaEfectos then
		local ring = Instance.new("Part")
		ring.Name = "AuraPulse"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.4, 2, 2)
		ring.Color = Color3.fromRGB(130, 20, 220) -- Púrpura umbrío
		ring.Material = Enum.Material.Neon
		ring.Transparency = 0.3
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CFrame = CFrame.new(origen) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = CombatService.CarpetaEfectos

		local tween = TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.2, radio * 2, radio * 2),
			Transparency = 1,
		})
		tween:Play()
		Debris:AddItem(ring, 0.4)
	end
end

-- HABILIDAD: CHISPA ESPIRITUAL (Proyectil automático al enemigo más cercano)
function CombatService.EjecutarProyectil(origen: Vector3, danio: number, rango: number, velocidad: number)
	if not EnemyService then return end

	local enemigos = EnemyService.ObtenerEnemigosEnRadio(origen, rango)
	if #enemigos == 0 then return end

	-- Buscar el más cercano
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

	-- Crear proyectil
	local proj = Instance.new("Part")
	proj.Name = "ChispaEspiritual"
	proj.Shape = Enum.PartType.Ball
	proj.Size = Vector3.new(1.2, 1.2, 1.2)
	proj.Color = Color3.fromRGB(80, 240, 255) -- Fuego fatuo celeste/cian
	proj.Material = Enum.Material.Neon
	proj.Anchored = true
	proj.CanCollide = false
	proj.CanQuery = false
	proj.CanTouch = false
	proj.CFrame = CFrame.new(origen + Vector3.new(0, 1, 0))
	proj.Parent = CombatService.CarpetaEfectos

	-- Hilo de traslación rápida hacia el objetivo
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

			local dir = (posDestino - proj.Position)
			local dist = dir.Magnitude

			if dist < 2.5 then
				-- Impacto
				if targetInst then
					EnemyService.DanioEnemigo(targetId, danio)
				end
				break
			else
				proj.CFrame = CFrame.new(proj.Position + (dir.Unit * velocidad * dt), posDestino)
			end
		end

		-- Pequeño destello de impacto
		if proj.Parent then
			proj.Size = Vector3.new(2.5, 2.5, 2.5)
			proj.Transparency = 0.5
			task.wait(0.05)
			proj:Destroy()
		end
	end)
end

-- HABILIDAD: FRAGMENTO GIRATORIO / ORBITALES
function CombatService.AsegurarOrbitales(player: Player, root: BasePart, habilidadId: string, nivel: number)
	local perfil = CombatService.Perfiles[player]
	if not perfil then return end

	local orbital = perfil.Orbitales[habilidadId]
	local cantidadRequerida = math.min(1 + nivel, 5)

	if not orbital then
		orbital = {
			Partes = {},
			Angulo = 0,
		}
		perfil.Orbitales[habilidadId] = orbital
	end

	-- Crear partes faltantes
	while #orbital.Partes < cantidadRequerida do
		local blade = Instance.new("Part")
		blade.Name = "CuchillaOrbital"
		blade.Size = Vector3.new(1.8, 0.4, 0.8)
		blade.Color = Color3.fromRGB(240, 50, 120)
		blade.Material = Enum.Material.Neon
		blade.Anchored = true
		blade.CanCollide = false
		blade.CanQuery = false
		blade.CanTouch = false
		blade.Parent = CombatService.CarpetaEfectos
		table.insert(orbital.Partes, blade)
	end
end

return CombatService
