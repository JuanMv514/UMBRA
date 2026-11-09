--!strict
-- HUDController.luau
-- Interfaz gráfica en pantalla (HUD) para UMBRA: La última luz.
-- Responsabilidad: Visualizar barra de vida, estado de sesión y reloj de supervivencia.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local PlayerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

local HUDController = {
	Activo = false,
	ScreenGui = nil :: ScreenGui?,
	BarraVida = nil :: Frame?,
	TextoVida = nil :: TextLabel?,
	TextoEstado = nil :: TextLabel?,
	TextoReloj = nil :: TextLabel?,
	TiempoInicio = 0,
	ConexionReloj = nil :: RBXScriptConnection?,
}

function HUDController.Iniciar()
	if HUDController.Activo then return end
	HUDController.Activo = true

	-- 1. Crear ScreenGui principal
	local gui = Instance.new("ScreenGui")
	gui.Name = "UmbraHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = PlayerGui
	HUDController.ScreenGui = gui

	-- 2. Banner superior: Reloj y Estado
	local bannerSuperior = Instance.new("Frame")
	bannerSuperior.Name = "BannerSuperior"
	bannerSuperior.Size = UDim2.new(0, 280, 0, 50)
	bannerSuperior.Position = UDim2.new(0.5, -140, 0, 20)
	bannerSuperior.BackgroundColor3 = Color3.fromRGB(15, 12, 22)
	bannerSuperior.BackgroundTransparency = 0.25
	bannerSuperior.BorderSizePixel = 0
	bannerSuperior.Parent = gui

	local cornerBanner = Instance.new("UICorner")
	cornerBanner.CornerRadius = UDim.new(0, 10)
	cornerBanner.Parent = bannerSuperior

	local strokeBanner = Instance.new("UIStroke")
	strokeBanner.Color = Color3.fromRGB(120, 50, 200)
	strokeBanner.Thickness = 1.5
	strokeBanner.Parent = bannerSuperior

	local textoEstado = Instance.new("TextLabel")
	textoEstado.Name = "TextoEstado"
	textoEstado.Size = UDim2.new(1, 0, 0, 22)
	textoEstado.Position = UDim2.new(0, 0, 0, 4)
	textoEstado.BackgroundTransparency = 1
	textoEstado.TextColor3 = Color3.fromRGB(200, 180, 255)
	textoEstado.Font = Enum.Font.GothamBold
	textoEstado.TextSize = 13
	textoEstado.Text = "PREPARANDO SESIÓN"
	textoEstado.Parent = bannerSuperior
	HUDController.TextoEstado = textoEstado

	local textoReloj = Instance.new("TextLabel")
	textoReloj.Name = "TextoReloj"
	textoReloj.Size = UDim2.new(1, 0, 0, 22)
	textoReloj.Position = UDim2.new(0, 0, 0, 24)
	textoReloj.BackgroundTransparency = 1
	textoReloj.TextColor3 = Color3.fromRGB(255, 255, 255)
	textoReloj.Font = Enum.Font.GothamBlack
	textoReloj.TextSize = 18
	textoReloj.Text = "00:00"
	textoReloj.Parent = bannerSuperior
	HUDController.TextoReloj = textoReloj

	-- 3. Barra inferior: Salud del superviviente
	local contenedorVida = Instance.new("Frame")
	contenedorVida.Name = "ContenedorVida"
	contenedorVida.Size = UDim2.new(0, 320, 0, 26)
	contenedorVida.Position = UDim2.new(0.5, -160, 1, -65)
	contenedorVida.BackgroundColor3 = Color3.fromRGB(20, 15, 25)
	contenedorVida.BackgroundTransparency = 0.2
	contenedorVida.BorderSizePixel = 0
	contenedorVida.Parent = gui

	local cornerContenedor = Instance.new("UICorner")
	cornerContenedor.CornerRadius = UDim.new(0, 8)
	cornerContenedor.Parent = contenedorVida

	local strokeVida = Instance.new("UIStroke")
	strokeVida.Color = Color3.fromRGB(60, 40, 80)
	strokeVida.Thickness = 1.5
	strokeVida.Parent = contenedorVida

	local barraRelleno = Instance.new("Frame")
	barraRelleno.Name = "BarraRelleno"
	barraRelleno.Size = UDim2.new(1, 0, 1, 0)
	barraRelleno.BackgroundColor3 = Color3.fromRGB(220, 40, 60)
	barraRelleno.BorderSizePixel = 0
	barraRelleno.Parent = contenedorVida
	HUDController.BarraVida = barraRelleno

	local cornerRelleno = Instance.new("UICorner")
	cornerRelleno.CornerRadius = UDim.new(0, 8)
	cornerRelleno.Parent = barraRelleno

	local textoVida = Instance.new("TextLabel")
	textoVida.Name = "TextoVida"
	textoVida.Size = UDim2.new(1, 0, 1, 0)
	textoVida.BackgroundTransparency = 1
	textoVida.TextColor3 = Color3.fromRGB(255, 255, 255)
	textoVida.Font = Enum.Font.GothamBold
	textoVida.TextSize = 13
	textoVida.Text = "100 / 100"
	textoVida.Parent = contenedorVida
	HUDController.TextoVida = textoVida

	-- Conectar vida del personaje
	local function vincularSalud(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then return end

		local function actualizar()
			local ratio = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
			if HUDController.BarraVida then
				TweenService:Create(HUDController.BarraVida, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
					Size = UDim2.new(ratio, 0, 1, 0)
				}):Play()
			end
			if HUDController.TextoVida then
				HUDController.TextoVida.Text = string.format("%d / %d", math.ceil(humanoid.Health), math.ceil(humanoid.MaxHealth))
			end
		end

		actualizar()
		humanoid.HealthChanged:Connect(actualizar)
	end

	if localPlayer.Character then
		vincularSalud(localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(vincularSalud)

	-- Bucle de reloj de supervivencia
	HUDController.TiempoInicio = os.clock()
	HUDController.ConexionReloj = RunService.RenderStepped:Connect(function()
		if not HUDController.Activo or not HUDController.TextoReloj then return end
		local diff = math.floor(os.clock() - HUDController.TiempoInicio)
		local mins = math.floor(diff / 60)
		local secs = diff % 60
		HUDController.TextoReloj.Text = string.format("%02d:%02d", mins, secs)
	end)

	print("[UMBRA Client] HUDController iniciado con éxito.")
end

function HUDController.ActualizarEstado(nuevoEstado: string)
	if not HUDController.TextoEstado then return end

	if nuevoEstado == "Waiting" then
		HUDController.TextoEstado.Text = "ESPERANDO SUPERVIVIENTES"
		HUDController.TextoEstado.TextColor3 = Color3.fromRGB(180, 180, 180)
	elseif nuevoEstado == "Starting" then
		HUDController.TextoEstado.Text = "PREPARANDO SUPERVIVENCIA"
		HUDController.TextoEstado.TextColor3 = Color3.fromRGB(240, 200, 80)
	elseif nuevoEstado == "Playing" then
		HUDController.TextoEstado.Text = "SUPERVIVENCIA EN CURSO"
		HUDController.TextoEstado.TextColor3 = Color3.fromRGB(100, 240, 140)
		HUDController.TiempoInicio = os.clock()
	elseif nuevoEstado == "GameOver" then
		HUDController.TextoEstado.Text = "HAS CAÍDO EN LA OSCURIDAD"
		HUDController.TextoEstado.TextColor3 = Color3.fromRGB(255, 60, 60)
	end
end

return HUDController
