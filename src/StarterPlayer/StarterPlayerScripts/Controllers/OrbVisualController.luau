--!strict
-- OrbVisualController.luau
-- Controlador cliente ligero para renderizar únicamente los orbes individuales del LocalPlayer (Sección 10).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ConfigFolder = ReplicatedStorage:WaitForChild("Config")
local ModulesFolder = ReplicatedStorage:WaitForChild("Modules")
local ExperienciaConfig = require(ConfigFolder:WaitForChild("ExperienciaConfig") :: ModuleScript)
local TiposAlpha = require(ModulesFolder:WaitForChild("TiposAlpha") :: ModuleScript)

type OrbeVisual = {
	Id: string,
	Parte: Part,
	PosicionBase: Vector3,
	TiempoExpiracionLocal: number,
	FaseAleatoria: number,
}

local OrbVisualController = {
	Activo = false,
	CarpetaOrbes = nil :: Folder?,
	Orbes = {} :: { [string]: OrbeVisual },
	ConexionRender = nil :: RBXScriptConnection?,
	ConexionRemote = nil :: RBXScriptConnection?,
}

function OrbVisualController.Iniciar()
	if OrbVisualController.Activo then return end
	OrbVisualController.Activo = true

	local carpeta = Workspace:FindFirstChild("OrbesLocales")
	if not carpeta then
		carpeta = Instance.new("Folder")
		carpeta.Name = "OrbesLocales"
		carpeta.Parent = Workspace
	end
	OrbVisualController.CarpetaOrbes = carpeta :: Folder

	task.spawn(function()
		local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
		if not remotesFolder then return end

		local remoteOrbes = remotesFolder:WaitForChild("EventosOrbesCliente", 10) :: RemoteEvent?
		if remoteOrbes and remoteOrbes:IsA("RemoteEvent") then
			OrbVisualController.ConexionRemote = remoteOrbes.OnClientEvent:Connect(function(accion: any, payload: any)
				OrbVisualController.ProcesarEvento(accion, payload)
			end)
		end
	end)

	OrbVisualController.ConexionRender = RunService.RenderStepped:Connect(function()
		if not OrbVisualController.Activo then return end
		local ahora = os.clock()

		for _, orbe in OrbVisualController.Orbes do
			if orbe.Parte and orbe.Parte.Parent then
				local flotacion = math.sin(ahora * 3.5 + orbe.FaseAleatoria) * 0.28
				orbe.Parte.Position = orbe.PosicionBase + Vector3.new(0, flotacion, 0)

				local restante = orbe.TiempoExpiracionLocal - ahora
				if restante <= 5 then
					local pulso = 0.25 + 0.55 * (0.5 + 0.5 * math.sin(ahora * 14))
					orbe.Parte.Transparency = pulso
				else
					orbe.Parte.Transparency = 0.1
				end
			end
		end
	end)

	print("[UMBRA Client] OrbVisualController iniciado.")
end

function OrbVisualController.ProcesarEvento(accion: any, payload: any)
	if accion == "Crear" and typeof(payload) == "table" then
		local datos = payload :: TiposAlpha.OrbeSincronizado
		OrbVisualController.CrearOrbeVisual(datos)
	elseif accion == "Eliminar" and typeof(payload) == "string" then
		OrbVisualController.EliminarOrbeVisual(payload)
	elseif accion == "LimpiarTodos" then
		OrbVisualController.LimpiarTodos()
	end
end

function OrbVisualController.CrearOrbeVisual(datos: TiposAlpha.OrbeSincronizado)
	if OrbVisualController.Orbes[datos.Id] then
		OrbVisualController.EliminarOrbeVisual(datos.Id)
	end

	local catDef = ExperienciaConfig.CategoriasOrbe[datos.Categoria] or ExperienciaConfig.CategoriasOrbe.Menor
	local part = Instance.new("Part")
	part.Name = datos.Id
	part.Shape = Enum.PartType.Ball
	part.Size = catDef.Tamanio
	part.Color = catDef.Color
	part.Material = Enum.Material.Neon
	part.Transparency = 0.1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Position = datos.Posicion
	part.Parent = OrbVisualController.CarpetaOrbes or Workspace

	local luz = Instance.new("PointLight")
	luz.Color = catDef.Color
	luz.Range = 7
	luz.Brightness = 1.2
	luz.Parent = part

	OrbVisualController.Orbes[datos.Id] = {
		Id = datos.Id,
		Parte = part,
		PosicionBase = datos.Posicion,
		TiempoExpiracionLocal = os.clock() + catDef.TiempoVidaSegundos,
		FaseAleatoria = math.random() * math.pi * 2,
	}
end

function OrbVisualController.EliminarOrbeVisual(orbeId: string)
	local orbe = OrbVisualController.Orbes[orbeId]
	if orbe then
		if orbe.Parte and orbe.Parte.Parent then
			orbe.Parte:Destroy()
		end
		OrbVisualController.Orbes[orbeId] = nil
	end
end

function OrbVisualController.LimpiarTodos()
	for id, orbe in OrbVisualController.Orbes do
		if orbe.Parte and orbe.Parte.Parent then
			orbe.Parte:Destroy()
		end
		OrbVisualController.Orbes[id] = nil
	end
	if OrbVisualController.CarpetaOrbes then
		OrbVisualController.CarpetaOrbes:ClearAllChildren()
	end
end

function OrbVisualController.Detener()
	OrbVisualController.Activo = false
	if OrbVisualController.ConexionRender then
		OrbVisualController.ConexionRender:Disconnect()
		OrbVisualController.ConexionRender = nil
	end
	if OrbVisualController.ConexionRemote then
		OrbVisualController.ConexionRemote:Disconnect()
		OrbVisualController.ConexionRemote = nil
	end
	OrbVisualController.LimpiarTodos()
end

return OrbVisualController
