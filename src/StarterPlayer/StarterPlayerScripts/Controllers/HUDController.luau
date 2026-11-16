--!strict
-- HUDController.luau
-- Interfaz gráfica en pantalla (HUD) para UMBRA: La última luz.
-- Responsabilidad: Reconocer autoritativamente si el jugador se encuentra en el Lobby o en la Expedición.
-- En el Lobby: oculta barra de vida y temporizador; muestra únicamente emparejamiento.
-- En la Expedición: muestra salud, temporizador de supervivencia activo y pantalla modal de derrota con reloj congelado.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ConfigFolder = ReplicatedStorage:WaitForChild("Config")
local PlacesConfig = require(ConfigFolder:WaitForChild("PlacesConfig") :: ModuleScript)

local localPlayer = Players.LocalPlayer
local PlayerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

local HUDController = {
	Activo = false,
	ScreenGui = nil :: ScreenGui?,
	BarraVida = nil :: Frame?,
	TextoVida = nil :: TextLabel?,
	ContenedorVida = nil :: Frame?,
	TextoEstado = nil :: TextLabel?,
	TextoReloj = nil :: TextLabel?,
	BannerSuperior = nil :: Frame?,
	BannerMatchmaking = nil :: Frame?,
	TextoMatchmaking = nil :: TextLabel?,
	ModalGameOver = nil :: Frame?,
	OverlayFondo = nil :: Frame?,
	TextoTiempoFinal = nil :: TextLabel?,
	NotaReaparicion = nil :: TextLabel?,
	TituloGameOver = nil :: TextLabel?,
	SubtituloGameOver = nil :: TextLabel?,
	TiempoInicio = 0,
	TiempoFinalCongelado = 0,
	RelojCongelado = false,
	ConexionReloj = nil :: RBXScriptConnection?,
	-- Modo espectador y estado individual
	ModoExpedicion = "Solo",
	EstadoIndividual = "Alive",
	SupervivientesVivos = {} :: { { UserId: number, Name: string } },
	IndiceEspectador = 1,
	ContenedorEspectador = nil :: Frame?,
	TextoEspectadorNombre = nil :: TextLabel?,
	BotonSalirLobby = nil :: TextButton?,
}

