--!strict
-- ProgressionService.luau
-- Servicio autoritativo de experiencia, orbes individuales, niveles y selección de mejoras (Secciones 6 y 10).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ConfigFolder = ReplicatedStorage:WaitForChild("Config")
local ModulesFolder = ReplicatedStorage:WaitForChild("Modules")
local ExperienciaConfig = require(ConfigFolder:WaitForChild("ExperienciaConfig") :: ModuleScript)
local AtributosConfig = require(ConfigFolder:WaitForChild("AtributosConfig") :: ModuleScript)
local HabilidadesConfig = require(ConfigFolder:WaitForChild("HabilidadesConfig") :: ModuleScript)
local TiposAlpha = require(ModulesFolder:WaitForChild("TiposAlpha") :: ModuleScript)

local CombatService = nil :: any
local GameManager = nil :: any

type ProgresionInterna = {
	Jugador: Player,
	Nivel: number,
	XpActual: number,
	XpRequerida: number,
	SeleccionesPendientes: number,
	OpcionesActuales: { TiposAlpha.OpcionMejora }?,
	NivelesAtributos: { [string]: number },
	OrbesActivos: { [string]: TiposAlpha.OrbeSincronizado },
}

local ProgressionService = {
	Activo = false,
	Perfiles = {} :: { [Player]: ProgresionInterna },
	ContadorOrbes = 0,
	MaxRanurasMagia = 6,
	ConexionHeartbeat = nil :: RBXScriptConnection?,
	RemoteSincronizar = nil :: RemoteEvent?,
	RemoteOrbes = nil :: RemoteEvent?,
	RemoteSeleccionarMejora = nil :: RemoteEvent?,
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

local function elegirCategoriaOrbe(tipoEnemigo: string): TiposAlpha.CategoriaOrbeId
	local pesos = ExperienciaConfig.PesosOrbePorEnemigo[tipoEnemigo]
	if not pesos then
		return "Menor"
	end

	local totalPeso = pesos.Menor + pesos.Medio + pesos.Mayor
	if totalPeso <= 0 then
		return "Menor"
	end

	local tiro = math.random() * totalPeso
	if tiro <= pesos.Menor then
		return "Menor"
	elseif tiro <= (pesos.Menor + pesos.Medio) then
		return "Medio"
	else
		return "Mayor"
	end
end

local function esJugadorVivo(player: Player): (boolean, BasePart?)
	if not player or not player:IsDescendantOf(Players) then
		return false, nil
	end
	if GameManager and GameManager.JugadoresVivos and GameManager.JugadoresVivos[player] == false then
		return false, nil
	end
	local char = player.Character
	if not char then
		return false, nil
	end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		return false, nil
	end
	return true, root
end

function ProgressionService.Iniciar(combatServiceRef: any, gameManagerRef: any?)
	if ProgressionService.Activo then
		ProgressionService.Detener()
	end

	CombatService = combatServiceRef
	GameManager = gameManagerRef
	ProgressionService.Activo = true

	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end

	ProgressionService.RemoteSincronizar = asegurarRemote(remotesFolder, "SincronizarProgresion")
	ProgressionService.RemoteOrbes = asegurarRemote(remotesFolder, "EventosOrbesCliente")
	ProgressionService.RemoteSeleccionarMejora = asegurarRemote(remotesFolder, "SeleccionarMejoraNivel")

	if ProgressionService.RemoteSeleccionarMejora then
		ProgressionService.RemoteSeleccionarMejora.OnServerEvent:Connect(function(player: Player, idOpcion: any)
			ProgressionService.ProcesarSeleccionMejora(player, idOpcion)
		end)
	end

	ProgressionService.ConexionHeartbeat = RunService.Heartbeat:Connect(function()
		if not ProgressionService.Activo then return end
		ProgressionService.ActualizarOrbes()
	end)

	print("[UMBRA Server] ProgressionService iniciado (XP, Orbes individuales y Mejoras activos).")
end

function ProgressionService.RegistrarJugador(player: Player)
	if not player then return end

	local perfil: ProgresionInterna = {
		Jugador = player,
		Nivel = 1,
		XpActual = 0,
		XpRequerida = ExperienciaConfig.CalcularXpParaNivel(1),
		SeleccionesPendientes = 0,
		OpcionesActuales = nil,
		NivelesAtributos = {},
		OrbesActivos = {},
	}
	ProgressionService.Perfiles[player] = perfil
	ProgressionService.SincronizarJugador(player)
end

function ProgressionService.DesregistrarJugador(player: Player)
	local perfil = ProgressionService.Perfiles[player]
	if perfil then
		table.clear(perfil.OrbesActivos)
		ProgressionService.Perfiles[player] = nil
	end
	if ProgressionService.RemoteOrbes and player:IsDescendantOf(Players) then
		ProgressionService.RemoteOrbes:FireClient(player, "LimpiarTodos")
	end
end

function ProgressionService.SincronizarJugador(player: Player)
	if not ProgressionService.RemoteSincronizar then return end
	if not player or not player:IsDescendantOf(Players) then return end

	local perfil = ProgressionService.Perfiles[player]
	if not perfil then return end

	local payload: TiposAlpha.EstadoProgresionJugador = {
		Nivel = perfil.Nivel,
		XpActual = perfil.XpActual,
		XpRequerida = perfil.XpRequerida,
		SeleccionesPendientes = perfil.SeleccionesPendientes,
		OpcionesActuales = perfil.OpcionesActuales,
	}
	ProgressionService.RemoteSincronizar:FireClient(player, payload)
end

function ProgressionService.OnEnemigoEliminado(tipoId: string, posicion: Vector3, xpBase: number)
	if not ProgressionService.Activo then return end
	if GameManager and typeof(GameManager.ObtenerEstado) == "function" and GameManager.ObtenerEstado() ~= "Playing" then
		return
	end

	local xpDirecta = math.max(1, math.round(xpBase * ExperienciaConfig.RatioXpDirectaMuerte))

	for player, perfil in ProgressionService.Perfiles do
		local vivo, _ = esJugadorVivo(player)
		if not vivo then continue end

		-- 1. Acreditar 50% de XP directa individual sin importar quién causó el daño
		ProgressionService.AcreditarXp(player, xpDirecta)

		-- 2. Generar orbe individual (50% restante) exclusivo para este jugador
		local categoria = elegirCategoriaOrbe(tipoId)
		local catDef = ExperienciaConfig.CategoriasOrbe[categoria]
		if catDef then
			ProgressionService.ContadorOrbes += 1
			local orbeId = string.format("Orbe_%d_%d", player.UserId, ProgressionService.ContadorOrbes)
			local angulo = math.random() * math.pi * 2
			local distOffset = 1.0 + math.random()
			local posOrbe = Vector3.new(
				posicion.X + math.cos(angulo) * distOffset,
				math.max(1.2, posicion.Y),
				posicion.Z + math.sin(angulo) * distOffset
			)

			local valorOrbe = math.max(1, math.round(xpBase * ExperienciaConfig.RatioXpOrbe * catDef.MultiplicadorValor))
			local orbe: TiposAlpha.OrbeSincronizado = {
				Id = orbeId,
				Categoria = categoria,
				ValorXp = valorOrbe,
				Posicion = posOrbe,
				TiempoExpiracion = os.clock() + catDef.TiempoVidaSegundos,
			}

			perfil.OrbesActivos[orbeId] = orbe
			if ProgressionService.RemoteOrbes then
				ProgressionService.RemoteOrbes:FireClient(player, "Crear", orbe)
			end
		end
	end
end

function ProgressionService.ActualizarOrbes()
	local ahora = os.clock()

	for player, perfil in ProgressionService.Perfiles do
		local vivo, root = esJugadorVivo(player)

		for orbeId, orbe in perfil.OrbesActivos do
			if ahora >= orbe.TiempoExpiracion then
				perfil.OrbesActivos[orbeId] = nil
				if ProgressionService.RemoteOrbes and player:IsDescendantOf(Players) then
					ProgressionService.RemoteOrbes:FireClient(player, "Eliminar", orbeId)
				end
			elseif vivo and root then
				local dist = (root.Position - orbe.Posicion).Magnitude
				if dist <= ExperienciaConfig.RadioRecogidaDirectaStuds then
					perfil.OrbesActivos[orbeId] = nil
					if ProgressionService.RemoteOrbes then
						ProgressionService.RemoteOrbes:FireClient(player, "Eliminar", orbeId)
					end
					ProgressionService.AcreditarXp(player, orbe.ValorXp)
				end
			end
		end
	end
end

function ProgressionService.AcreditarXp(player: Player, cantidad: number)
	local perfil = ProgressionService.Perfiles[player]
	if not perfil or cantidad <= 0 then return end
	if perfil.Nivel >= ExperienciaConfig.NivelMaximoJugador then return end

	perfil.XpActual += cantidad

	while perfil.Nivel < ExperienciaConfig.NivelMaximoJugador and perfil.XpActual >= perfil.XpRequerida do
		perfil.XpActual -= perfil.XpRequerida
		perfil.Nivel += 1
		perfil.XpRequerida = ExperienciaConfig.CalcularXpParaNivel(perfil.Nivel)
		perfil.SeleccionesPendientes += 1
	end

	if perfil.Nivel >= ExperienciaConfig.NivelMaximoJugador then
		perfil.XpActual = 0
	end

	if perfil.SeleccionesPendientes > 0 and not perfil.OpcionesActuales then
		ProgressionService.GenerarOpcionesMejora(player)
	end

	ProgressionService.SincronizarJugador(player)
end

function ProgressionService.GenerarOpcionesMejora(player: Player)
	local perfil = ProgressionService.Perfiles[player]
	if not perfil then return end

	local candidatos: { TiposAlpha.OpcionMejora } = {}

	-- 1. Candidatos de Magias (desde CombatService / HabilidadesConfig)
	if CombatService then
		local habilidadesJugador = if typeof(CombatService.ObtenerHabilidadesJugador) == "function"
			then CombatService.ObtenerHabilidadesJugador(player)
			else nil
		local ranurasOcupadas = if typeof(CombatService.ContarRanurasHabilidades) == "function"
			then CombatService.ContarRanurasHabilidades(player)
			else 0

		for habId, habDef in HabilidadesConfig.Catalogo do
			if habDef.EtapaDesbloqueo > HabilidadesConfig.EtapaMagiasActiva then
				continue
			end

			local activa = if habilidadesJugador then habilidadesJugador[habId] else nil
			local limiteNivel = math.min(habDef.MaxNivel, HabilidadesConfig.NivelMaximoMagia)
			if activa then
				if activa.Nivel < limiteNivel then
					table.insert(candidatos, {
						IdOpcion = "MAG_UP_" .. habId,
						Tipo = "MagiaMejora",
						ReferenciaId = habId,
						Titulo = habDef.Nombre,
						Descripcion = habDef.Descripcion,
						NivelActual = activa.Nivel,
						NivelSiguiente = activa.Nivel + 1,
					})
				end
			elseif ranurasOcupadas < HabilidadesConfig.MaxRanurasActivas then
				table.insert(candidatos, {
					IdOpcion = "MAG_NEW_" .. habId,
					Tipo = "MagiaNueva",
					ReferenciaId = habId,
					Titulo = habDef.Nombre .. " (Nueva)",
					Descripcion = habDef.Descripcion,
					NivelActual = 0,
					NivelSiguiente = 1,
				})
			end
		end
	end

	-- 2. Candidatos de los 4 Atributos mejorables (excluye regeneración pasiva base)
	for attrId, attrDef in AtributosConfig.AtributosMejorables do
		local nivelAttr = perfil.NivelesAtributos[attrId] or 0
		if nivelAttr < attrDef.MaxSelecciones then
			table.insert(candidatos, {
				IdOpcion = "ATTR_" .. attrId,
				Tipo = "Atributo",
				ReferenciaId = attrId,
				Titulo = attrDef.Nombre,
				Descripcion = attrDef.Descripcion,
				NivelActual = nivelAttr,
				NivelSiguiente = nivelAttr + 1,
			})
		end
	end

	if #candidatos == 0 then
		perfil.OpcionesActuales = nil
		perfil.SeleccionesPendientes = 0
		return
	end

	-- Barajar candidatos (Fisher-Yates) y tomar hasta 3 alternativas sin repetir
	for i = #candidatos, 2, -1 do
		local j = math.random(1, i)
		candidatos[i], candidatos[j] = candidatos[j], candidatos[i]
	end

	local seleccionadas: { TiposAlpha.OpcionMejora } = {}
	local limite = math.min(3, #candidatos)
	for i = 1, limite do
		table.insert(seleccionadas, candidatos[i])
	end

	perfil.OpcionesActuales = seleccionadas
end

function ProgressionService.AplicarAtributoJugador(player: Player, attrId: string): boolean
	local perfil = ProgressionService.Perfiles[player]
	local attrDef = AtributosConfig.AtributosMejorables[attrId]
	if not perfil or not attrDef then return false end

	local nivelActual = perfil.NivelesAtributos[attrId] or 0
	if nivelActual >= attrDef.MaxSelecciones then return false end

	perfil.NivelesAtributos[attrId] = nivelActual + 1

	local char = player.Character
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil

	if attrId == "VidaMaxima" and humanoid and humanoid.Health > 0 then
		local incremento = humanoid.MaxHealth * attrDef.PorcentajePorNivel
		humanoid.MaxHealth += incremento
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + incremento)

	elseif attrId == "VelocidadMovimiento" and humanoid then
		humanoid.WalkSpeed = humanoid.WalkSpeed * (1 + attrDef.PorcentajePorNivel)

	elseif attrId == "PoderMagico" and CombatService and typeof(CombatService.ObtenerMultiplicadores) == "function" then
		local multDanio, factorCd = CombatService.ObtenerMultiplicadores(player)
		CombatService.EstablecerMultiplicadores(player, multDanio * (1 + attrDef.PorcentajePorNivel), factorCd)

	elseif attrId == "ReduccionCooldown" and CombatService and typeof(CombatService.ObtenerMultiplicadores) == "function" then
		local multDanio, factorCd = CombatService.ObtenerMultiplicadores(player)
		CombatService.EstablecerMultiplicadores(player, multDanio, factorCd * (1 - attrDef.PorcentajePorNivel))
	end

	return true
end

function ProgressionService.ProcesarSeleccionMejora(player: Player, idOpcion: any)
	if not ProgressionService.Activo then return end
	if typeof(idOpcion) ~= "string" then return end

	local perfil = ProgressionService.Perfiles[player]
	if not perfil or not perfil.OpcionesActuales or perfil.SeleccionesPendientes <= 0 then
		return
	end

	local elegida: TiposAlpha.OpcionMejora? = nil
	for _, op in perfil.OpcionesActuales do
		if op.IdOpcion == idOpcion then
			elegida = op
			break
		end
	end

	if not elegida then
		warn(string.format("[ProgressionService] %s intentó seleccionar una opción inválida: %s", player.Name, idOpcion))
		return
	end

	if elegida.Tipo == "MagiaNueva" and CombatService then
		CombatService.AgregarHabilidad(player, elegida.ReferenciaId)
	elseif elegida.Tipo == "MagiaMejora" and CombatService then
		CombatService.MejorarHabilidad(player, elegida.ReferenciaId)
	elseif elegida.Tipo == "Atributo" then
		ProgressionService.AplicarAtributoJugador(player, elegida.ReferenciaId)
	end

	perfil.OpcionesActuales = nil
	perfil.SeleccionesPendientes = math.max(0, perfil.SeleccionesPendientes - 1)

	if perfil.SeleccionesPendientes > 0 then
		ProgressionService.GenerarOpcionesMejora(player)
	end

	ProgressionService.SincronizarJugador(player)
end

function ProgressionService.ObtenerNivelJugador(player: Player): number
	local perfil = ProgressionService.Perfiles[player]
	return if perfil then perfil.Nivel else 1
end

function ProgressionService.ExportarSnapshotJugador(player: Player): any?
	local perfil = ProgressionService.Perfiles[player]
	if not perfil then return nil end

	local attrsCopia: { [string]: number } = {}
	for k, v in perfil.NivelesAtributos do
		attrsCopia[k] = v
	end

	return {
		Nivel = perfil.Nivel,
		XpActual = perfil.XpActual,
		XpRequerida = perfil.XpRequerida,
		SeleccionesPendientes = perfil.SeleccionesPendientes,
		OpcionesActuales = perfil.OpcionesActuales,
		NivelesAtributos = attrsCopia,
	}
end

function ProgressionService.RestaurarSnapshotJugador(player: Player, snapshot: any)
	if not snapshot or typeof(snapshot) ~= "table" then return end
	local perfil = ProgressionService.Perfiles[player]
	if not perfil then
		ProgressionService.RegistrarJugador(player)
		perfil = ProgressionService.Perfiles[player]
	end
	if not perfil then return end

	perfil.Nivel = snapshot.Nivel or 1
	perfil.XpActual = snapshot.XpActual or 0
	perfil.XpRequerida = snapshot.XpRequerida or ExperienciaConfig.CalcularXpParaNivel(perfil.Nivel)
	perfil.SeleccionesPendientes = snapshot.SeleccionesPendientes or 0
	perfil.OpcionesActuales = snapshot.OpcionesActuales
	perfil.NivelesAtributos = snapshot.NivelesAtributos or {}

	ProgressionService.SincronizarJugador(player)
end

function ProgressionService.Detener()
	ProgressionService.Activo = false

	if ProgressionService.ConexionHeartbeat then
		ProgressionService.ConexionHeartbeat:Disconnect()
		ProgressionService.ConexionHeartbeat = nil
	end

	if ProgressionService.RemoteOrbes then
		ProgressionService.RemoteOrbes:FireAllClients("LimpiarTodos")
	end

	table.clear(ProgressionService.Perfiles)
	print("[UMBRA Server] ProgressionService detenido y limpiado.")
end

return ProgressionService
