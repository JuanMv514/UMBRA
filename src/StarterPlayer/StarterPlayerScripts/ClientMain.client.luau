--!strict
-- ClientMain.client.luau
-- Punto de entrada único del Cliente (Client Bootstrap) para UMBRA.

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer
local PlayerScripts = localPlayer:WaitForChild("PlayerScripts")

local ControllersFolder = PlayerScripts:WaitForChild("Controllers")
local InputController = require(ControllersFolder:WaitForChild("InputController") :: ModuleScript)

print(string.format("[UMBRA Client] Inicializando cliente para: %s", localPlayer.Name))

InputController.Iniciar()
