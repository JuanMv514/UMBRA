--!strict
-- CameraController.luau
-- Controlador de perspectiva isométrica 3D suave para UMBRA: La Última Luz.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Camera = Workspace.CurrentCamera
local localPlayer = Players.LocalPlayer

local CameraController = {
	Activo = false,
	Offset = Vector3.new(0, 38, 24), -- Elevación de 38 studs e inclinación hacia atrás de 24 studs (~58 grados)
	Suavizado = 0.15, -- Factor de interpolación lineal (Lerp)
	ObjetivoActual = nil :: BasePart?,
	Espectando = false,
	ConexionRender = nil :: RBXScriptConnection?,
}

function CameraController.FijarObjetivo(targetPart: BasePart?)
	CameraController.ObjetivoActual = targetPart
	if targetPart then
		local posObjetivo = targetPart.Position + CameraController.Offset
		Camera.CFrame = CFrame.lookAt(posObjetivo, targetPart.Position)
	end
end

function CameraController.EstablecerModoEspectador(espectando: boolean, targetPart: BasePart?)
	CameraController.Espectando = espectando
	if espectando and targetPart then
		CameraController.FijarObjetivo(targetPart)
	elseif not espectando then
		if localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart") then
			CameraController.FijarObjetivo(localPlayer.Character.HumanoidRootPart :: BasePart)
		end
	end
end

function CameraController.Iniciar()
	CameraController.Activo = true
	Camera.CameraType = Enum.CameraType.Scriptable

	local function vincularPersonaje(character: Model)
		if CameraController.Espectando then return end
		local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		if root then
			CameraController.ObjetivoActual = root
			-- Colocar inmediatamente la cámara en posición inicial para evitar saltos
			local posObjetivo = root.Position + CameraController.Offset
			Camera.CFrame = CFrame.lookAt(posObjetivo, root.Position)
		end
	end

	if localPlayer.Character then
		vincularPersonaje(localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(vincularPersonaje)

	-- Bucle de renderizado para actualización fluida a los FPS del cliente
	CameraController.ConexionRender = RunService.RenderStepped:Connect(function(dt: number)
		if not CameraController.Activo or not CameraController.ObjetivoActual then return end

		local posRoot = CameraController.ObjetivoActual.Position
		local posDeseada = posRoot + CameraController.Offset
		local cframeDeseado = CFrame.lookAt(posDeseada, posRoot)

		-- Seguimiento suave mediante interpolación (Lerp)
		Camera.CFrame = Camera.CFrame:Lerp(cframeDeseado, CameraController.Suavizado)
	end)

	print("[UMBRA Client] CameraController iniciado (Perspectiva Isométrica 3D activa).")
end

function CameraController.Detener()
	CameraController.Activo = false
	if CameraController.ConexionRender then
		CameraController.ConexionRender:Disconnect()
		CameraController.ConexionRender = nil
	end
	Camera.CameraType = Enum.CameraType.Custom
end

return CameraController
