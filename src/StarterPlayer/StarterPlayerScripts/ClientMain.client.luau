--!strict
-- ClientMain.client.luau
-- Punto de entrada único del Cliente (Client Bootstrap) para UMBRA: La Última Luz.

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer
local PlayerScripts = localPlayer:WaitForChild("PlayerScripts")

local ControllersFolder = PlayerScripts:WaitForChild("Controllers")
local CameraController = require(ControllersFolder:WaitForChild("CameraController") :: ModuleScript)
local InputController = require(ControllersFolder:WaitForChild("InputController") :: ModuleScript)

print(string.format("[UMBRA Client] Inicializando cliente para superviviente: %s", localPlayer.Name))

-- 1. Iniciar cámara isométrica
CameraController.Iniciar()

-- 2. Iniciar controlador de inputs
InputController.Iniciar()
