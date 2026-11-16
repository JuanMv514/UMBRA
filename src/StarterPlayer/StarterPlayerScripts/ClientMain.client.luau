--!strict
-- ClientMain.client.luau
-- Punto de entrada único del Cliente (Client Bootstrap) para UMBRA: La última luz.
-- Responsabilidad: Orquestar controladores locales, gestionar carga del personaje y recibir estado de sesión.

-- 1. Control de inicialización única para evitar ejecuciones duplicadas
if (_G :: any).__UMBRA_CLIENT_INICIADO then
	warn("[ClientMain] Intento de inicialización duplicada cancelado.")
	return
end
(_G :: any).__UMBRA_CLIENT_INICIADO = true

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigFolder = ReplicatedStorage:WaitForChild("Config")
local PlacesConfig = require(ConfigFolder:WaitForChild("PlacesConfig") :: ModuleScript)

local localPlayer = Players.LocalPlayer
local PlayerScripts = localPlayer:WaitForChild("PlayerScripts")
local ControllersFolder = PlayerScripts:WaitForChild("Controllers")

local CameraController = require(ControllersFolder:WaitForChild("CameraController") :: ModuleScript)
local InputController = require(ControllersFolder:WaitForChild("InputController") :: ModuleScript)
local HUDController = require(ControllersFolder:WaitForChild("HUDController") :: ModuleScript)
local OrbVisualController = require(ControllersFolder:WaitForChild("OrbVisualController") :: ModuleScript)

print("=========================================")
print(string.format("[UMBRA Client] Iniciando sesión para: %s en %s", localPlayer.Name, if PlacesConfig.EsLobby() then "LOBBY" else "EXPEDICIÓN"))
print("=========================================")

local EstadoActual = "Waiting"

-- 2. Iniciar controladores del cliente
HUDController.Iniciar()
InputController.Iniciar()

-- En el Lobby, asegurar cámara libre de tercera persona; en Expedición, iniciar orbes visuales
if PlacesConfig.EsLobby() then
	CameraController.Detener()
else
	OrbVisualController.Iniciar()
end

-- 3. Escuchar cambios de estado autoritativos desde el Servidor
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 5)
if remotesFolder then
	local remoteSincronizar = remotesFolder:WaitForChild("SincronizarEstadoPartida", 5) :: RemoteEvent?
	if remoteSincronizar and remoteSincronizar:IsA("RemoteEvent") then
		remoteSincronizar.OnClientEvent:Connect(function(nuevoEstado: string)
			local estadoPrevio = EstadoActual
			EstadoActual = nuevoEstado
			print(string.format("[UMBRA Client] Estado de sesión recibido: %s -> %s", estadoPrevio, nuevoEstado))

			HUDController.ActualizarEstado(nuevoEstado)

			if nuevoEstado == "Playing" and not PlacesConfig.EsLobby() then
				CameraController.Iniciar()
			elseif nuevoEstado == "Victory" then
				print("[UMBRA Client] Partida finalizada. ¡Victoria de la expedición!")
			elseif nuevoEstado == "GameOver" then
				print("[UMBRA Client] Partida finalizada. Superviviente derrotado.")
			elseif nuevoEstado == "Waiting" or PlacesConfig.EsLobby() then
				CameraController.Detener()
			end
		end)
	end

	-- Escuchar reloj lógico sincronizado de la expedición
	local remoteReloj = remotesFolder:WaitForChild("SincronizarRelojExpedicion", 5) :: RemoteEvent?
	if remoteReloj and remoteReloj:IsA("RemoteEvent") then
		remoteReloj.OnClientEvent:Connect(function(datos: any)
			HUDController.ActualizarRelojExpedicion(datos)
		end)
	end

	-- Escuchar estado individual del jugador (modo espectador / retorno)
	local remoteIndividual = remotesFolder:WaitForChild("SincronizarEstadoIndividual", 5) :: RemoteEvent?
	if remoteIndividual and remoteIndividual:IsA("RemoteEvent") then
		remoteIndividual.OnClientEvent:Connect(function(estadoIndividual: string, modoExpedicion: string)
			print(string.format("[UMBRA Client] Estado individual: %s (Modo: %s)", estadoIndividual, modoExpedicion))
			HUDController.ActualizarEstadoIndividual(estadoIndividual, modoExpedicion)
		end)
	end

	-- Escuchar lista de supervivientes vivos para modo espectador
	local remoteSupervivientes = remotesFolder:WaitForChild("ActualizarSupervivientes", 5) :: RemoteEvent?
	if remoteSupervivientes and remoteSupervivientes:IsA("RemoteEvent") then
		remoteSupervivientes.OnClientEvent:Connect(function(lista: any)
			HUDController.ActualizarSupervivientes(lista)
		end)
	end

	-- Escuchar progresión individual (nivel, XP y tarjetas de mejora)
	local remoteProgresion = remotesFolder:WaitForChild("SincronizarProgresion", 5) :: RemoteEvent?
	if remoteProgresion and remoteProgresion:IsA("RemoteEvent") then
		remoteProgresion.OnClientEvent:Connect(function(datos: any)
			HUDController.ActualizarProgresion(datos)
		end)
	end
end

-- 4. Gestión segura de la carga del personaje
local function alCargarPersonaje(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?

	if humanoid and root then
		print(string.format("[UMBRA Client] Personaje de %s cargado correctamente en Workspace.", localPlayer.Name))
		if EstadoActual == "Playing" and not PlacesConfig.EsLobby() then
			CameraController.Iniciar()
		else
			CameraController.Detener()
		end
	end
end

if localPlayer.Character then
	task.spawn(alCargarPersonaje, localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(alCargarPersonaje)

print("[UMBRA Client] Inicialización del cliente completada con éxito.")
