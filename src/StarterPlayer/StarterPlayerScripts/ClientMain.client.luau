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

local localPlayer = Players.LocalPlayer
local PlayerScripts = localPlayer:WaitForChild("PlayerScripts")
local ControllersFolder = PlayerScripts:WaitForChild("Controllers")

local CameraController = require(ControllersFolder:WaitForChild("CameraController") :: ModuleScript)
local InputController = require(ControllersFolder:WaitForChild("InputController") :: ModuleScript)

print("=========================================")
print(string.format("[UMBRA Client] Iniciando sesión para: %s (ID: %d)", localPlayer.Name, localPlayer.UserId))
print("=========================================")

local EstadoActual = "Waiting"

-- 2. Escuchar cambios de estado autoritativos desde el Servidor
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 5)
if remotesFolder then
	local remoteSincronizar = remotesFolder:WaitForChild("SincronizarEstadoPartida", 5) :: RemoteEvent?
	if remoteSincronizar and remoteSincronizar:IsA("RemoteEvent") then
		remoteSincronizar.OnClientEvent:Connect(function(nuevoEstado: string)
			local estadoPrevio = EstadoActual
			EstadoActual = nuevoEstado
			print(string.format("[UMBRA Client] Estado de sesión recibido: %s -> %s", estadoPrevio, nuevoEstado))

			if nuevoEstado == "Playing" then
				CameraController.Iniciar()
			elseif nuevoEstado == "GameOver" then
				print("[UMBRA Client] Partida finalizada. Esperando reinicio de sesión...")
			elseif nuevoEstado == "Waiting" then
				CameraController.Detener()
			end
		end)
	end
end

-- 3. Gestión segura de la carga del personaje
local function alCargarPersonaje(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?

	if humanoid and root then
		print(string.format("[UMBRA Client] Personaje de %s cargado correctamente en Workspace.", localPlayer.Name))
		if EstadoActual == "Playing" then
			CameraController.Iniciar()
		end
	end
end

if localPlayer.Character then
	task.spawn(alCargarPersonaje, localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(alCargarPersonaje)

-- 4. Iniciar controlador de inputs del cliente
InputController.Iniciar()

print("[UMBRA Client] Inicialización del cliente completada con éxito.")