function HUDController.Iniciar()
	if HUDController.Activo then return end
	HUDController.Activo = true

	local esLobby = PlacesConfig.EsLobby()

	-- 1. Crear ScreenGui principal
	local gui = Instance.new("ScreenGui")
	gui.Name = "UmbraHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = PlayerGui
	HUDController.ScreenGui = gui

	-- 2. Banner superior: Reloj y Estado (SOLO para Expedición)
	local bannerSuperior = Instance.new("Frame")
	bannerSuperior.Name = "BannerSuperior"
	bannerSuperior.Size = UDim2.new(0, 300, 0, 52)
	bannerSuperior.Position = UDim2.new(0.5, -150, 0, 16)
	bannerSuperior.BackgroundColor3 = Color3.fromRGB(15, 12, 22)
	bannerSuperior.BackgroundTransparency = 0.25
	bannerSuperior.BorderSizePixel = 0
	bannerSuperior.Visible = not esLobby -- Oculto en el Lobby
	bannerSuperior.Parent = gui
	HUDController.BannerSuperior = bannerSuperior

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
	textoEstado.Text = if esLobby then "SANTUARIO" else "PREPARANDO EXPEDICIÓN"
	textoEstado.Parent = bannerSuperior
	HUDController.TextoEstado = textoEstado

	local textoReloj = Instance.new("TextLabel")
	textoReloj.Name = "TextoReloj"
	textoReloj.Size = UDim2.new(1, 0, 0, 24)
	textoReloj.Position = UDim2.new(0, 0, 0, 24)
	textoReloj.BackgroundTransparency = 1
	textoReloj.TextColor3 = Color3.fromRGB(255, 255, 255)
	textoReloj.Font = Enum.Font.GothamBlack
	textoReloj.TextSize = 18
	textoReloj.Text = "00:00"
	textoReloj.Parent = bannerSuperior
	HUDController.TextoReloj = textoReloj

	-- 3. Banner de Matchmaking en pantalla (para el Lobby)
	local bannerMM = Instance.new("Frame")
	bannerMM.Name = "BannerMatchmaking"
	bannerMM.Size = UDim2.new(0, 420, 0, 40)
	bannerMM.Position = UDim2.new(0.5, -210, 0, 20)
	bannerMM.BackgroundColor3 = Color3.fromRGB(20, 15, 30)
	bannerMM.BackgroundTransparency = 0.25
	bannerMM.BorderSizePixel = 0
	bannerMM.Visible = false
	bannerMM.Parent = gui
	HUDController.BannerMatchmaking = bannerMM

	local cornerMM = Instance.new("UICorner")
	cornerMM.CornerRadius = UDim.new(0, 8)
	cornerMM.Parent = bannerMM

	local strokeMM = Instance.new("UIStroke")
	strokeMM.Color = Color3.fromRGB(80, 220, 255)
	strokeMM.Thickness = 1.2
	strokeMM.Parent = bannerMM

	local textoMM = Instance.new("TextLabel")
	textoMM.Name = "TextoMatchmaking"
	textoMM.Size = UDim2.new(1, 0, 1, 0)
	textoMM.BackgroundTransparency = 1
	textoMM.TextColor3 = Color3.fromRGB(220, 245, 255)
	textoMM.Font = Enum.Font.GothamBold
	textoMM.TextSize = 13
	textoMM.Text = "EXPEDICIÓN EN PREPARACIÓN"
	textoMM.Parent = bannerMM
	HUDController.TextoMatchmaking = textoMM

	-- 4. Barra inferior: Salud del superviviente (SOLO para Expedición)
	local contenedorVida = Instance.new("Frame")
	contenedorVida.Name = "ContenedorVida"
	contenedorVida.Size = UDim2.new(0, 320, 0, 26)
	contenedorVida.Position = UDim2.new(0.5, -160, 1, -65)
	contenedorVida.BackgroundColor3 = Color3.fromRGB(20, 15, 25)
	contenedorVida.BackgroundTransparency = 0.2
	contenedorVida.BorderSizePixel = 0
	contenedorVida.Visible = not esLobby -- Oculto en el Lobby
	contenedorVida.Parent = gui
	HUDController.ContenedorVida = contenedorVida

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

	-- 5. Modal de Derrota (Game Over)
	local overlay = Instance.new("Frame")
	overlay.Name = "OverlayGameOver"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.Position = UDim2.new(0, 0, 0, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(5, 2, 8)
	overlay.BackgroundTransparency = 1
	overlay.Visible = false
	overlay.ZIndex = 50
	overlay.Parent = gui
	HUDController.OverlayFondo = overlay

	local modal = Instance.new("Frame")
	modal.Name = "ModalGameOver"
	modal.Size = UDim2.new(0, 460, 0, 280)
	modal.Position = UDim2.new(0.5, -230, 0.5, -140)
	modal.BackgroundColor3 = Color3.fromRGB(18, 12, 26)
	modal.BackgroundTransparency = 0.15
	modal.BorderSizePixel = 0
	modal.Visible = false
	modal.ZIndex = 51
	modal.Parent = gui
	HUDController.ModalGameOver = modal

	local cornerModal = Instance.new("UICorner")
	cornerModal.CornerRadius = UDim.new(0, 14)
	cornerModal.Parent = modal

	local strokeModal = Instance.new("UIStroke")
	strokeModal.Color = Color3.fromRGB(180, 40, 60)
	strokeModal.Thickness = 2
	strokeModal.Parent = modal

	local tituloGO = Instance.new("TextLabel")
	tituloGO.Name = "TituloGameOver"
	tituloGO.Size = UDim2.new(1, 0, 0, 36)
	tituloGO.Position = UDim2.new(0, 0, 0, 18)
	tituloGO.BackgroundTransparency = 1
	tituloGO.TextColor3 = Color3.fromRGB(255, 60, 70)
	tituloGO.Font = Enum.Font.GothamBlack
	tituloGO.TextSize = 22
	tituloGO.Text = "HAS CAÍDO EN LA OSCURIDAD"
	tituloGO.ZIndex = 52
	tituloGO.Parent = modal
	HUDController.TituloGameOver = tituloGO

	local subtituloGO = Instance.new("TextLabel")
	subtituloGO.Name = "SubtituloGameOver"
	subtituloGO.Size = UDim2.new(1, -40, 0, 32)
	subtituloGO.Position = UDim2.new(0, 20, 0, 56)
	subtituloGO.BackgroundTransparency = 1
	subtituloGO.TextColor3 = Color3.fromRGB(190, 175, 210)
	subtituloGO.Font = Enum.Font.GothamMedium
	subtituloGO.TextSize = 13
	subtituloGO.TextWrapped = true
	subtituloGO.Text = "El Vacío ha consumido tu último resplandor. La expedición ha terminado."
	subtituloGO.ZIndex = 52
	subtituloGO.Parent = modal
	HUDController.SubtituloGameOver = subtituloGO

	local boxTiempo = Instance.new("Frame")
	boxTiempo.Name = "BoxTiempo"
	boxTiempo.Size = UDim2.new(0, 380, 0, 76)
	boxTiempo.Position = UDim2.new(0.5, -190, 0, 98)
	boxTiempo.BackgroundColor3 = Color3.fromRGB(12, 8, 18)
	boxTiempo.BackgroundTransparency = 0.3
	boxTiempo.BorderSizePixel = 0
	boxTiempo.ZIndex = 52
	boxTiempo.Parent = modal

	local cornerBox = Instance.new("UICorner")
	cornerBox.CornerRadius = UDim.new(0, 8)
	cornerBox.Parent = boxTiempo

	local strokeBox = Instance.new("UIStroke")
	strokeBox.Color = Color3.fromRGB(140, 60, 220)
	strokeBox.Thickness = 1
	strokeBox.Parent = boxTiempo

	local labelBox = Instance.new("TextLabel")
	labelBox.Name = "LabelTiempo"
	labelBox.Size = UDim2.new(1, 0, 0, 22)
	labelBox.Position = UDim2.new(0, 0, 0, 8)
	labelBox.BackgroundTransparency = 1
	labelBox.TextColor3 = Color3.fromRGB(240, 200, 80)
	labelBox.Font = Enum.Font.GothamBold
	labelBox.TextSize = 12
	labelBox.Text = "TIEMPO SOBREVIVIDO"
	labelBox.ZIndex = 53
	labelBox.Parent = boxTiempo

	local txtTiempoFinal = Instance.new("TextLabel")
	txtTiempoFinal.Name = "TextoTiempoFinal"
	txtTiempoFinal.Size = UDim2.new(1, 0, 0, 36)
	txtTiempoFinal.Position = UDim2.new(0, 0, 0, 30)
	txtTiempoFinal.BackgroundTransparency = 1
	txtTiempoFinal.TextColor3 = Color3.fromRGB(255, 255, 255)
	txtTiempoFinal.Font = Enum.Font.GothamBlack
	txtTiempoFinal.TextSize = 28
	txtTiempoFinal.Text = "00:00"
	txtTiempoFinal.ZIndex = 53
	txtTiempoFinal.Parent = boxTiempo
	HUDController.TextoTiempoFinal = txtTiempoFinal

	local notaReaparicion = Instance.new("TextLabel")
	notaReaparicion.Name = "NotaReaparicion"
	notaReaparicion.Size = UDim2.new(1, 0, 0, 26)
	notaReaparicion.Position = UDim2.new(0, 0, 0, 192)
	notaReaparicion.BackgroundTransparency = 1
	notaReaparicion.TextColor3 = Color3.fromRGB(160, 150, 180)
	notaReaparicion.Font = Enum.Font.Gotham
	notaReaparicion.TextSize = 12
	notaReaparicion.Text = "Retornando al Santuario..."
	notaReaparicion.ZIndex = 52
	notaReaparicion.Parent = modal
	HUDController.NotaReaparicion = notaReaparicion

	-- 5.1 Barra de Modo Espectador (Cooperativo)
	local contenedorEsp = Instance.new("Frame")
	contenedorEsp.Name = "ContenedorEspectador"
	contenedorEsp.Size = UDim2.new(0, 520, 0, 78)
	contenedorEsp.Position = UDim2.new(0.5, -260, 1, -95)
	contenedorEsp.BackgroundColor3 = Color3.fromRGB(15, 10, 22)
	contenedorEsp.BackgroundTransparency = 0.15
	contenedorEsp.BorderSizePixel = 0
	contenedorEsp.Visible = false
	contenedorEsp.ZIndex = 40
	contenedorEsp.Parent = gui
	HUDController.ContenedorEspectador = contenedorEsp

	local cornerEsp = Instance.new("UICorner")
	cornerEsp.CornerRadius = UDim.new(0, 10)
	cornerEsp.Parent = contenedorEsp

	local strokeEsp = Instance.new("UIStroke")
	strokeEsp.Color = Color3.fromRGB(130, 70, 230)
	strokeEsp.Thickness = 1.5
	strokeEsp.Parent = contenedorEsp

	local headerEsp = Instance.new("TextLabel")
	headerEsp.Name = "HeaderEspectador"
	headerEsp.Size = UDim2.new(1, -20, 0, 18)
	headerEsp.Position = UDim2.new(0, 10, 0, 6)
	headerEsp.BackgroundTransparency = 1
	headerEsp.TextColor3 = Color3.fromRGB(120, 220, 255)
	headerEsp.Font = Enum.Font.GothamBold
	headerEsp.TextSize = 11
	headerEsp.Text = "MODO ESPECTADOR — OBSERVANDO COMPAÑERO"
	headerEsp.ZIndex = 41
	headerEsp.Parent = contenedorEsp

	local btnAnt = Instance.new("TextButton")
	btnAnt.Name = "BotonAnterior"
	btnAnt.Size = UDim2.new(0, 36, 0, 36)
	btnAnt.Position = UDim2.new(0, 12, 0, 28)
	btnAnt.BackgroundColor3 = Color3.fromRGB(30, 20, 45)
	btnAnt.TextColor3 = Color3.fromRGB(240, 240, 255)
	btnAnt.Font = Enum.Font.GothamBlack
	btnAnt.TextSize = 18
	btnAnt.Text = "◄"
	btnAnt.ZIndex = 41
	btnAnt.Parent = contenedorEsp
	local cornerBtnAnt = Instance.new("UICorner")
	cornerBtnAnt.CornerRadius = UDim.new(0, 6)
	cornerBtnAnt.Parent = btnAnt
	btnAnt.MouseButton1Click:Connect(function()
		HUDController.CambiarObjetivoEspectador(-1)
	end)

	local txtNombreEsp = Instance.new("TextLabel")
	txtNombreEsp.Name = "TextoEspectadorNombre"
	txtNombreEsp.Size = UDim2.new(0, 220, 0, 36)
	txtNombreEsp.Position = UDim2.new(0, 54, 0, 28)
	txtNombreEsp.BackgroundColor3 = Color3.fromRGB(22, 14, 32)
	txtNombreEsp.BackgroundTransparency = 0.4
	txtNombreEsp.TextColor3 = Color3.fromRGB(255, 255, 255)
	txtNombreEsp.Font = Enum.Font.GothamBold
	txtNombreEsp.TextSize = 14
	txtNombreEsp.Text = "Buscando superviviente..."
	txtNombreEsp.ZIndex = 41
	txtNombreEsp.Parent = contenedorEsp
	local cornerTxt = Instance.new("UICorner")
	cornerTxt.CornerRadius = UDim.new(0, 6)
	cornerTxt.Parent = txtNombreEsp
	HUDController.TextoEspectadorNombre = txtNombreEsp

	local btnSig = Instance.new("TextButton")
	btnSig.Name = "BotonSiguiente"
	btnSig.Size = UDim2.new(0, 36, 0, 36)
	btnSig.Position = UDim2.new(0, 280, 0, 28)
	btnSig.BackgroundColor3 = Color3.fromRGB(30, 20, 45)
	btnSig.TextColor3 = Color3.fromRGB(240, 240, 255)
	btnSig.Font = Enum.Font.GothamBlack
	btnSig.TextSize = 18
	btnSig.Text = "►"
	btnSig.ZIndex = 41
	btnSig.Parent = contenedorEsp
	local cornerBtnSig = Instance.new("UICorner")
	cornerBtnSig.CornerRadius = UDim.new(0, 6)
	cornerBtnSig.Parent = btnSig
	btnSig.MouseButton1Click:Connect(function()
		HUDController.CambiarObjetivoEspectador(1)
	end)

	local btnSalir = Instance.new("TextButton")
	btnSalir.Name = "BotonSalirLobby"
	btnSalir.Size = UDim2.new(0, 180, 0, 36)
	btnSalir.Position = UDim2.new(1, -192, 0, 28)
	btnSalir.BackgroundColor3 = Color3.fromRGB(160, 35, 55)
	btnSalir.TextColor3 = Color3.fromRGB(255, 255, 255)
	btnSalir.Font = Enum.Font.GothamBold
	btnSalir.TextSize = 12
	btnSalir.Text = "REGRESAR AL LOBBY"
	btnSalir.ZIndex = 41
	btnSalir.Parent = contenedorEsp
	local cornerBtnSalir = Instance.new("UICorner")
	cornerBtnSalir.CornerRadius = UDim.new(0, 6)
	cornerBtnSalir.Parent = btnSalir
	HUDController.BotonSalirLobby = btnSalir

	btnSalir.MouseButton1Click:Connect(function()
		btnSalir.Text = "Teletransportando..."
		btnSalir.Active = false
		local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
		if remotesFolder then
			local remoteRetorno = remotesFolder:FindFirstChild("SolicitarRetornoIndividual") :: RemoteEvent?
			if remoteRetorno then
				remoteRetorno:FireServer()
			end
		end
	end)
	notaReaparicion.ZIndex = 52
	notaReaparicion.Parent = modal
	HUDController.NotaReaparicion = notaReaparicion

	-- 6. Conectar vida y detección de muerte del personaje
	local function vincularSalud(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then return end

		local function actualizar()
			if PlacesConfig.EsLobby() then return end

			local maxH = math.max(humanoid.MaxHealth, 1)
			local ratio = math.clamp(humanoid.Health / maxH, 0, 1)
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

		humanoid.Died:Connect(function()
			if not PlacesConfig.EsLobby() then
				if HUDController.ModoExpedicion == "Solo" then
					HUDController.DispararDerrota()
				else
					-- En modo cooperativo, ocultar barra de salud local
					if HUDController.ContenedorVida then
						HUDController.ContenedorVida.Visible = false
					end
				end
			end
		end)
	end

	if localPlayer.Character then
		vincularSalud(localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(function(char)
		task.wait(0.5)
		vincularSalud(char)
	end)

	-- 7. Bucle de reloj de supervivencia: SOLO se activa en la Expedición durante "Playing"
	-- En el Lobby no se conecta ningún cronómetro ascendente.
	if not esLobby then
		HUDController.ConexionReloj = RunService.RenderStepped:Connect(function()
			if not HUDController.Activo or not HUDController.TextoReloj then return end
			if HUDController.RelojCongelado then return end
			if HUDController.TiempoInicio <= 0 then return end

			local diff = math.max(0, math.floor(os.clock() - HUDController.TiempoInicio))
			local mins = math.floor(diff / 60)
			local secs = diff % 60
			HUDController.TextoReloj.Text = string.format("%02d:%02d", mins, secs)
		end)
	end

	-- 8. Escuchar eventos de emparejamiento desde el servidor (Lobby)
	task.spawn(function()
		local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
		if remotesFolder then
			local remoteMM = remotesFolder:WaitForChild("SincronizarMatchmaking", 10) :: RemoteEvent?
			if remoteMM then
				remoteMM.OnClientEvent:Connect(function(datos: any)
					HUDController.ActualizarMatchmaking(datos)
				end)
			end
		end
	end)

	print(string.format("[UMBRA Client] HUDController iniciado con éxito (Modo: %s).", if esLobby then "Lobby" else "Expedición"))
end

function HUDController.DispararDerrota()
	if HUDController.RelojCongelado then return end
	HUDController.RelojCongelado = true

	local tiempoTotal = 0
	if HUDController.TiempoInicio > 0 then
		tiempoTotal = math.max(0, math.floor(os.clock() - HUDController.TiempoInicio))
	end
	HUDController.TiempoFinalCongelado = tiempoTotal

	local mins = math.floor(tiempoTotal / 60)
	local secs = tiempoTotal % 60
	local formatoTiempo = string.format("%02d:%02d", mins, secs)

	if HUDController.TextoReloj then
		HUDController.TextoReloj.Text = formatoTiempo
		HUDController.TextoReloj.TextColor3 = Color3.fromRGB(255, 70, 70)
	end

	if HUDController.TextoTiempoFinal then
		HUDController.TextoTiempoFinal.Text = formatoTiempo
	end

	if HUDController.TextoEstado then
		HUDController.TextoEstado.Text = "EXPEDICIÓN FALLIDA"
		HUDController.TextoEstado.TextColor3 = Color3.fromRGB(255, 60, 60)
	end

	if HUDController.NotaReaparicion then
		HUDController.NotaReaparicion.Text = "Retornando al Santuario..."
	end

	if HUDController.OverlayFondo and HUDController.ModalGameOver then
		HUDController.OverlayFondo.Visible = true
		HUDController.ModalGameOver.Visible = true

		TweenService:Create(HUDController.OverlayFondo, TweenInfo.new(0.5), {
			BackgroundTransparency = 0.4
		}):Play()

		HUDController.ModalGameOver.Position = UDim2.new(0.5, -230, 0.45, -140)
		TweenService:Create(HUDController.ModalGameOver, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, -230, 0.5, -140)
		}):Play()
	end
end

function HUDController.OcultarDerrota()
	HUDController.RelojCongelado = false
	if HUDController.OverlayFondo then
		HUDController.OverlayFondo.Visible = false
	end
	if HUDController.ModalGameOver then
		HUDController.ModalGameOver.Visible = false
	end
	if HUDController.TextoReloj then
		HUDController.TextoReloj.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
end

function HUDController.ActualizarMatchmaking(datos: any)
	if not HUDController.BannerMatchmaking or not HUDController.TextoMatchmaking then return end
	if not datos or typeof(datos) ~= "table" then return end

	-- Si hay un mensaje de alerta (ej: PlaceId no configurado)
	if datos.MensajeAlerta then
		HUDController.BannerMatchmaking.Visible = true
		HUDController.TextoMatchmaking.Text = tostring(datos.MensajeAlerta)
		HUDController.TextoMatchmaking.TextColor3 = Color3.fromRGB(255, 80, 80)
		task.delay(6, function()
			if HUDController.BannerMatchmaking and not datos.CuentaActiva then
				HUDController.BannerMatchmaking.Visible = false
			end
		end)
		return
	end

	local total = datos.Total or 0
	local maximo = datos.Maximo or 4
	local cuentaActiva = datos.CuentaActiva or false
	local cuentaAtras = datos.CuentaAtras or 15

	if total > 0 then
		HUDController.BannerMatchmaking.Visible = true
		if cuentaActiva then
			HUDController.TextoMatchmaking.Text = string.format("PORTAL EXPEDICIÓN (%d/%d) — TELETRANSPORTE EN %d SEG", total, maximo, cuentaAtras)
			HUDController.TextoMatchmaking.TextColor3 = Color3.fromRGB(255, 225, 90)
		else
			HUDController.TextoMatchmaking.Text = string.format("PORTAL EXPEDICIÓN (%d/%d) — ESPERANDO GRUPO...", total, maximo)
			HUDController.TextoMatchmaking.TextColor3 = Color3.fromRGB(100, 240, 255)
		end
	else
		HUDController.BannerMatchmaking.Visible = false
	end
end

function HUDController.ActualizarEstado(nuevoEstado: string)
	local esLobby = PlacesConfig.EsLobby()

	-- En el Lobby, todos los elementos de combate y reloj permanecen ocultos
	if esLobby then
		if HUDController.BannerSuperior then HUDController.BannerSuperior.Visible = false end
		if HUDController.ContenedorVida then HUDController.ContenedorVida.Visible = false end
		if HUDController.ModalGameOver then HUDController.ModalGameOver.Visible = false end
		return
	end

	-- En la Expedición:
	if not HUDController.TextoEstado then return end

	if nuevoEstado == "Waiting" or nuevoEstado == "Starting" then
		HUDController.TextoEstado.Text = "PREPARANDO EXPEDICIÓN"
		HUDController.TextoEstado.TextColor3 = Color3.fromRGB(240, 200, 80)
		HUDController.OcultarDerrota()
		if HUDController.BannerSuperior then HUDController.BannerSuperior.Visible = true end
		if HUDController.ContenedorVida then HUDController.ContenedorVida.Visible = true end

	elseif nuevoEstado == "Playing" then
		HUDController.TextoEstado.Text = "SUPERVIVENCIA EN CURSO"
		HUDController.TextoEstado.TextColor3 = Color3.fromRGB(100, 240, 140)
		HUDController.OcultarDerrota()
		HUDController.TiempoInicio = os.clock()
		HUDController.RelojCongelado = false
		if HUDController.BannerSuperior then HUDController.BannerSuperior.Visible = true end
		if HUDController.ContenedorVida then HUDController.ContenedorVida.Visible = true end
		if HUDController.BannerMatchmaking then HUDController.BannerMatchmaking.Visible = false end

	elseif nuevoEstado == "GameOver" then
		HUDController.DetenerEspectador()
		if HUDController.ModoExpedicion == "Coop" then
			if HUDController.TituloGameOver then
				HUDController.TituloGameOver.Text = "TODA LA ESCUADRA HA CAÍDO"
			end
			if HUDController.SubtituloGameOver then
				HUDController.SubtituloGameOver.Text = "Todos los supervivientes han sido consumidos por El Vacío. La expedición ha terminado."
			end
		end
		HUDController.DispararDerrota()

	elseif nuevoEstado == "ReturningToLobby" then
		if HUDController.BotonSalirLobby then
			HUDController.BotonSalirLobby.Text = "Teletransportando..."
			HUDController.BotonSalirLobby.Active = false
		end
		if HUDController.NotaReaparicion then
			HUDController.NotaReaparicion.Text = "Teletransportando al Santuario (Lobby)..."
			HUDController.NotaReaparicion.TextColor3 = Color3.fromRGB(80, 220, 255)
		end
	end
end

-- =========================================================================
-- MÉTODOS DEL MODO ESPECTADOR (COOPERATIVO)
-- =========================================================================

function HUDController.IniciarEspectador()
	if HUDController.ContenedorVida then
		HUDController.ContenedorVida.Visible = false
	end
	if HUDController.ModalGameOver then
		HUDController.ModalGameOver.Visible = false
	end
	if HUDController.OverlayFondo then
		HUDController.OverlayFondo.Visible = false
	end

	if HUDController.ContenedorEspectador then
		HUDController.ContenedorEspectador.Visible = true
	end

	HUDController.CambiarObjetivoEspectador(0)
end

function HUDController.DetenerEspectador()
	if HUDController.ContenedorEspectador then
		HUDController.ContenedorEspectador.Visible = false
	end

	local controllers = localPlayer:WaitForChild("PlayerScripts"):WaitForChild("Controllers")
	local CameraController = require(controllers:WaitForChild("CameraController") :: ModuleScript)
	CameraController.EstablecerModoEspectador(false, nil)
end

function HUDController.ActualizarSupervivientes(lista: { { UserId: number, Name: string } })
	HUDController.SupervivientesVivos = lista or {}
	if HUDController.EstadoIndividual == "Spectating" then
		HUDController.CambiarObjetivoEspectador(0)
	end
end

function HUDController.CambiarObjetivoEspectador(delta: number)
	local lista = HUDController.SupervivientesVivos
	if not lista or #lista == 0 then
		if HUDController.TextoEspectadorNombre then
			HUDController.TextoEspectadorNombre.Text = "Sin supervivientes vivos"
		end
		return
	end

	HUDController.IndiceEspectador = ((HUDController.IndiceEspectador - 1 + delta) % #lista) + 1
	local obj = lista[HUDController.IndiceEspectador]

	if obj then
		if HUDController.TextoEspectadorNombre then
			HUDController.TextoEspectadorNombre.Text = obj.Name
		end

		local targetPlayer = Players:GetPlayerByUserId(obj.UserId)
		if targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
			local controllers = localPlayer:WaitForChild("PlayerScripts"):WaitForChild("Controllers")
			local CameraController = require(controllers:WaitForChild("CameraController") :: ModuleScript)
			CameraController.EstablecerModoEspectador(true, targetPlayer.Character.HumanoidRootPart :: BasePart)
		end
	end
end

function HUDController.ActualizarEstadoIndividual(nuevoEstado: string, modo: string)
	HUDController.EstadoIndividual = nuevoEstado
	if modo and modo ~= "" then
		HUDController.ModoExpedicion = modo
	end

	if nuevoEstado == "Spectating" then
		HUDController.IniciarEspectador()
	elseif nuevoEstado == "ReturningToLobby" then
		if HUDController.BotonSalirLobby then
			HUDController.BotonSalirLobby.Text = "Teletransportando..."
			HUDController.BotonSalirLobby.Active = false
		end
		if HUDController.NotaReaparicion then
			HUDController.NotaReaparicion.Text = "Teletransportando al Santuario (Lobby)..."
		end
	end
end

return HUDController
