--!strict
-- InputController.luau
-- Manejador adaptativo de entrada para PC (teclado/ratón) y Móviles (táctil) en UMBRA.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ConfigFolder = ReplicatedStorage:WaitForChild("Config")
local PlacesConfig = require(ConfigFolder:WaitForChild("PlacesConfig") :: ModuleScript)

local localPlayer = Players.LocalPlayer

local InputController = {
	EsDispositivoMovil = false,
}

function InputController.Iniciar()
	InputController.EsDispositivoMovil = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	-- Asegurar que los controles táctiles de movimiento de Roblox estén activos en móviles durante la expedición
	if UserInputService.TouchEnabled and not PlacesConfig.EsLobby() then
		UserInputService.ModalEnabled = false
		pcall(function()
			GuiService.TouchControlsEnabled = true
		end)
	end

	print(string.format("[UMBRA Client] InputController iniciado (Perfil: %s).",
		if InputController.EsDispositivoMovil then "Móvil/Táctil" else "PC"))

	local playerScripts = localPlayer:WaitForChild("PlayerScripts")
	local controllersFolder = playerScripts:WaitForChild("Controllers")
	local HUDController = require(controllersFolder:WaitForChild("HUDController") :: ModuleScript)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then return end
		if PlacesConfig.EsLobby() then return end

		-- Atajos numéricos opcionales (1, 2, 3) en PC para elegir tarjetas de mejora al subir de nivel
		if input.KeyCode == Enum.KeyCode.One then
			HUDController.SeleccionarMejoraPorIndice(1)
		elseif input.KeyCode == Enum.KeyCode.Two then
			HUDController.SeleccionarMejoraPorIndice(2)
		elseif input.KeyCode == Enum.KeyCode.Three then
			HUDController.SeleccionarMejoraPorIndice(3)
		end
	end)
end

return InputController
