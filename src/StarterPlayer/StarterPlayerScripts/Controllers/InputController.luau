--!strict
-- InputController.luau
-- Manejador de teclado, gamepad y pantallas táctiles para UMBRA.

local UserInputService = game:GetService("UserInputService")

local InputController = {}

function InputController.Iniciar()
	print("[UMBRA Client] InputController iniciado.")

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		-- Lógica de hotkeys / habilidades manuales secundarias si aplican
	end)
end

return InputController
