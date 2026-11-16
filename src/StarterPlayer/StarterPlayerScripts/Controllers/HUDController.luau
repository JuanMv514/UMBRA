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
local Workspace = game:GetService("Workspace")

local ConfigFolder = ReplicatedStorage:WaitForChild("Config")
local ModulesFolder = ReplicatedStorage:WaitForChild("Modules")
local PlacesConfig = require(ConfigFolder:WaitForChild("PlacesConfig") :: ModuleScript)
local DevTestConfig = require(ConfigFolder:WaitForChild("DevTestConfig") :: ModuleScript)
local TiposAlpha = require(ModulesFolder:WaitForChild("TiposAlpha") :: ModuleScript)

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
	-- Reloj lógico sincronizado con servidor
	TiempoLogicoSegundos = 0,
	MultiplicadorTiempo = DevTestConfig.MultiplicadorPorDefecto,
	ModoAceleradoActivo = false,
	RelojEnCurso = false,
	TiempoFinalCongelado = 0,
	RelojCongelado = false,
	ConexionReloj = nil :: RBXScriptConnection?,
	-- Panel de desarrollo [DEV] (solo jugadores autorizados en Expedición)
	PanelDev = nil :: Frame?,
	BotonDevVelocidad = nil :: TextButton?,
	BotonDevPreJefe = nil :: TextButton?,
	-- Barra de experiencia y panel de mejoras (solo en Expedición)
	ContenedorXP = nil :: Frame?,
	BarraXP = nil :: Frame?,
	TextoNivel = nil :: TextLabel?,
	TextoXP = nil :: TextLabel?,
	PanelMejorasNivel = nil :: Frame?,
	TarjetasMejora = {} :: { {
		Boton: TextButton,
		Tipo: TextLabel,
		Titulo: TextLabel,
		Nivel: TextLabel,
		Descripcion: TextLabel,
		IdOpcionActual: string?,
	} },
	ContenedorRanurasMagia = nil :: Frame?,
	RanurasMagiaHUD = {} :: { {
		Marco: Frame,
		Borde: UIStroke,
		Numero: TextLabel,
		Nombre: TextLabel,
		Nivel: TextLabel,
	} },
	-- Barra de vida del Jefe Final (solo en Expedición)
	ContenedorVidaJefe = nil :: Frame?,
	BarraVidaJefe = nil :: Frame?,
	TextoNombreJefe = nil :: TextLabel?,
	TextoVidaJefe = nil :: TextLabel?,
	-- Panel de acceso y sala cooperativa (solo en Lobby)
	PanelAccesoLobby = nil :: Frame?,
	TextoAlertaLobby = nil :: TextLabel?,
	PanelSalaCoop = nil :: Frame?,
	TextoPlazasSala = nil :: TextLabel?,
	TextoEstadoSala = nil :: TextLabel?,
	FilasParticipantesSala = {} :: { { Nombre: TextLabel, Rol: TextLabel, Estado: TextLabel } },
	BotonIniciarSala = nil :: TextButton?,
	BotonAbandonarSala = nil :: TextButton?,
	-- Modo espectador y estado individual
	ModoExpedicion = "Solo",
	EstadoIndividual = "Alive",
	SupervivientesVivos = {} :: { TiposAlpha.MiembroEquipoEspectador },
	EquipoCompleto = {} :: { TiposAlpha.MiembroEquipoEspectador },
	IndiceEspectador = 1,
	ContenedorEspectador = nil :: Frame?,
	TextoEspectadorNombre = nil :: TextLabel?,
	TextoNivelEspectador = nil :: TextLabel?,
	BarraVidaEspectador = nil :: Frame?,
	TextoVidaEspectador = nil :: TextLabel?,
	FilasEquipoEspectador = {} :: { {
		Boton: TextButton,
		Nombre: TextLabel,
		Estado: TextLabel,
		UserIdActual: number?,
	} },
	BotonSalirLobby = nil :: TextButton?,
	-- Reconexión en Lobby
	BannerReconexion = nil :: Frame?,
	TextoReconexion = nil :: TextLabel?,
	BotonReconectar = nil :: TextButton?,
	SegundosReconexionRestantes = 0,
	-- Escala responsiva PC/Móvil, indicadores cooperativos y resultados finales (Fase 7)
	UIScaleRef = nil :: UIScale?,
	JefeActivoLocal = false,
	ContenedorCompanieros = nil :: Frame?,
	TarjetasCompanieros = {} :: { {
		Marco: Frame,
		Nombre: TextLabel,
		BarraVida: Frame,
		Estado: TextLabel,
	} },
	PantallaTransicionFin = nil :: Frame?,
	TextoTransicionResultado = nil :: TextLabel?,
	PanelResultados = nil :: Frame?,
	SeccionesResultados = {} :: { Frame },
	BotonesTabResultados = {} :: { TextButton },
	TextosResumen = {} :: { [string]: TextLabel },
	TextosRecompensas = {} :: { [string]: TextLabel },
	TextoDanioTotalCombate = nil :: TextLabel?,
	ListaMagiasCombate = nil :: ScrollingFrame?,
	ModalConfirmacionSalida = nil :: Frame?,
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

	-- 1.1 Escala adaptativa automática para PC y Móviles (Secciones 5 y 16)
	local uiScale = Instance.new("UIScale")
	uiScale.Name = "EscalaResponsiva"
	uiScale.Parent = gui
	HUDController.UIScaleRef = uiScale

	local function actualizarEscalaViewport()
		local cam = Workspace.CurrentCamera
		if not cam or not HUDController.UIScaleRef then return end
		local vp = cam.ViewportSize
		if vp.X > 0 and vp.Y > 0 then
			HUDController.UIScaleRef.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.58, 1.15)
		end
	end

	local function vincularCamaraViewport(cam: Camera?)
		if not cam then return end
		actualizarEscalaViewport()
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(actualizarEscalaViewport)
	end
	vincularCamaraViewport(Workspace.CurrentCamera)
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		vincularCamaraViewport(Workspace.CurrentCamera)
	end)

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

	-- 2.1 Barra de Vida del Jefe Final (debajo del reloj de expedición, oculta por defecto)
	local contenedorJefe = Instance.new("Frame")
	contenedorJefe.Name = "ContenedorVidaJefe"
	contenedorJefe.Size = UDim2.new(0, 440, 0, 44)
	contenedorJefe.Position = UDim2.new(0.5, -220, 0, 74)
	contenedorJefe.BackgroundColor3 = Color3.fromRGB(18, 10, 26)
	contenedorJefe.BackgroundTransparency = 0.18
	contenedorJefe.BorderSizePixel = 0
	contenedorJefe.Visible = false
	contenedorJefe.ZIndex = 38
	contenedorJefe.Parent = gui
	HUDController.ContenedorVidaJefe = contenedorJefe

	local cornerJefe = Instance.new("UICorner")
	cornerJefe.CornerRadius = UDim.new(0, 8)
	cornerJefe.Parent = contenedorJefe

	local strokeJefe = Instance.new("UIStroke")
	strokeJefe.Color = Color3.fromRGB(220, 45, 80)
	strokeJefe.Thickness = 1.6
	strokeJefe.Parent = contenedorJefe

	local txtNombreJefe = Instance.new("TextLabel")
	txtNombreJefe.Name = "TextoNombreJefe"
	txtNombreJefe.Size = UDim2.new(1, -16, 0, 18)
	txtNombreJefe.Position = UDim2.new(0, 8, 0, 3)
	txtNombreJefe.BackgroundTransparency = 1
	txtNombreJefe.TextColor3 = Color3.fromRGB(255, 195, 210)
	txtNombreJefe.Font = Enum.Font.GothamBlack
	txtNombreJefe.TextSize = 12
	txtNombreJefe.Text = "HERALDO DEL VACÍO"
	txtNombreJefe.ZIndex = 39
	txtNombreJefe.Parent = contenedorJefe
	HUDController.TextoNombreJefe = txtNombreJefe

	local fondoBarraJefe = Instance.new("Frame")
	fondoBarraJefe.Name = "FondoBarraJefe"
	fondoBarraJefe.Size = UDim2.new(1, -16, 0, 16)
	fondoBarraJefe.Position = UDim2.new(0, 8, 0, 23)
	fondoBarraJefe.BackgroundColor3 = Color3.fromRGB(35, 16, 42)
	fondoBarraJefe.BorderSizePixel = 0
	fondoBarraJefe.ZIndex = 39
	fondoBarraJefe.Parent = contenedorJefe

	local cornerFondoJefe = Instance.new("UICorner")
	cornerFondoJefe.CornerRadius = UDim.new(0, 5)
	cornerFondoJefe.Parent = fondoBarraJefe

	local barraJefe = Instance.new("Frame")
	barraJefe.Name = "BarraVidaJefe"
	barraJefe.Size = UDim2.new(1, 0, 1, 0)
	barraJefe.BackgroundColor3 = Color3.fromRGB(205, 35, 75)
	barraJefe.BorderSizePixel = 0
	barraJefe.ZIndex = 40
	barraJefe.Parent = fondoBarraJefe
	HUDController.BarraVidaJefe = barraJefe

	local cornerBarraJefe = Instance.new("UICorner")
	cornerBarraJefe.CornerRadius = UDim.new(0, 5)
	cornerBarraJefe.Parent = barraJefe

	local txtVidaJefe = Instance.new("TextLabel")
	txtVidaJefe.Name = "TextoVidaJefe"
	txtVidaJefe.Size = UDim2.new(1, 0, 1, 0)
	txtVidaJefe.BackgroundTransparency = 1
	txtVidaJefe.TextColor3 = Color3.fromRGB(255, 255, 255)
	txtVidaJefe.Font = Enum.Font.GothamBold
	txtVidaJefe.TextSize = 11
	txtVidaJefe.Text = "3500 / 3500"
	txtVidaJefe.ZIndex = 41
	txtVidaJefe.Parent = fondoBarraJefe
	HUDController.TextoVidaJefe = txtVidaJefe

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

	-- 4.1 Barra de Experiencia y Nivel (SOLO para Expedición)
	local contenedorXP = Instance.new("Frame")
	contenedorXP.Name = "ContenedorXP"
	contenedorXP.Size = UDim2.new(0, 380, 0, 20)
	contenedorXP.Position = UDim2.new(0.5, -190, 1, -34)
	contenedorXP.BackgroundColor3 = Color3.fromRGB(16, 12, 24)
	contenedorXP.BackgroundTransparency = 0.2
	contenedorXP.BorderSizePixel = 0
	contenedorXP.Visible = not esLobby
	contenedorXP.Parent = gui
	HUDController.ContenedorXP = contenedorXP

	local cornerXP = Instance.new("UICorner")
	cornerXP.CornerRadius = UDim.new(0, 6)
	cornerXP.Parent = contenedorXP

	local strokeXP = Instance.new("UIStroke")
	strokeXP.Color = Color3.fromRGB(80, 150, 230)
	strokeXP.Thickness = 1.2
	strokeXP.Parent = contenedorXP

	local barraXP = Instance.new("Frame")
	barraXP.Name = "BarraXP"
	barraXP.Size = UDim2.new(0, 0, 1, 0)
	barraXP.BackgroundColor3 = Color3.fromRGB(70, 180, 255)
	barraXP.BorderSizePixel = 0
	barraXP.Parent = contenedorXP
	HUDController.BarraXP = barraXP

	local cornerBarraXP = Instance.new("UICorner")
	cornerBarraXP.CornerRadius = UDim.new(0, 6)
	cornerBarraXP.Parent = barraXP

	local txtNivel = Instance.new("TextLabel")
	txtNivel.Name = "TextoNivel"
	txtNivel.Size = UDim2.new(0, 74, 1, 0)
	txtNivel.Position = UDim2.new(0, 8, 0, 0)
	txtNivel.BackgroundTransparency = 1
	txtNivel.TextXAlignment = Enum.TextXAlignment.Left
	txtNivel.TextColor3 = Color3.fromRGB(255, 225, 110)
	txtNivel.Font = Enum.Font.GothamBlack
	txtNivel.TextSize = 11
	txtNivel.Text = "NV. 1"
	txtNivel.ZIndex = 3
	txtNivel.Parent = contenedorXP
	HUDController.TextoNivel = txtNivel

	local txtXP = Instance.new("TextLabel")
	txtXP.Name = "TextoXP"
	txtXP.Size = UDim2.new(1, -16, 1, 0)
	txtXP.Position = UDim2.new(0, 8, 0, 0)
	txtXP.BackgroundTransparency = 1
	txtXP.TextXAlignment = Enum.TextXAlignment.Right
	txtXP.TextColor3 = Color3.fromRGB(235, 245, 255)
	txtXP.Font = Enum.Font.GothamBold
	txtXP.TextSize = 11
	txtXP.Text = "0 / 25 XP"
	txtXP.ZIndex = 3
	txtXP.Parent = contenedorXP
	HUDController.TextoXP = txtXP

	-- 4.2 Panel de Selección de Mejoras al Subir de Nivel (no pausa el juego ni bloquea movimiento)
	local panelMejoras = Instance.new("Frame")
	panelMejoras.Name = "PanelMejorasNivel"
	panelMejoras.Size = UDim2.new(0, 636, 0, 152)
	panelMejoras.Position = UDim2.new(0.5, -318, 0, 126)
	panelMejoras.BackgroundColor3 = Color3.fromRGB(14, 10, 22)
	panelMejoras.BackgroundTransparency = 0.22
	panelMejoras.BorderSizePixel = 0
	panelMejoras.Visible = false
	panelMejoras.ZIndex = 42
	panelMejoras.Parent = gui
	HUDController.PanelMejorasNivel = panelMejoras

	local cornerMejoras = Instance.new("UICorner")
	cornerMejoras.CornerRadius = UDim.new(0, 10)
	cornerMejoras.Parent = panelMejoras

	local strokeMejoras = Instance.new("UIStroke")
	strokeMejoras.Color = Color3.fromRGB(240, 200, 80)
	strokeMejoras.Thickness = 1.5
	strokeMejoras.Parent = panelMejoras

	local tituloMejoras = Instance.new("TextLabel")
	tituloMejoras.Name = "TituloMejoras"
	tituloMejoras.Size = UDim2.new(1, 0, 0, 24)
	tituloMejoras.Position = UDim2.new(0, 0, 0, 4)
	tituloMejoras.BackgroundTransparency = 1
	tituloMejoras.TextColor3 = Color3.fromRGB(255, 225, 110)
	tituloMejoras.Font = Enum.Font.GothamBlack
	tituloMejoras.TextSize = 13
	tituloMejoras.Text = "¡SUBISTE DE NIVEL! ELIGE UNA MEJORA"
	tituloMejoras.ZIndex = 43
	tituloMejoras.Parent = panelMejoras

	HUDController.TarjetasMejora = {}
	for i = 1, 3 do
		local tarjeta = Instance.new("TextButton")
		tarjeta.Name = string.format("TarjetaMejora_%d", i)
		tarjeta.Size = UDim2.new(0, 198, 0, 112)
		tarjeta.Position = UDim2.new(0, 12 + (i - 1) * 207, 0, 30)
		tarjeta.BackgroundColor3 = Color3.fromRGB(26, 20, 42)
		tarjeta.AutoButtonColor = true
		tarjeta.Text = ""
		tarjeta.BorderSizePixel = 0
		tarjeta.ZIndex = 43
		tarjeta.Parent = panelMejoras

		local cornerT = Instance.new("UICorner")
		cornerT.CornerRadius = UDim.new(0, 8)
		cornerT.Parent = tarjeta

		local strokeT = Instance.new("UIStroke")
		strokeT.Color = Color3.fromRGB(120, 80, 210)
		strokeT.Thickness = 1.2
		strokeT.Parent = tarjeta

		local lblTipo = Instance.new("TextLabel")
		lblTipo.Name = "Tipo"
		lblTipo.Size = UDim2.new(1, -12, 0, 16)
		lblTipo.Position = UDim2.new(0, 6, 0, 5)
		lblTipo.BackgroundTransparency = 1
		lblTipo.TextXAlignment = Enum.TextXAlignment.Left
		lblTipo.TextColor3 = Color3.fromRGB(110, 225, 255)
		lblTipo.Font = Enum.Font.GothamBold
		lblTipo.TextSize = 10
		lblTipo.Text = "MEJORA"
		lblTipo.ZIndex = 44
		lblTipo.Parent = tarjeta

		local lblNivel = Instance.new("TextLabel")
		lblNivel.Name = "Nivel"
		lblNivel.Size = UDim2.new(1, -12, 0, 16)
		lblNivel.Position = UDim2.new(0, 6, 0, 5)
		lblNivel.BackgroundTransparency = 1
		lblNivel.TextXAlignment = Enum.TextXAlignment.Right
		lblNivel.TextColor3 = Color3.fromRGB(255, 215, 90)
		lblNivel.Font = Enum.Font.GothamBlack
		lblNivel.TextSize = 10
		lblNivel.Text = "Nv. 1"
		lblNivel.ZIndex = 44
		lblNivel.Parent = tarjeta

		local lblTitulo = Instance.new("TextLabel")
		lblTitulo.Name = "Titulo"
		lblTitulo.Size = UDim2.new(1, -12, 0, 24)
		lblTitulo.Position = UDim2.new(0, 6, 0, 22)
		lblTitulo.BackgroundTransparency = 1
		lblTitulo.TextXAlignment = Enum.TextXAlignment.Left
		lblTitulo.TextWrapped = true
		lblTitulo.TextColor3 = Color3.fromRGB(255, 255, 255)
		lblTitulo.Font = Enum.Font.GothamBlack
		lblTitulo.TextSize = 12
		lblTitulo.Text = "Mejora"
		lblTitulo.ZIndex = 44
		lblTitulo.Parent = tarjeta

		local lblDesc = Instance.new("TextLabel")
		lblDesc.Name = "Descripcion"
		lblDesc.Size = UDim2.new(1, -12, 0, 58)
		lblDesc.Position = UDim2.new(0, 6, 0, 48)
		lblDesc.BackgroundTransparency = 1
		lblDesc.TextXAlignment = Enum.TextXAlignment.Left
		lblDesc.TextYAlignment = Enum.TextYAlignment.Top
		lblDesc.TextWrapped = true
		lblDesc.TextColor3 = Color3.fromRGB(195, 190, 215)
		lblDesc.Font = Enum.Font.Gotham
		lblDesc.TextSize = 11
		lblDesc.Text = ""
		lblDesc.ZIndex = 44
		lblDesc.Parent = tarjeta

		local registroTarjeta = {
			Boton = tarjeta,
			Tipo = lblTipo,
			Titulo = lblTitulo,
			Nivel = lblNivel,
			Descripcion = lblDesc,
			IdOpcionActual = nil :: string?,
		}
		table.insert(HUDController.TarjetasMejora, registroTarjeta)

		tarjeta.MouseButton1Click:Connect(function()
			if not registroTarjeta.IdOpcionActual then return end
			local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
			local remoteSel = if remotesFolder then remotesFolder:FindFirstChild("SeleccionarMejoraNivel") :: RemoteEvent? else nil
			if remoteSel then
				remoteSel:FireServer(registroTarjeta.IdOpcionActual)
			end
		end)
	end

	-- 4.3 Contenedor de 6 Ranuras de Magia (Sección 11, sobre barra de vida/XP)
	local contenedorMagias = Instance.new("Frame")
	contenedorMagias.Name = "ContenedorRanurasMagia"
	contenedorMagias.Size = UDim2.new(0, 486, 0, 52)
	contenedorMagias.Position = UDim2.new(0.5, -243, 1, -124)
	contenedorMagias.BackgroundColor3 = Color3.fromRGB(14, 10, 22)
	contenedorMagias.BackgroundTransparency = 0.35
	contenedorMagias.BorderSizePixel = 0
	contenedorMagias.Visible = not esLobby
	contenedorMagias.Parent = gui
	HUDController.ContenedorRanurasMagia = contenedorMagias

	local cornerContMagias = Instance.new("UICorner")
	cornerContMagias.CornerRadius = UDim.new(0, 8)
	cornerContMagias.Parent = contenedorMagias

	HUDController.RanurasMagiaHUD = {}
	for i = 1, 6 do
		local slot = Instance.new("Frame")
		slot.Name = string.format("RanuraMagia_%d", i)
		slot.Size = UDim2.new(0, 74, 0, 44)
		slot.Position = UDim2.new(0, 6 + (i - 1) * 80, 0, 4)
		slot.BackgroundColor3 = Color3.fromRGB(22, 17, 34)
		slot.BackgroundTransparency = 0.15
		slot.BorderSizePixel = 0
		slot.Parent = contenedorMagias

		local cornerSlot = Instance.new("UICorner")
		cornerSlot.CornerRadius = UDim.new(0, 6)
		cornerSlot.Parent = slot

		local strokeSlot = Instance.new("UIStroke")
		strokeSlot.Color = Color3.fromRGB(70, 60, 95)
		strokeSlot.Thickness = 1.2
		strokeSlot.Parent = slot

		local lblNum = Instance.new("TextLabel")
		lblNum.Name = "Numero"
		lblNum.Size = UDim2.new(0, 16, 0, 14)
		lblNum.Position = UDim2.new(0, 3, 0, 2)
		lblNum.BackgroundTransparency = 1
		lblNum.TextXAlignment = Enum.TextXAlignment.Left
		lblNum.TextColor3 = Color3.fromRGB(150, 145, 175)
		lblNum.Font = Enum.Font.GothamBold
		lblNum.TextSize = 9
		lblNum.Text = tostring(i)
		lblNum.Parent = slot

		local lblNombre = Instance.new("TextLabel")
		lblNombre.Name = "Nombre"
		lblNombre.Size = UDim2.new(1, -6, 0, 22)
		lblNombre.Position = UDim2.new(0, 3, 0, 11)
		lblNombre.BackgroundTransparency = 1
		lblNombre.TextWrapped = true
		lblNombre.TextColor3 = Color3.fromRGB(130, 125, 150)
		lblNombre.Font = Enum.Font.GothamBold
		lblNombre.TextSize = 9
		lblNombre.Text = "[VACÍO]"
		lblNombre.Parent = slot

		local lblNivel = Instance.new("TextLabel")
		lblNivel.Name = "Nivel"
		lblNivel.Size = UDim2.new(1, -6, 0, 12)
		lblNivel.Position = UDim2.new(0, 3, 1, -13)
		lblNivel.BackgroundTransparency = 1
		lblNivel.TextColor3 = Color3.fromRGB(240, 210, 90)
		lblNivel.Font = Enum.Font.GothamBlack
		lblNivel.TextSize = 9
		lblNivel.Text = ""
		lblNivel.Parent = slot

		table.insert(HUDController.RanurasMagiaHUD, {
			Marco = slot,
			Borde = strokeSlot,
			Numero = lblNum,
			Nombre = lblNombre,
			Nivel = lblNivel,
		})
	end

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

	-- 5.1 Barra y Panel de Modo Espectador (Cooperativo - Sección 12)
	local contenedorEsp = Instance.new("Frame")
	contenedorEsp.Name = "ContenedorEspectador"
	contenedorEsp.Size = UDim2.new(0, 560, 0, 206)
	contenedorEsp.Position = UDim2.new(0.5, -280, 1, -220)
	contenedorEsp.BackgroundColor3 = Color3.fromRGB(15, 10, 22)
	contenedorEsp.BackgroundTransparency = 0.14
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
	btnAnt.Size = UDim2.new(0, 34, 0, 32)
	btnAnt.Position = UDim2.new(0, 12, 0, 28)
	btnAnt.BackgroundColor3 = Color3.fromRGB(30, 20, 45)
	btnAnt.TextColor3 = Color3.fromRGB(240, 240, 255)
	btnAnt.Font = Enum.Font.GothamBlack
	btnAnt.TextSize = 16
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
	txtNombreEsp.Size = UDim2.new(0, 178, 0, 32)
	txtNombreEsp.Position = UDim2.new(0, 50, 0, 28)
	txtNombreEsp.BackgroundColor3 = Color3.fromRGB(22, 14, 32)
	txtNombreEsp.BackgroundTransparency = 0.4
	txtNombreEsp.TextColor3 = Color3.fromRGB(255, 255, 255)
	txtNombreEsp.Font = Enum.Font.GothamBold
	txtNombreEsp.TextSize = 13
	txtNombreEsp.Text = "Buscando..."
	txtNombreEsp.ZIndex = 41
	txtNombreEsp.Parent = contenedorEsp
	local cornerTxt = Instance.new("UICorner")
	cornerTxt.CornerRadius = UDim.new(0, 6)
	cornerTxt.Parent = txtNombreEsp
	HUDController.TextoEspectadorNombre = txtNombreEsp

	local txtNivelEsp = Instance.new("TextLabel")
	txtNivelEsp.Name = "TextoNivelEspectador"
	txtNivelEsp.Size = UDim2.new(0, 62, 0, 32)
	txtNivelEsp.Position = UDim2.new(0, 232, 0, 28)
	txtNivelEsp.BackgroundColor3 = Color3.fromRGB(28, 18, 42)
	txtNivelEsp.BackgroundTransparency = 0.3
	txtNivelEsp.TextColor3 = Color3.fromRGB(255, 220, 95)
	txtNivelEsp.Font = Enum.Font.GothamBlack
	txtNivelEsp.TextSize = 12
	txtNivelEsp.Text = "Nv. 1"
	txtNivelEsp.ZIndex = 41
	txtNivelEsp.Parent = contenedorEsp
	local cornerNivEsp = Instance.new("UICorner")
	cornerNivEsp.CornerRadius = UDim.new(0, 6)
	cornerNivEsp.Parent = txtNivelEsp
	HUDController.TextoNivelEspectador = txtNivelEsp

	local btnSig = Instance.new("TextButton")
	btnSig.Name = "BotonSiguiente"
	btnSig.Size = UDim2.new(0, 34, 0, 32)
	btnSig.Position = UDim2.new(0, 298, 0, 28)
	btnSig.BackgroundColor3 = Color3.fromRGB(30, 20, 45)
	btnSig.TextColor3 = Color3.fromRGB(240, 240, 255)
	btnSig.Font = Enum.Font.GothamBlack
	btnSig.TextSize = 16
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
	btnSalir.Size = UDim2.new(0, 204, 0, 32)
	btnSalir.Position = UDim2.new(1, -216, 0, 28)
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
		HUDController.AbrirConfirmacionSalida()
	end)

	-- Barra de vida en tiempo real del compañero observado
	local fondoVidaEsp = Instance.new("Frame")
	fondoVidaEsp.Name = "FondoVidaEspectador"
	fondoVidaEsp.Size = UDim2.new(1, -24, 0, 18)
	fondoVidaEsp.Position = UDim2.new(0, 12, 0, 66)
	fondoVidaEsp.BackgroundColor3 = Color3.fromRGB(26, 16, 36)
	fondoVidaEsp.BorderSizePixel = 0
	fondoVidaEsp.ZIndex = 41
	fondoVidaEsp.Parent = contenedorEsp
	local cornerVidaEsp = Instance.new("UICorner")
	cornerVidaEsp.CornerRadius = UDim.new(0, 5)
	cornerVidaEsp.Parent = fondoVidaEsp

	local barraVidaEsp = Instance.new("Frame")
	barraVidaEsp.Name = "BarraVidaEspectador"
	barraVidaEsp.Size = UDim2.new(1, 0, 1, 0)
	barraVidaEsp.BackgroundColor3 = Color3.fromRGB(220, 45, 70)
	barraVidaEsp.BorderSizePixel = 0
	barraVidaEsp.ZIndex = 42
	barraVidaEsp.Parent = fondoVidaEsp
	HUDController.BarraVidaEspectador = barraVidaEsp
	local cornerBarraEsp = Instance.new("UICorner")
	cornerBarraEsp.CornerRadius = UDim.new(0, 5)
	cornerBarraEsp.Parent = barraVidaEsp

	local txtVidaEsp = Instance.new("TextLabel")
	txtVidaEsp.Name = "TextoVidaEspectador"
	txtVidaEsp.Size = UDim2.new(1, 0, 1, 0)
	txtVidaEsp.BackgroundTransparency = 1
	txtVidaEsp.TextColor3 = Color3.fromRGB(255, 255, 255)
	txtVidaEsp.Font = Enum.Font.GothamBold
	txtVidaEsp.TextSize = 11
	txtVidaEsp.Text = "100 / 100"
	txtVidaEsp.ZIndex = 43
	txtVidaEsp.Parent = fondoVidaEsp
	HUDController.TextoVidaEspectador = txtVidaEsp

	-- Lista del equipo completo (vivos seleccionables / eliminados no seleccionables)
	HUDController.FilasEquipoEspectador = {}
	for i = 1, 4 do
		local filaBtn = Instance.new("TextButton")
		filaBtn.Name = string.format("MiembroEquipo_%d", i)
		filaBtn.Size = UDim2.new(1, -24, 0, 24)
		filaBtn.Position = UDim2.new(0, 12, 0, 90 + (i - 1) * 27)
		filaBtn.BackgroundColor3 = Color3.fromRGB(24, 18, 36)
		filaBtn.AutoButtonColor = false
		filaBtn.Text = ""
		filaBtn.Visible = false
		filaBtn.ZIndex = 41
		filaBtn.Parent = contenedorEsp

		local cornerF = Instance.new("UICorner")
		cornerF.CornerRadius = UDim.new(0, 5)
		cornerF.Parent = filaBtn

		local lblNom = Instance.new("TextLabel")
		lblNom.Size = UDim2.new(0.65, -8, 1, 0)
		lblNom.Position = UDim2.new(0, 8, 0, 0)
		lblNom.BackgroundTransparency = 1
		lblNom.TextXAlignment = Enum.TextXAlignment.Left
		lblNom.TextColor3 = Color3.fromRGB(235, 235, 250)
		lblNom.Font = Enum.Font.GothamBold
		lblNom.TextSize = 11
		lblNom.Text = ""
		lblNom.ZIndex = 42
		lblNom.Parent = filaBtn

		local lblEst = Instance.new("TextLabel")
		lblEst.Size = UDim2.new(0.35, -8, 1, 0)
		lblEst.Position = UDim2.new(0.65, 0, 0, 0)
		lblEst.BackgroundTransparency = 1
		lblEst.TextXAlignment = Enum.TextXAlignment.Right
		lblEst.TextColor3 = Color3.fromRGB(110, 240, 150)
		lblEst.Font = Enum.Font.GothamBlack
		lblEst.TextSize = 10
		lblEst.Text = ""
		lblEst.ZIndex = 42
		lblEst.Parent = filaBtn

		local registroFila = {
			Boton = filaBtn,
			Nombre = lblNom,
			Estado = lblEst,
			UserIdActual = nil :: number?,
		}
		table.insert(HUDController.FilasEquipoEspectador, registroFila)

		filaBtn.MouseButton1Click:Connect(function()
			if not registroFila.UserIdActual then return end
			for idx, vivo in HUDController.SupervivientesVivos do
				if vivo.UserId == registroFila.UserIdActual then
					HUDController.IndiceEspectador = idx
					HUDController.CambiarObjetivoEspectador(0)
					break
				end
			end
		end)
	end

	-- 5.2 Indicadores de Compañeros en Cooperativo (esquina superior izquierda, lejos del joystick móvil)
	if not esLobby then
		local contComp = Instance.new("Frame")
		contComp.Name = "ContenedorCompanieros"
		contComp.Size = UDim2.new(0, 196, 0, 190)
		contComp.Position = UDim2.new(0, 14, 0, 82)
		contComp.BackgroundTransparency = 1
		contComp.Visible = false
		contComp.ZIndex = 35
		contComp.Parent = gui
		HUDController.ContenedorCompanieros = contComp

		HUDController.TarjetasCompanieros = {}
		for i = 1, 4 do
			local card = Instance.new("Frame")
			card.Name = string.format("Companiero_%d", i)
			card.Size = UDim2.new(1, 0, 0, 42)
			card.Position = UDim2.new(0, 0, 0, (i - 1) * 46)
			card.BackgroundColor3 = Color3.fromRGB(16, 12, 24)
			card.BackgroundTransparency = 0.25
			card.BorderSizePixel = 0
			card.Visible = false
			card.ZIndex = 36
			card.Parent = contComp

			local cornerC = Instance.new("UICorner")
			cornerC.CornerRadius = UDim.new(0, 6)
			cornerC.Parent = card

			local lblNom = Instance.new("TextLabel")
			lblNom.Size = UDim2.new(0.66, -6, 0, 18)
			lblNom.Position = UDim2.new(0, 6, 0, 2)
			lblNom.BackgroundTransparency = 1
			lblNom.TextXAlignment = Enum.TextXAlignment.Left
			lblNom.TextColor3 = Color3.fromRGB(240, 240, 255)
			lblNom.Font = Enum.Font.GothamBold
			lblNom.TextSize = 11
			lblNom.Text = ""
			lblNom.ZIndex = 37
			lblNom.Parent = card

			local lblEst = Instance.new("TextLabel")
			lblEst.Size = UDim2.new(0.34, -6, 0, 18)
			lblEst.Position = UDim2.new(0.66, 0, 0, 2)
			lblEst.BackgroundTransparency = 1
			lblEst.TextXAlignment = Enum.TextXAlignment.Right
			lblEst.TextColor3 = Color3.fromRGB(110, 240, 150)
			lblEst.Font = Enum.Font.GothamBlack
			lblEst.TextSize = 9
			lblEst.Text = "VIVO"
			lblEst.ZIndex = 37
			lblEst.Parent = card

			local fondoV = Instance.new("Frame")
			fondoV.Size = UDim2.new(1, -12, 0, 8)
			fondoV.Position = UDim2.new(0, 6, 0, 26)
			fondoV.BackgroundColor3 = Color3.fromRGB(30, 20, 42)
			fondoV.BorderSizePixel = 0
			fondoV.ZIndex = 37
			fondoV.Parent = card
			local cornerFV = Instance.new("UICorner")
			cornerFV.CornerRadius = UDim.new(0, 4)
			cornerFV.Parent = fondoV

			local barraV = Instance.new("Frame")
			barraV.Size = UDim2.new(1, 0, 1, 0)
			barraV.BackgroundColor3 = Color3.fromRGB(220, 50, 75)
			barraV.BorderSizePixel = 0
			barraV.ZIndex = 38
			barraV.Parent = fondoV
			local cornerBV = Instance.new("UICorner")
			cornerBV.CornerRadius = UDim.new(0, 4)
			cornerBV.Parent = barraV

			table.insert(HUDController.TarjetasCompanieros, {
				Marco = card,
				Nombre = lblNom,
				BarraVida = barraV,
				Estado = lblEst,
			})
		end

		-- 5.3 Pantalla de Transición de Fin de Partida (3 segundos con logotipo UMBRA)
		local pantallaTrans = Instance.new("Frame")
		pantallaTrans.Name = "PantallaTransicionFin"
		pantallaTrans.Size = UDim2.new(1, 0, 1, 0)
		pantallaTrans.BackgroundColor3 = Color3.fromRGB(6, 4, 12)
		pantallaTrans.BackgroundTransparency = 0.08
		pantallaTrans.BorderSizePixel = 0
		pantallaTrans.Visible = false
		pantallaTrans.ZIndex = 60
		pantallaTrans.Parent = gui
		HUDController.PantallaTransicionFin = pantallaTrans

		local logoTrans = Instance.new("TextLabel")
		logoTrans.Size = UDim2.new(1, -40, 0, 40)
		logoTrans.Position = UDim2.new(0, 20, 0.4, -30)
		logoTrans.BackgroundTransparency = 1
		logoTrans.TextColor3 = Color3.fromRGB(210, 185, 255)
		logoTrans.Font = Enum.Font.GothamBlack
		logoTrans.TextSize = 24
		logoTrans.Text = "UMBRA: LA ÚLTIMA LUZ"
		logoTrans.ZIndex = 61
		logoTrans.Parent = pantallaTrans

		local resTrans = Instance.new("TextLabel")
		resTrans.Name = "TextoTransicionResultado"
		resTrans.Size = UDim2.new(1, -40, 0, 60)
		resTrans.Position = UDim2.new(0, 20, 0.4, 18)
		resTrans.BackgroundTransparency = 1
		resTrans.TextColor3 = Color3.fromRGB(255, 210, 80)
		resTrans.Font = Enum.Font.GothamBlack
		resTrans.TextSize = 44
		resTrans.Text = "VICTORIA"
		resTrans.ZIndex = 61
		resTrans.Parent = pantallaTrans
		HUDController.TextoTransicionResultado = resTrans

		-- 5.4 Pantalla de Resultados Individual (3 Secciones - Sección 14)
		local panelRes = Instance.new("Frame")
		panelRes.Name = "PanelResultados"
		panelRes.Size = UDim2.new(0, 580, 0, 380)
		panelRes.Position = UDim2.new(0.5, -290, 0.5, -190)
		panelRes.BackgroundColor3 = Color3.fromRGB(16, 12, 26)
		panelRes.BackgroundTransparency = 0.08
		panelRes.BorderSizePixel = 0
		panelRes.Visible = false
		panelRes.ZIndex = 65
		panelRes.Parent = gui
		HUDController.PanelResultados = panelRes

		local cornerRes = Instance.new("UICorner")
		cornerRes.CornerRadius = UDim.new(0, 14)
		cornerRes.Parent = panelRes

		local strokeRes = Instance.new("UIStroke")
		strokeRes.Color = Color3.fromRGB(150, 80, 240)
		strokeRes.Thickness = 2
		strokeRes.Parent = panelRes

		local tituloRes = Instance.new("TextLabel")
		tituloRes.Size = UDim2.new(1, 0, 0, 34)
		tituloRes.Position = UDim2.new(0, 0, 0, 10)
		tituloRes.BackgroundTransparency = 1
		tituloRes.TextColor3 = Color3.fromRGB(255, 220, 100)
		tituloRes.Font = Enum.Font.GothamBlack
		tituloRes.TextSize = 18
		tituloRes.Text = "RESULTADOS DE EXPEDICIÓN"
		tituloRes.ZIndex = 66
		tituloRes.Parent = panelRes

		local nombresTabs = { "1. Resumen", "2. Combate", "3. Recompensas" }
		HUDController.BotonesTabResultados = {}
		HUDController.SeccionesResultados = {}

		for idx, nombreTab in nombresTabs do
			local btnTab = Instance.new("TextButton")
			btnTab.Size = UDim2.new(0, 174, 0, 30)
			btnTab.Position = UDim2.new(0, 18 + (idx - 1) * 184, 0, 48)
			btnTab.BackgroundColor3 = if idx == 1 then Color3.fromRGB(90, 50, 170) else Color3.fromRGB(28, 22, 44)
			btnTab.TextColor3 = Color3.fromRGB(255, 255, 255)
			btnTab.Font = Enum.Font.GothamBold
			btnTab.TextSize = 12
			btnTab.Text = nombreTab
			btnTab.ZIndex = 66
			btnTab.Parent = panelRes

			local cornerTab = Instance.new("UICorner")
			cornerTab.CornerRadius = UDim.new(0, 6)
			cornerTab.Parent = btnTab
			table.insert(HUDController.BotonesTabResultados, btnTab)

			local secFrame = Instance.new("Frame")
			secFrame.Name = "Seccion_" .. tostring(idx)
			secFrame.Size = UDim2.new(1, -36, 0, 228)
			secFrame.Position = UDim2.new(0, 18, 0, 86)
			secFrame.BackgroundColor3 = Color3.fromRGB(22, 16, 36)
			secFrame.BackgroundTransparency = 0.25
			secFrame.BorderSizePixel = 0
			secFrame.Visible = (idx == 1)
			secFrame.ZIndex = 66
			secFrame.Parent = panelRes

			local cornerSec = Instance.new("UICorner")
			cornerSec.CornerRadius = UDim.new(0, 8)
			cornerSec.Parent = secFrame
			table.insert(HUDController.SeccionesResultados, secFrame)

			btnTab.MouseButton1Click:Connect(function()
				HUDController.CambiarTabResultados(idx)
			end)
		end

		-- Contenido Sección 1: Resumen de Expedición
		local sec1 = HUDController.SeccionesResultados[1]
		local camposResumen = {
			{ Id = "Resultado", Etiqueta = "Resultado final:" },
			{ Id = "Tiempo", Etiqueta = "Tiempo sobrevivido:" },
			{ Id = "Nivel", Etiqueta = "Nivel alcanzado:" },
			{ Id = "Enemigos", Etiqueta = "Enemigos derrotados:" },
			{ Id = "Jefes", Etiqueta = "Jefes derrotados:" },
			{ Id = "Botin", Etiqueta = "Oro / Gemas (Provisional):" },
		}
		HUDController.TextosResumen = {}
		for i, campo in camposResumen do
			local lblIzq = Instance.new("TextLabel")
			lblIzq.Size = UDim2.new(0.55, -16, 0, 28)
			lblIzq.Position = UDim2.new(0, 14, 0, 12 + (i - 1) * 34)
			lblIzq.BackgroundTransparency = 1
			lblIzq.TextXAlignment = Enum.TextXAlignment.Left
			lblIzq.TextColor3 = Color3.fromRGB(190, 185, 215)
			lblIzq.Font = Enum.Font.GothamMedium
			lblIzq.TextSize = 13
			lblIzq.Text = campo.Etiqueta
			lblIzq.ZIndex = 67
			lblIzq.Parent = sec1

			local lblDer = Instance.new("TextLabel")
			lblDer.Size = UDim2.new(0.45, -16, 0, 28)
			lblDer.Position = UDim2.new(0.55, 0, 0, 12 + (i - 1) * 34)
			lblDer.BackgroundTransparency = 1
			lblDer.TextXAlignment = Enum.TextXAlignment.Right
			lblDer.TextColor3 = Color3.fromRGB(255, 255, 255)
			lblDer.Font = Enum.Font.GothamBlack
			lblDer.TextSize = 13
			lblDer.Text = "--"
			lblDer.ZIndex = 67
			lblDer.Parent = sec1
			HUDController.TextosResumen[campo.Id] = lblDer
		end

		-- Contenido Sección 2: Rendimiento de Combate (sin daño recibido ni comparación entre jugadores)
		local sec2 = HUDController.SeccionesResultados[2]
		local lblDanioTot = Instance.new("TextLabel")
		lblDanioTot.Size = UDim2.new(1, -24, 0, 28)
		lblDanioTot.Position = UDim2.new(0, 12, 0, 8)
		lblDanioTot.BackgroundTransparency = 1
		lblDanioTot.TextXAlignment = Enum.TextXAlignment.Left
		lblDanioTot.TextColor3 = Color3.fromRGB(255, 210, 100)
		lblDanioTot.Font = Enum.Font.GothamBlack
		lblDanioTot.TextSize = 14
		lblDanioTot.Text = "Daño total causado: 0"
		lblDanioTot.ZIndex = 67
		lblDanioTot.Parent = sec2
		HUDController.TextoDanioTotalCombate = lblDanioTot

		local scrollMagias = Instance.new("ScrollingFrame")
		scrollMagias.Size = UDim2.new(1, -24, 1, -46)
		scrollMagias.Position = UDim2.new(0, 12, 0, 38)
		scrollMagias.BackgroundTransparency = 1
		scrollMagias.ScrollBarThickness = 4
		scrollMagias.CanvasSize = UDim2.new(0, 0, 0, 0)
		scrollMagias.ZIndex = 67
		scrollMagias.Parent = sec2
		HUDController.ListaMagiasCombate = scrollMagias

		-- Contenido Sección 3: Recompensas
		local sec3 = HUDController.SeccionesResultados[3]
		local lblOro = Instance.new("TextLabel")
		lblOro.Size = UDim2.new(1, -24, 0, 36)
		lblOro.Position = UDim2.new(0, 12, 0, 24)
		lblOro.BackgroundTransparency = 1
		lblOro.TextColor3 = Color3.fromRGB(255, 215, 80)
		lblOro.Font = Enum.Font.GothamBlack
		lblOro.TextSize = 20
		lblOro.Text = "Oro obtenido: 0"
		lblOro.ZIndex = 67
		lblOro.Parent = sec3

		local lblGemas = Instance.new("TextLabel")
		lblGemas.Size = UDim2.new(1, -24, 0, 36)
		lblGemas.Position = UDim2.new(0, 12, 0, 70)
		lblGemas.BackgroundTransparency = 1
		lblGemas.TextColor3 = Color3.fromRGB(110, 230, 255)
		lblGemas.Font = Enum.Font.GothamBlack
		lblGemas.TextSize = 20
		lblGemas.Text = "Gemas obtenidas: 0"
		lblGemas.ZIndex = 67
		lblGemas.Parent = sec3

		local lblAvisoAlpha = Instance.new("TextLabel")
		lblAvisoAlpha.Size = UDim2.new(1, -32, 0, 54)
		lblAvisoAlpha.Position = UDim2.new(0, 16, 0, 130)
		lblAvisoAlpha.BackgroundTransparency = 1
		lblAvisoAlpha.TextWrapped = true
		lblAvisoAlpha.TextColor3 = Color3.fromRGB(175, 170, 200)
		lblAvisoAlpha.Font = Enum.Font.Gotham
		lblAvisoAlpha.TextSize = 12
		lblAvisoAlpha.Text = "Aviso Alpha v1.0: Los valores de Oro y Gemas son provisionales mientras se define la fórmula económica definitiva (Sección 14)."
		lblAvisoAlpha.ZIndex = 67
		lblAvisoAlpha.Parent = sec3

		HUDController.TextosRecompensas = {
			Oro = lblOro,
			Gemas = lblGemas,
		}

		local btnVolverRes = Instance.new("TextButton")
		btnVolverRes.Name = "BotonRegresarResultados"
		btnVolverRes.Size = UDim2.new(0, 240, 0, 40)
		btnVolverRes.Position = UDim2.new(0.5, -120, 1, -52)
		btnVolverRes.BackgroundColor3 = Color3.fromRGB(160, 40, 65)
		btnVolverRes.TextColor3 = Color3.fromRGB(255, 255, 255)
		btnVolverRes.Font = Enum.Font.GothamBlack
		btnVolverRes.TextSize = 13
		btnVolverRes.Text = "REGRESAR AL LOBBY"
		btnVolverRes.ZIndex = 66
		btnVolverRes.Parent = panelRes
		local cornerBtnVolver = Instance.new("UICorner")
		cornerBtnVolver.CornerRadius = UDim.new(0, 8)
		cornerBtnVolver.Parent = btnVolverRes
		btnVolverRes.MouseButton1Click:Connect(function()
			HUDController.AbrirConfirmacionSalida()
		end)

		-- 5.5 Modal de Confirmación antes de regresar al Lobby
		local modalConf = Instance.new("Frame")
		modalConf.Name = "ModalConfirmacionSalida"
		modalConf.Size = UDim2.new(0, 360, 0, 150)
		modalConf.Position = UDim2.new(0.5, -180, 0.5, -75)
		modalConf.BackgroundColor3 = Color3.fromRGB(18, 12, 28)
		modalConf.BackgroundTransparency = 0.05
		modalConf.BorderSizePixel = 0
		modalConf.Visible = false
		modalConf.ZIndex = 80
		modalConf.Parent = gui
		HUDController.ModalConfirmacionSalida = modalConf

		local cornerConf = Instance.new("UICorner")
		cornerConf.CornerRadius = UDim.new(0, 12)
		cornerConf.Parent = modalConf

		local strokeConf = Instance.new("UIStroke")
		strokeConf.Color = Color3.fromRGB(240, 185, 70)
		strokeConf.Thickness = 1.6
		strokeConf.Parent = modalConf

		local lblConf = Instance.new("TextLabel")
		lblConf.Size = UDim2.new(1, -24, 0, 56)
		lblConf.Position = UDim2.new(0, 12, 0, 16)
		lblConf.BackgroundTransparency = 1
		lblConf.TextWrapped = true
		lblConf.TextColor3 = Color3.fromRGB(245, 240, 255)
		lblConf.Font = Enum.Font.GothamBold
		lblConf.TextSize = 15
		lblConf.Text = "¿Deseas regresar al Santuario?"
		lblConf.ZIndex = 81
		lblConf.Parent = modalConf

		local btnConfSi = Instance.new("TextButton")
		btnConfSi.Size = UDim2.new(0, 152, 0, 38)
		btnConfSi.Position = UDim2.new(0, 18, 1, -54)
		btnConfSi.BackgroundColor3 = Color3.fromRGB(170, 40, 65)
		btnConfSi.TextColor3 = Color3.fromRGB(255, 255, 255)
		btnConfSi.Font = Enum.Font.GothamBlack
		btnConfSi.TextSize = 12
		btnConfSi.Text = "CONFIRMAR SALIDA"
		btnConfSi.ZIndex = 81
		btnConfSi.Parent = modalConf
		local cornerCS = Instance.new("UICorner")
		cornerCS.CornerRadius = UDim.new(0, 8)
		cornerCS.Parent = btnConfSi

		btnConfSi.MouseButton1Click:Connect(function()
			modalConf.Visible = false
			if HUDController.BotonSalirLobby then
				HUDController.BotonSalirLobby.Text = "Teletransportando..."
				HUDController.BotonSalirLobby.Active = false
			end
			local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
			local remoteRetorno = if remotesFolder then remotesFolder:FindFirstChild("SolicitarRetornoIndividual") :: RemoteEvent? else nil
			if remoteRetorno then
				remoteRetorno:FireServer()
			end
		end)

		local btnConfNo = Instance.new("TextButton")
		btnConfNo.Size = UDim2.new(0, 152, 0, 38)
		btnConfNo.Position = UDim2.new(1, -170, 1, -54)
		btnConfNo.BackgroundColor3 = Color3.fromRGB(45, 38, 65)
		btnConfNo.TextColor3 = Color3.fromRGB(255, 255, 255)
		btnConfNo.Font = Enum.Font.GothamBold
		btnConfNo.TextSize = 12
		btnConfNo.Text = "CANCELAR"
		btnConfNo.ZIndex = 81
		btnConfNo.Parent = modalConf
		local cornerCN = Instance.new("UICorner")
		cornerCN.CornerRadius = UDim.new(0, 8)
		cornerCN.Parent = btnConfNo

		btnConfNo.MouseButton1Click:Connect(function()
			modalConf.Visible = false
		end)
	end

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

	-- 7. Panel de desarrollo [DEV] (solo jugadores autorizados en Expedición)
	if not esLobby and DevTestConfig.EsJugadorAutorizado(localPlayer) then
		local panelDev = Instance.new("Frame")
		panelDev.Name = "PanelDev"
		panelDev.Size = UDim2.new(0, 200, 0, 96)
		panelDev.Position = UDim2.new(1, -216, 0, 16)
		panelDev.BackgroundColor3 = Color3.fromRGB(16, 12, 24)
		panelDev.BackgroundTransparency = 0.2
		panelDev.BorderSizePixel = 0
		panelDev.ZIndex = 45
		panelDev.Parent = gui
		HUDController.PanelDev = panelDev

		local cornerDev = Instance.new("UICorner")
		cornerDev.CornerRadius = UDim.new(0, 8)
		cornerDev.Parent = panelDev

		local strokeDev = Instance.new("UIStroke")
		strokeDev.Color = Color3.fromRGB(240, 190, 60)
		strokeDev.Thickness = 1.2
		strokeDev.Parent = panelDev

		local tituloDev = Instance.new("TextLabel")
		tituloDev.Name = "TituloDev"
		tituloDev.Size = UDim2.new(1, 0, 0, 20)
		tituloDev.Position = UDim2.new(0, 0, 0, 4)
		tituloDev.BackgroundTransparency = 1
		tituloDev.TextColor3 = Color3.fromRGB(240, 200, 80)
		tituloDev.Font = Enum.Font.GothamBold
		tituloDev.TextSize = 11
		tituloDev.Text = "[DEV] CONTROL DE TIEMPO"
		tituloDev.ZIndex = 46
		tituloDev.Parent = panelDev

		local btnVel = Instance.new("TextButton")
		btnVel.Name = "BotonDevVelocidad"
		btnVel.Size = UDim2.new(1, -16, 0, 28)
		btnVel.Position = UDim2.new(0, 8, 0, 28)
		btnVel.BackgroundColor3 = Color3.fromRGB(45, 35, 70)
		btnVel.TextColor3 = Color3.fromRGB(255, 255, 255)
		btnVel.Font = Enum.Font.GothamBold
		btnVel.TextSize = 12
		btnVel.Text = "Vel: x1"
		btnVel.ZIndex = 46
		btnVel.Parent = panelDev
		HUDController.BotonDevVelocidad = btnVel

		local cornerVel = Instance.new("UICorner")
		cornerVel.CornerRadius = UDim.new(0, 6)
		cornerVel.Parent = btnVel

		btnVel.MouseButton1Click:Connect(function()
			local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
			local remoteDev = if remotesFolder then remotesFolder:FindFirstChild("ComandoDevExpedicion") :: RemoteEvent? else nil
			if remoteDev then
				remoteDev:FireServer("AlternarVelocidad")
			end
		end)

		local btnPreJefe = Instance.new("TextButton")
		btnPreJefe.Name = "BotonDevPreJefe"
		btnPreJefe.Size = UDim2.new(1, -16, 0, 28)
		btnPreJefe.Position = UDim2.new(0, 8, 0, 60)
		btnPreJefe.BackgroundColor3 = Color3.fromRGB(110, 45, 70)
		btnPreJefe.TextColor3 = Color3.fromRGB(255, 255, 255)
		btnPreJefe.Font = Enum.Font.GothamBold
		btnPreJefe.TextSize = 11
		btnPreJefe.Text = "Saltar a 29:50 (Pre-Jefe)"
		btnPreJefe.ZIndex = 46
		btnPreJefe.Parent = panelDev
		HUDController.BotonDevPreJefe = btnPreJefe

		local cornerPre = Instance.new("UICorner")
		cornerPre.CornerRadius = UDim.new(0, 6)
		cornerPre.Parent = btnPreJefe

		btnPreJefe.MouseButton1Click:Connect(function()
			local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
			local remoteDev = if remotesFolder then remotesFolder:FindFirstChild("ComandoDevExpedicion") :: RemoteEvent? else nil
			if remoteDev then
				remoteDev:FireServer("SaltarTiempo", DevTestConfig.HitosSaltoRapido.PreJefe)
			end
		end)
	end

	-- 8. Panel de acceso a expedición y Sala Cooperativa (SOLO en el Lobby)
	if esLobby then
		local function enviarAccionLobby(accion: TiposAlpha.AccionLobby)
			local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
			local remoteAccion = if remotesFolder then remotesFolder:FindFirstChild("AccionEmparejamientoLobby") :: RemoteEvent? else nil
			if remoteAccion then
				remoteAccion:FireServer(accion)
			end
		end

		-- Panel principal de acceso (siempre visible en el Lobby cuando no está en sala)
		local panelAcceso = Instance.new("Frame")
		panelAcceso.Name = "PanelAccesoLobby"
		panelAcceso.Size = UDim2.new(0, 460, 0, 114)
		panelAcceso.Position = UDim2.new(0.5, -230, 1, -134)
		panelAcceso.BackgroundColor3 = Color3.fromRGB(16, 12, 26)
		panelAcceso.BackgroundTransparency = 0.18
		panelAcceso.BorderSizePixel = 0
		panelAcceso.ZIndex = 30
		panelAcceso.Parent = gui
		HUDController.PanelAccesoLobby = panelAcceso

		local cornerAcceso = Instance.new("UICorner")
		cornerAcceso.CornerRadius = UDim.new(0, 12)
		cornerAcceso.Parent = panelAcceso

		local strokeAcceso = Instance.new("UIStroke")
		strokeAcceso.Color = Color3.fromRGB(130, 70, 230)
		strokeAcceso.Thickness = 1.5
		strokeAcceso.Parent = panelAcceso

		local tituloAcceso = Instance.new("TextLabel")
		tituloAcceso.Name = "TituloAcceso"
		tituloAcceso.Size = UDim2.new(1, 0, 0, 24)
		tituloAcceso.Position = UDim2.new(0, 0, 0, 6)
		tituloAcceso.BackgroundTransparency = 1
		tituloAcceso.TextColor3 = Color3.fromRGB(220, 200, 255)
		tituloAcceso.Font = Enum.Font.GothamBlack
		tituloAcceso.TextSize = 13
		tituloAcceso.Text = "SANTUARIO — ACCESO A EXPEDICIÓN"
		tituloAcceso.ZIndex = 31
		tituloAcceso.Parent = panelAcceso

		local btnSolo = Instance.new("TextButton")
		btnSolo.Name = "BotonIniciarIndividual"
		btnSolo.Size = UDim2.new(0.5, -18, 0, 42)
		btnSolo.Position = UDim2.new(0, 12, 0, 34)
		btnSolo.BackgroundColor3 = Color3.fromRGB(70, 45, 130)
		btnSolo.TextColor3 = Color3.fromRGB(255, 255, 255)
		btnSolo.Font = Enum.Font.GothamBold
		btnSolo.TextSize = 13
		btnSolo.Text = "Iniciar partida individual"
		btnSolo.ZIndex = 31
		btnSolo.Parent = panelAcceso

		local cornerSolo = Instance.new("UICorner")
		cornerSolo.CornerRadius = UDim.new(0, 8)
		cornerSolo.Parent = btnSolo

		btnSolo.MouseButton1Click:Connect(function()
			if HUDController.TextoAlertaLobby then
				HUDController.TextoAlertaLobby.Text = "Preparando expedición individual..."
				HUDController.TextoAlertaLobby.TextColor3 = Color3.fromRGB(140, 230, 255)
			end
			enviarAccionLobby("IniciarIndividual")
		end)

		local btnCoop = Instance.new("TextButton")
		btnCoop.Name = "BotonBuscarCoop"
		btnCoop.Size = UDim2.new(0.5, -18, 0, 42)
		btnCoop.Position = UDim2.new(0.5, 6, 0, 34)
		btnCoop.BackgroundColor3 = Color3.fromRGB(30, 110, 135)
		btnCoop.TextColor3 = Color3.fromRGB(255, 255, 255)
		btnCoop.Font = Enum.Font.GothamBold
		btnCoop.TextSize = 13
		btnCoop.Text = "Buscar partida cooperativa"
		btnCoop.ZIndex = 31
		btnCoop.Parent = panelAcceso

		local cornerCoop = Instance.new("UICorner")
		cornerCoop.CornerRadius = UDim.new(0, 8)
		cornerCoop.Parent = btnCoop

		btnCoop.MouseButton1Click:Connect(function()
			if HUDController.TextoAlertaLobby then
				HUDController.TextoAlertaLobby.Text = "Buscando sala pública disponible..."
				HUDController.TextoAlertaLobby.TextColor3 = Color3.fromRGB(140, 230, 255)
			end
			enviarAccionLobby("BuscarCoop")
		end)

		local txtAlertaLobby = Instance.new("TextLabel")
		txtAlertaLobby.Name = "TextoAlertaLobby"
		txtAlertaLobby.Size = UDim2.new(1, -24, 0, 24)
		txtAlertaLobby.Position = UDim2.new(0, 12, 0, 82)
		txtAlertaLobby.BackgroundTransparency = 1
		txtAlertaLobby.TextColor3 = Color3.fromRGB(170, 165, 195)
		txtAlertaLobby.Font = Enum.Font.Gotham
		txtAlertaLobby.TextSize = 12
		txtAlertaLobby.Text = "Elige modo individual o únete a una sala cooperativa pública."
		txtAlertaLobby.ZIndex = 31
		txtAlertaLobby.Parent = panelAcceso
		HUDController.TextoAlertaLobby = txtAlertaLobby

		-- Ventana de Sala Cooperativa (Sección 3.3)
		local panelSala = Instance.new("Frame")
		panelSala.Name = "PanelSalaCoop"
		panelSala.Size = UDim2.new(0, 500, 0, 316)
		panelSala.Position = UDim2.new(0.5, -250, 0.5, -158)
		panelSala.BackgroundColor3 = Color3.fromRGB(16, 12, 26)
		panelSala.BackgroundTransparency = 0.12
		panelSala.BorderSizePixel = 0
		panelSala.Visible = false
		panelSala.ZIndex = 35
		panelSala.Parent = gui
		HUDController.PanelSalaCoop = panelSala

		local cornerSala = Instance.new("UICorner")
		cornerSala.CornerRadius = UDim.new(0, 12)
		cornerSala.Parent = panelSala

		local strokeSala = Instance.new("UIStroke")
		strokeSala.Color = Color3.fromRGB(80, 200, 255)
		strokeSala.Thickness = 1.6
		strokeSala.Parent = panelSala

		local headerSala = Instance.new("TextLabel")
		headerSala.Name = "HeaderSala"
		headerSala.Size = UDim2.new(0.6, 0, 0, 30)
		headerSala.Position = UDim2.new(0, 16, 0, 10)
		headerSala.BackgroundTransparency = 1
		headerSala.TextXAlignment = Enum.TextXAlignment.Left
		headerSala.TextColor3 = Color3.fromRGB(230, 240, 255)
		headerSala.Font = Enum.Font.GothamBlack
		headerSala.TextSize = 16
		headerSala.Text = "SALA COOPERATIVA"
		headerSala.ZIndex = 36
		headerSala.Parent = panelSala

		local txtPlazas = Instance.new("TextLabel")
		txtPlazas.Name = "TextoPlazasSala"
		txtPlazas.Size = UDim2.new(0.35, 0, 0, 30)
		txtPlazas.Position = UDim2.new(0.65, -16, 0, 10)
		txtPlazas.BackgroundTransparency = 1
		txtPlazas.TextXAlignment = Enum.TextXAlignment.Right
		txtPlazas.TextColor3 = Color3.fromRGB(100, 240, 255)
		txtPlazas.Font = Enum.Font.GothamBlack
		txtPlazas.TextSize = 15
		txtPlazas.Text = "PLAZAS: 0 / 4"
		txtPlazas.ZIndex = 36
		txtPlazas.Parent = panelSala
		HUDController.TextoPlazasSala = txtPlazas

		HUDController.FilasParticipantesSala = {}
		for i = 1, 4 do
			local fila = Instance.new("Frame")
			fila.Name = string.format("SlotParticipante_%d", i)
			fila.Size = UDim2.new(1, -32, 0, 40)
			fila.Position = UDim2.new(0, 16, 0, 48 + (i - 1) * 46)
			fila.BackgroundColor3 = Color3.fromRGB(24, 18, 38)
			fila.BackgroundTransparency = 0.2
			fila.BorderSizePixel = 0
			fila.ZIndex = 36
			fila.Parent = panelSala

			local cornerFila = Instance.new("UICorner")
			cornerFila.CornerRadius = UDim.new(0, 8)
			cornerFila.Parent = fila

			local lblNombre = Instance.new("TextLabel")
			lblNombre.Name = "Nombre"
			lblNombre.Size = UDim2.new(0.45, -10, 1, 0)
			lblNombre.Position = UDim2.new(0, 12, 0, 0)
			lblNombre.BackgroundTransparency = 1
			lblNombre.TextXAlignment = Enum.TextXAlignment.Left
			lblNombre.TextColor3 = Color3.fromRGB(240, 240, 255)
			lblNombre.Font = Enum.Font.GothamBold
			lblNombre.TextSize = 13
			lblNombre.Text = "Plaza disponible..."
			lblNombre.ZIndex = 37
			lblNombre.Parent = fila

			local lblRol = Instance.new("TextLabel")
			lblRol.Name = "Rol"
			lblRol.Size = UDim2.new(0.3, 0, 1, 0)
			lblRol.Position = UDim2.new(0.45, 0, 0, 0)
			lblRol.BackgroundTransparency = 1
			lblRol.TextXAlignment = Enum.TextXAlignment.Center
			lblRol.TextColor3 = Color3.fromRGB(255, 210, 80)
			lblRol.Font = Enum.Font.GothamBlack
			lblRol.TextSize = 11
			lblRol.Text = ""
			lblRol.ZIndex = 37
			lblRol.Parent = fila

			local lblEstado = Instance.new("TextLabel")
			lblEstado.Name = "Estado"
			lblEstado.Size = UDim2.new(0.25, -12, 1, 0)
			lblEstado.Position = UDim2.new(0.75, 0, 0, 0)
			lblEstado.BackgroundTransparency = 1
			lblEstado.TextXAlignment = Enum.TextXAlignment.Right
			lblEstado.TextColor3 = Color3.fromRGB(120, 240, 160)
			lblEstado.Font = Enum.Font.GothamMedium
			lblEstado.TextSize = 12
			lblEstado.Text = ""
			lblEstado.ZIndex = 37
			lblEstado.Parent = fila

			table.insert(HUDController.FilasParticipantesSala, {
				Nombre = lblNombre,
				Rol = lblRol,
				Estado = lblEstado,
			})
		end

		local txtEstadoSala = Instance.new("TextLabel")
		txtEstadoSala.Name = "TextoEstadoSala"
		txtEstadoSala.Size = UDim2.new(1, -32, 0, 22)
		txtEstadoSala.Position = UDim2.new(0, 16, 0, 234)
		txtEstadoSala.BackgroundTransparency = 1
		txtEstadoSala.TextColor3 = Color3.fromRGB(185, 195, 225)
		txtEstadoSala.Font = Enum.Font.Gotham
		txtEstadoSala.TextSize = 12
		txtEstadoSala.Text = ""
		txtEstadoSala.ZIndex = 36
		txtEstadoSala.Parent = panelSala
		HUDController.TextoEstadoSala = txtEstadoSala

		local btnIniciarSala = Instance.new("TextButton")
		btnIniciarSala.Name = "BotonIniciarSala"
		btnIniciarSala.Size = UDim2.new(0.55, -20, 0, 40)
		btnIniciarSala.Position = UDim2.new(0, 16, 1, -54)
		btnIniciarSala.BackgroundColor3 = Color3.fromRGB(45, 145, 95)
		btnIniciarSala.TextColor3 = Color3.fromRGB(255, 255, 255)
		btnIniciarSala.Font = Enum.Font.GothamBold
		btnIniciarSala.TextSize = 13
		btnIniciarSala.Text = "Iniciar expedición"
		btnIniciarSala.ZIndex = 36
		btnIniciarSala.Parent = panelSala
		HUDController.BotonIniciarSala = btnIniciarSala

		local cornerIniciarSala = Instance.new("UICorner")
		cornerIniciarSala.CornerRadius = UDim.new(0, 8)
		cornerIniciarSala.Parent = btnIniciarSala

		btnIniciarSala.MouseButton1Click:Connect(function()
			if btnIniciarSala.Active then
				enviarAccionLobby("IniciarExpedicionSala")
			end
		end)

		local btnAbandonarSala = Instance.new("TextButton")
		btnAbandonarSala.Name = "BotonAbandonarSala"
		btnAbandonarSala.Size = UDim2.new(0.45, -20, 0, 40)
		btnAbandonarSala.Position = UDim2.new(0.55, 4, 1, -54)
		btnAbandonarSala.BackgroundColor3 = Color3.fromRGB(145, 40, 60)
		btnAbandonarSala.TextColor3 = Color3.fromRGB(255, 255, 255)
		btnAbandonarSala.Font = Enum.Font.GothamBold
		btnAbandonarSala.TextSize = 13
		btnAbandonarSala.Text = "Abandonar sala"
		btnAbandonarSala.ZIndex = 36
		btnAbandonarSala.Parent = panelSala
		HUDController.BotonAbandonarSala = btnAbandonarSala

		local cornerAbandonar = Instance.new("UICorner")
		cornerAbandonar.CornerRadius = UDim.new(0, 8)
		cornerAbandonar.Parent = btnAbandonarSala

		btnAbandonarSala.MouseButton1Click:Connect(function()
			enviarAccionLobby("AbandonarSala")
		end)

		-- Banner de reconexión en curso (Sección 13)
		local bannerRec = Instance.new("Frame")
		bannerRec.Name = "BannerReconexion"
		bannerRec.Size = UDim2.new(0, 480, 0, 68)
		bannerRec.Position = UDim2.new(0.5, -240, 0, 18)
		bannerRec.BackgroundColor3 = Color3.fromRGB(20, 14, 34)
		bannerRec.BackgroundTransparency = 0.14
		bannerRec.BorderSizePixel = 0
		bannerRec.Visible = false
		bannerRec.ZIndex = 38
		bannerRec.Parent = gui
		HUDController.BannerReconexion = bannerRec

		local cornerRec = Instance.new("UICorner")
		cornerRec.CornerRadius = UDim.new(0, 10)
		cornerRec.Parent = bannerRec

		local strokeRec = Instance.new("UIStroke")
		strokeRec.Color = Color3.fromRGB(240, 200, 70)
		strokeRec.Thickness = 1.6
		strokeRec.Parent = bannerRec

		local txtRec = Instance.new("TextLabel")
		txtRec.Name = "TextoReconexion"
		txtRec.Size = UDim2.new(0.58, -12, 1, -12)
		txtRec.Position = UDim2.new(0, 12, 0, 6)
		txtRec.BackgroundTransparency = 1
		txtRec.TextXAlignment = Enum.TextXAlignment.Left
		txtRec.TextWrapped = true
		txtRec.TextColor3 = Color3.fromRGB(255, 225, 130)
		txtRec.Font = Enum.Font.GothamBold
		txtRec.TextSize = 12
		txtRec.Text = "Expedición en curso disponible"
		txtRec.ZIndex = 39
		txtRec.Parent = bannerRec
		HUDController.TextoReconexion = txtRec

		local btnRecon = Instance.new("TextButton")
		btnRecon.Name = "BotonReconectar"
		btnRecon.Size = UDim2.new(0.42, -14, 0, 40)
		btnRecon.Position = UDim2.new(0.58, 4, 0.5, -20)
		btnRecon.BackgroundColor3 = Color3.fromRGB(45, 150, 95)
		btnRecon.TextColor3 = Color3.fromRGB(255, 255, 255)
		btnRecon.Font = Enum.Font.GothamBlack
		btnRecon.TextSize = 11
		btnRecon.TextWrapped = true
		btnRecon.Text = "RECONECTAR A EXPEDICIÓN EN CURSO"
		btnRecon.ZIndex = 39
		btnRecon.Parent = bannerRec
		HUDController.BotonReconectar = btnRecon

		local cornerBtnRec = Instance.new("UICorner")
		cornerBtnRec.CornerRadius = UDim.new(0, 8)
		cornerBtnRec.Parent = btnRecon

		btnRecon.MouseButton1Click:Connect(function()
			btnRecon.Text = "Reconectando..."
			btnRecon.Active = false
			local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
			local remoteSol = if remotesFolder then remotesFolder:FindFirstChild("SolicitarReconexionLobby") :: RemoteEvent? else nil
			if remoteSol then
				remoteSol:FireServer()
			end
		end)
	end

	-- 9. Bucle de reloj de supervivencia: SOLO se activa en la Expedición durante "Playing"
	-- En el Lobby no se conecta ningún cronómetro ascendente.
	if not esLobby then
		HUDController.ConexionReloj = RunService.RenderStepped:Connect(function(dt: number)
			if not HUDController.Activo or not HUDController.TextoReloj then return end
			if HUDController.RelojCongelado or not HUDController.RelojEnCurso then return end

			HUDController.TiempoLogicoSegundos += dt * HUDController.MultiplicadorTiempo
			HUDController.RefrescarTextoReloj()
		end)
	end

	-- 10. Escuchar eventos de emparejamiento (Lobby) y magias (Expedición) desde el servidor
	task.spawn(function()
		local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
		if remotesFolder then
			local remoteSala = remotesFolder:WaitForChild("SincronizarSalaCooperativa", 10) :: RemoteEvent?
			if remoteSala then
				remoteSala.OnClientEvent:Connect(function(datosSala: any, mensajeAlerta: string?)
					HUDController.ActualizarSalaCooperativa(datosSala, mensajeAlerta)
				end)
			end

			if esLobby then
				local remoteRec = remotesFolder:WaitForChild("EstadoReconexionLobby", 10) :: RemoteEvent?
				if remoteRec then
					remoteRec.OnClientEvent:Connect(function(datosRec: any)
						HUDController.ActualizarReconexionLobby(datosRec)
					end)
				end
			else
				local remoteMagias = remotesFolder:WaitForChild("SincronizarMagiasJugador", 10) :: RemoteEvent?
				if remoteMagias then
					remoteMagias.OnClientEvent:Connect(function(datosMagias: any)
						HUDController.ActualizarMagiasJugador(datosMagias)
					end)
				end

				local remoteJefe = remotesFolder:WaitForChild("SincronizarJefeFinal", 10) :: RemoteEvent?
				if remoteJefe then
					remoteJefe.OnClientEvent:Connect(function(datosJefe: any)
						HUDController.ActualizarJefeFinal(datosJefe)
					end)
				end

				local remoteResultados = remotesFolder:WaitForChild("PresentarResultadosExpedicion", 10) :: RemoteEvent?
				if remoteResultados then
					remoteResultados.OnClientEvent:Connect(function(reporte: any)
						HUDController.MostrarFlujoResultados(reporte)
					end)
				end
			end
		end
	end)

	print(string.format("[UMBRA Client] HUDController iniciado con éxito (Modo: %s).", if esLobby then "Lobby" else "Expedición"))
end

function HUDController.RefrescarTextoReloj()
	if not HUDController.TextoReloj then return end
	local tiempoTotal = math.max(0, math.floor(HUDController.TiempoLogicoSegundos))
	local mins = math.floor(tiempoTotal / 60)
	local secs = tiempoTotal % 60
	HUDController.TextoReloj.Text = string.format("%02d:%02d", mins, secs)
end

function HUDController.ActualizarRelojExpedicion(datos: any)
	if not datos or typeof(datos) ~= "table" then return end

	if typeof(datos.TiempoLogicoSegundos) == "number" then
		HUDController.TiempoLogicoSegundos = datos.TiempoLogicoSegundos
	end
	if typeof(datos.MultiplicadorTiempo) == "number" then
		HUDController.MultiplicadorTiempo = datos.MultiplicadorTiempo
	end
	if typeof(datos.ModoAceleradoActivo) == "boolean" then
		HUDController.ModoAceleradoActivo = datos.ModoAceleradoActivo
	end

	if HUDController.BotonDevVelocidad then
		if HUDController.ModoAceleradoActivo then
			HUDController.BotonDevVelocidad.Text = string.format("Vel: x%.0f (ACTIVO)", HUDController.MultiplicadorTiempo)
			HUDController.BotonDevVelocidad.BackgroundColor3 = Color3.fromRGB(45, 130, 80)
		else
			HUDController.BotonDevVelocidad.Text = "Vel: x1"
			HUDController.BotonDevVelocidad.BackgroundColor3 = Color3.fromRGB(45, 35, 70)
		end
	end

	if HUDController.TextoEstado and HUDController.RelojEnCurso and not HUDController.RelojCongelado then
		if HUDController.JefeActivoLocal then
			HUDController.TextoEstado.Text = "¡JEFE FINAL EN LA ARENA!"
			HUDController.TextoEstado.TextColor3 = Color3.fromRGB(255, 110, 130)
		elseif typeof(datos.OleadaActual) == "number" and typeof(datos.EnemigosActivosCount) == "number" then
			HUDController.TextoEstado.Text = string.format("OLEADA %d • ENEMIGOS: %d", datos.OleadaActual, datos.EnemigosActivosCount)
			HUDController.TextoEstado.TextColor3 = Color3.fromRGB(140, 240, 180)
		end
	end

	HUDController.RefrescarTextoReloj()
end

function HUDController.DispararFinPartida(esVictoria: boolean)
	if HUDController.RelojCongelado then return end
	HUDController.RelojCongelado = true
	HUDController.RelojEnCurso = false

	if HUDController.PanelMejorasNivel then
		HUDController.PanelMejorasNivel.Visible = false
	end
	if HUDController.ContenedorVidaJefe then
		HUDController.ContenedorVidaJefe.Visible = false
	end
	if HUDController.ContenedorRanurasMagia then
		HUDController.ContenedorRanurasMagia.Visible = false
	end
	if HUDController.ContenedorCompanieros then
		HUDController.ContenedorCompanieros.Visible = false
	end
	if HUDController.ContenedorCompanieros then
		HUDController.ContenedorCompanieros.Visible = false
	end
	if HUDController.ContenedorVida then
		HUDController.ContenedorVida.Visible = false
	end
	if HUDController.ContenedorXP then
		HUDController.ContenedorXP.Visible = false
	end

	local tiempoTotal = math.max(0, math.floor(HUDController.TiempoLogicoSegundos))
	HUDController.TiempoFinalCongelado = tiempoTotal

	local mins = math.floor(tiempoTotal / 60)
	local secs = tiempoTotal % 60
	local formatoTiempo = string.format("%02d:%02d", mins, secs)

	if HUDController.TextoReloj then
		HUDController.TextoReloj.Text = formatoTiempo
		HUDController.TextoReloj.TextColor3 = if esVictoria then Color3.fromRGB(240, 200, 80) else Color3.fromRGB(255, 70, 70)
	end

	if HUDController.TextoEstado then
		HUDController.TextoEstado.Text = if esVictoria then "EXPEDICIÓN COMPLETADA" else "EXPEDICIÓN FALLIDA"
		HUDController.TextoEstado.TextColor3 = if esVictoria then Color3.fromRGB(240, 200, 80) else Color3.fromRGB(255, 60, 60)
	end
end

function HUDController.DispararVictoria()
	HUDController.DispararFinPartida(true)
end

function HUDController.DispararDerrota()
	HUDController.DispararFinPartida(false)
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

function HUDController.ActualizarSalaCooperativa(datosSala: TiposAlpha.EstadoSalaCooperativa?, mensajeAlerta: string?)
	if not PlacesConfig.EsLobby() then return end

	if not datosSala or typeof(datosSala) ~= "table" then
		if HUDController.PanelSalaCoop then
			HUDController.PanelSalaCoop.Visible = false
		end
		if HUDController.PanelAccesoLobby then
			HUDController.PanelAccesoLobby.Visible = true
		end
		if HUDController.TextoAlertaLobby then
			if mensajeAlerta and mensajeAlerta ~= "" then
				HUDController.TextoAlertaLobby.Text = mensajeAlerta
				HUDController.TextoAlertaLobby.TextColor3 = Color3.fromRGB(255, 90, 90)
			else
				HUDController.TextoAlertaLobby.Text = "Elige modo individual o únete a una sala cooperativa pública."
				HUDController.TextoAlertaLobby.TextColor3 = Color3.fromRGB(170, 165, 195)
			end
		end
		return
	end

	-- Jugador dentro de una sala pública cooperativa
	if HUDController.PanelAccesoLobby then
		HUDController.PanelAccesoLobby.Visible = false
	end
	if HUDController.PanelSalaCoop then
		HUDController.PanelSalaCoop.Visible = true
	end

	if HUDController.TextoPlazasSala then
		HUDController.TextoPlazasSala.Text = string.format("PLAZAS: %d / %d", datosSala.PlazasOcupadas, datosSala.CapacidadMaxima)
	end

	for i = 1, 4 do
		local fila = HUDController.FilasParticipantesSala[i]
		if fila then
			local participante = datosSala.Participantes[i]
			if participante then
				fila.Nombre.Text = participante.Nombre
				fila.Nombre.TextColor3 = Color3.fromRGB(245, 245, 255)
				fila.Rol.Text = if participante.EsResponsable then "[RESPONSABLE]" else ""
				fila.Estado.Text = participante.Estado
				fila.Estado.TextColor3 = if participante.Estado == "Conectado"
					then Color3.fromRGB(110, 240, 150)
					else Color3.fromRGB(255, 180, 80)
			else
				fila.Nombre.Text = "Plaza disponible..."
				fila.Nombre.TextColor3 = Color3.fromRGB(130, 125, 150)
				fila.Rol.Text = ""
				fila.Estado.Text = ""
			end
		end
	end

	local esResponsable = (localPlayer.UserId == datosSala.ResponsableUserId)
	if HUDController.BotonIniciarSala then
		if datosSala.IniciandoExpedicion then
			HUDController.BotonIniciarSala.Text = "Iniciando expedición..."
			HUDController.BotonIniciarSala.Active = false
			HUDController.BotonIniciarSala.BackgroundColor3 = Color3.fromRGB(55, 70, 90)
		elseif esResponsable then
			HUDController.BotonIniciarSala.Text = "Iniciar expedición"
			HUDController.BotonIniciarSala.Active = true
			HUDController.BotonIniciarSala.BackgroundColor3 = Color3.fromRGB(45, 145, 95)
		else
			HUDController.BotonIniciarSala.Text = "Esperando al responsable..."
			HUDController.BotonIniciarSala.Active = false
			HUDController.BotonIniciarSala.BackgroundColor3 = Color3.fromRGB(60, 55, 80)
		end
	end

	if HUDController.TextoEstadoSala then
		local aviso = datosSala.MensajeAlerta or mensajeAlerta
		if aviso and aviso ~= "" then
			HUDController.TextoEstadoSala.Text = aviso
			HUDController.TextoEstadoSala.TextColor3 = Color3.fromRGB(255, 100, 100)
		elseif datosSala.IniciandoExpedicion then
			HUDController.TextoEstadoSala.Text = "Teletransportando a la expedición..."
			HUDController.TextoEstadoSala.TextColor3 = Color3.fromRGB(100, 240, 255)
		elseif esResponsable then
			HUDController.TextoEstadoSala.Text = "Eres el responsable de esta sala. Puedes iniciar cuando quieras."
			HUDController.TextoEstadoSala.TextColor3 = Color3.fromRGB(255, 220, 110)
		else
			HUDController.TextoEstadoSala.Text = "Esperando a que el responsable inicie la expedición..."
			HUDController.TextoEstadoSala.TextColor3 = Color3.fromRGB(185, 195, 225)
		end
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
		if HUDController.ContenedorXP then HUDController.ContenedorXP.Visible = false end
		if HUDController.PanelMejorasNivel then HUDController.PanelMejorasNivel.Visible = false end
		if HUDController.ContenedorRanurasMagia then HUDController.ContenedorRanurasMagia.Visible = false end
		if HUDController.ContenedorVidaJefe then HUDController.ContenedorVidaJefe.Visible = false end
		if HUDController.ModalGameOver then HUDController.ModalGameOver.Visible = false end
		return
	end

	-- En la Expedición:
	if not HUDController.TextoEstado then return end

	if nuevoEstado == "Waiting" or nuevoEstado == "Starting" then
		HUDController.TextoEstado.Text = "PREPARANDO EXPEDICIÓN"
		HUDController.TextoEstado.TextColor3 = Color3.fromRGB(240, 200, 80)
		HUDController.RelojEnCurso = false
		HUDController.TiempoLogicoSegundos = 0
		HUDController.RefrescarTextoReloj()
		HUDController.OcultarDerrota()
		if HUDController.BannerSuperior then HUDController.BannerSuperior.Visible = true end
		if HUDController.ContenedorVida then HUDController.ContenedorVida.Visible = true end

	elseif nuevoEstado == "Playing" then
		HUDController.TextoEstado.Text = "SUPERVIVENCIA EN CURSO"
		HUDController.TextoEstado.TextColor3 = Color3.fromRGB(100, 240, 140)
		HUDController.OcultarDerrota()
		HUDController.RelojCongelado = false
		HUDController.RelojEnCurso = true
		if HUDController.BannerSuperior then HUDController.BannerSuperior.Visible = true end
		if HUDController.ContenedorVida then HUDController.ContenedorVida.Visible = true end
		if HUDController.BannerMatchmaking then HUDController.BannerMatchmaking.Visible = false end

	elseif nuevoEstado == "Victory" then
		HUDController.DetenerEspectador()
		HUDController.RelojEnCurso = false
		HUDController.DispararVictoria()

	elseif nuevoEstado == "GameOver" then
		HUDController.DetenerEspectador()
		HUDController.RelojEnCurso = false
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
	if HUDController.ContenedorXP then
		HUDController.ContenedorXP.Visible = false
	end
	if HUDController.PanelMejorasNivel then
		HUDController.PanelMejorasNivel.Visible = false
	end
	if HUDController.ContenedorVidaJefe then
		HUDController.ContenedorVidaJefe.Visible = false
	end
	if HUDController.ContenedorRanurasMagia then
		HUDController.ContenedorRanurasMagia.Visible = false
	end
	if HUDController.ContenedorCompanieros then
		HUDController.ContenedorCompanieros.Visible = false
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

function HUDController.ActualizarSupervivientes(lista: { TiposAlpha.MiembroEquipoEspectador })
	local equipo = lista or {}
	HUDController.EquipoCompleto = equipo

	local vivos: { TiposAlpha.MiembroEquipoEspectador } = {}
	for _, miembro in equipo do
		if miembro.Vivo then
			table.insert(vivos, miembro)
		end
	end
	HUDController.SupervivientesVivos = vivos

	-- Actualizar filas de la lista completa del equipo en modo espectador
	for i = 1, 4 do
		local fila = HUDController.FilasEquipoEspectador[i]
		if fila then
			local miembro = equipo[i]
			if miembro then
				fila.Boton.Visible = true
				fila.Nombre.Text = string.format("%s  (Nv. %d)", miembro.Name, miembro.Nivel or 1)
				if miembro.Vivo then
					fila.UserIdActual = miembro.UserId
					fila.Boton.Active = true
					fila.Boton.BackgroundColor3 = Color3.fromRGB(28, 22, 46)
					fila.Nombre.TextColor3 = Color3.fromRGB(240, 240, 255)
					fila.Estado.Text = string.format("VIVO  %d/%d", miembro.SaludActual, miembro.SaludMaxima)
					fila.Estado.TextColor3 = Color3.fromRGB(110, 240, 150)
				else
					fila.UserIdActual = nil
					fila.Boton.Active = false
					fila.Boton.BackgroundColor3 = Color3.fromRGB(20, 16, 28)
					fila.Nombre.TextColor3 = Color3.fromRGB(130, 125, 145)
					fila.Estado.Text = if miembro.Estado == "Disconnected" then "DESCONECTADO" else "ELIMINADO"
					fila.Estado.TextColor3 = Color3.fromRGB(220, 80, 90)
				end
			else
				fila.UserIdActual = nil
				fila.Boton.Visible = false
			end
		end
	end

	-- Actualizar tarjetas compactas de compañeros en cooperativo (HUD lateral)
	if HUDController.ContenedorCompanieros then
		local mostrarComp = (HUDController.ModoExpedicion == "Coop" and HUDController.EstadoIndividual == "Alive" and not HUDController.RelojCongelado)
		HUDController.ContenedorCompanieros.Visible = mostrarComp
		if mostrarComp then
			local idxTarjeta = 0
			for _, miembro in equipo do
				if miembro.UserId ~= localPlayer.UserId then
					idxTarjeta += 1
					local tarjeta = HUDController.TarjetasCompanieros[idxTarjeta]
					if tarjeta then
						tarjeta.Marco.Visible = true
						tarjeta.Nombre.Text = string.format("%s  Nv.%d", miembro.Name, miembro.Nivel or 1)
						local maxH = math.max(miembro.SaludMaxima or 100, 1)
						local ratio = math.clamp((miembro.SaludActual or 0) / maxH, 0, 1)
						tarjeta.BarraVida.Size = UDim2.new(ratio, 0, 1, 0)
						if miembro.Vivo then
							tarjeta.Estado.Text = "VIVO"
							tarjeta.Estado.TextColor3 = Color3.fromRGB(110, 240, 150)
						else
							tarjeta.Estado.Text = if miembro.Estado == "Disconnected" then "DESC." else "ELIM."
							tarjeta.Estado.TextColor3 = Color3.fromRGB(220, 80, 90)
						end
					end
				end
			end
			for i = idxTarjeta + 1, 4 do
				local tarjeta = HUDController.TarjetasCompanieros[i]
				if tarjeta then
					tarjeta.Marco.Visible = false
				end
			end
		end
	end

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
		if HUDController.TextoNivelEspectador then
			HUDController.TextoNivelEspectador.Text = "--"
		end
		if HUDController.TextoVidaEspectador then
			HUDController.TextoVidaEspectador.Text = "0 / 0"
		end
		if HUDController.BarraVidaEspectador then
			HUDController.BarraVidaEspectador.Size = UDim2.new(0, 0, 1, 0)
		end
		return
	end

	HUDController.IndiceEspectador = ((HUDController.IndiceEspectador - 1 + delta) % #lista) + 1
	local obj = lista[HUDController.IndiceEspectador]

	if obj then
		if HUDController.TextoEspectadorNombre then
			HUDController.TextoEspectadorNombre.Text = obj.Name
		end
		if HUDController.TextoNivelEspectador then
			HUDController.TextoNivelEspectador.Text = string.format("Nv. %d", obj.Nivel or 1)
		end
		local maxH = math.max(obj.SaludMaxima or 100, 1)
		local actH = math.clamp(obj.SaludActual or 0, 0, maxH)
		if HUDController.BarraVidaEspectador then
			TweenService:Create(HUDController.BarraVidaEspectador, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
				Size = UDim2.new(actH / maxH, 0, 1, 0),
			}):Play()
		end
		if HUDController.TextoVidaEspectador then
			HUDController.TextoVidaEspectador.Text = string.format("%d / %d", math.ceil(actH), math.ceil(maxH))
		end

		local targetPlayer = Players:GetPlayerByUserId(obj.UserId)
		if targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
			local controllers = localPlayer:WaitForChild("PlayerScripts"):WaitForChild("Controllers")
			local CameraController = require(controllers:WaitForChild("CameraController") :: ModuleScript)
			CameraController.EstablecerModoEspectador(true, targetPlayer.Character.HumanoidRootPart :: BasePart)
		end
	end
end

function HUDController.ActualizarReconexionLobby(datos: TiposAlpha.DatosReconexionLobby)
	if not PlacesConfig.EsLobby() or not HUDController.BannerReconexion then return end
	if not datos or typeof(datos) ~= "table" or not datos.Disponible or datos.SegundosRestantes <= 0 then
		HUDController.BannerReconexion.Visible = false
		return
	end

	HUDController.SegundosReconexionRestantes = math.floor(datos.SegundosRestantes)
	HUDController.BannerReconexion.Visible = true
	if HUDController.BotonReconectar then
		HUDController.BotonReconectar.Text = "RECONECTAR A EXPEDICIÓN EN CURSO"
		HUDController.BotonReconectar.Active = true
	end

	task.spawn(function()
		while HUDController.BannerReconexion and HUDController.BannerReconexion.Visible and HUDController.SegundosReconexionRestantes > 0 do
			if HUDController.TextoReconexion then
				local mins = math.floor(HUDController.SegundosReconexionRestantes / 60)
				local secs = HUDController.SegundosReconexionRestantes % 60
				HUDController.TextoReconexion.Text = string.format("EXPEDICIÓN EN CURSO\nTiempo restante: %02d:%02d", mins, secs)
			end
			task.wait(1)
			HUDController.SegundosReconexionRestantes -= 1
		end
		if HUDController.BannerReconexion and HUDController.SegundosReconexionRestantes <= 0 then
			HUDController.BannerReconexion.Visible = false
		end
	end)
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

function HUDController.ActualizarProgresion(datos: TiposAlpha.EstadoProgresionJugador)
	if PlacesConfig.EsLobby() then return end
	if not datos or typeof(datos) ~= "table" then return end

	if HUDController.TextoNivel then
		HUDController.TextoNivel.Text = string.format("NV. %d", datos.Nivel)
	end

	local xpReq = math.max(datos.XpRequerida, 1)
	local ratio = math.clamp(datos.XpActual / xpReq, 0, 1)
	if HUDController.BarraXP then
		TweenService:Create(HUDController.BarraXP, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
			Size = UDim2.new(ratio, 0, 1, 0),
		}):Play()
	end
	if HUDController.TextoXP then
		HUDController.TextoXP.Text = string.format("%d / %d XP", math.floor(datos.XpActual), math.floor(xpReq))
	end

	if not HUDController.PanelMejorasNivel then return end

	local opciones = datos.OpcionesActuales
	if opciones and #opciones > 0 and HUDController.EstadoIndividual == "Alive" then
		for i, tarjeta in HUDController.TarjetasMejora do
			local opcion = opciones[i]
			if opcion then
				tarjeta.IdOpcionActual = opcion.IdOpcion
				tarjeta.Boton.Visible = true
				tarjeta.Titulo.Text = opcion.Titulo
				tarjeta.Descripcion.Text = opcion.Descripcion
				tarjeta.Nivel.Text = string.format("Nv. %d ➔ %d", opcion.NivelActual, opcion.NivelSiguiente)

				if opcion.Tipo == "Atributo" then
					tarjeta.Tipo.Text = "ATRIBUTO"
					tarjeta.Tipo.TextColor3 = Color3.fromRGB(120, 240, 160)
				elseif opcion.Tipo == "MagiaNueva" then
					tarjeta.Tipo.Text = "NUEVA MAGIA"
					tarjeta.Tipo.TextColor3 = Color3.fromRGB(255, 200, 80)
				else
					tarjeta.Tipo.Text = "MEJORA MAGIA"
					tarjeta.Tipo.TextColor3 = Color3.fromRGB(110, 225, 255)
				end
			else
				tarjeta.IdOpcionActual = nil
				tarjeta.Boton.Visible = false
			end
		end
		HUDController.PanelMejorasNivel.Visible = true
	else
		for _, tarjeta in HUDController.TarjetasMejora do
			tarjeta.IdOpcionActual = nil
		end
		HUDController.PanelMejorasNivel.Visible = false
	end
end

function HUDController.ActualizarMagiasJugador(datos: TiposAlpha.EstadoMagiasJugador)
	if PlacesConfig.EsLobby() then return end
	if not datos or typeof(datos) ~= "table" or typeof(datos.Magias) ~= "table" then return end

	for i = 1, 6 do
		local ranura = HUDController.RanurasMagiaHUD[i]
		if ranura then
			local magia = datos.Magias[i]
			if magia then
				ranura.Nombre.Text = magia.Nombre
				ranura.Nombre.TextColor3 = Color3.fromRGB(245, 245, 255)
				ranura.Nivel.Text = if magia.Nivel >= magia.MaxNivel
					then "MAX"
					else string.format("Nv. %d/%d", magia.Nivel, magia.MaxNivel)
				ranura.Nivel.TextColor3 = if magia.Nivel >= magia.MaxNivel
					then Color3.fromRGB(255, 215, 70)
					else Color3.fromRGB(120, 235, 255)
				ranura.Borde.Color = magia.Color
				ranura.Marco.BackgroundColor3 = Color3.fromRGB(30, 24, 46)
			else
				ranura.Nombre.Text = "[VACÍO]"
				ranura.Nombre.TextColor3 = Color3.fromRGB(130, 125, 150)
				ranura.Nivel.Text = ""
				ranura.Borde.Color = Color3.fromRGB(70, 60, 95)
				ranura.Marco.BackgroundColor3 = Color3.fromRGB(22, 17, 34)
			end
		end
	end
end

function HUDController.ActualizarJefeFinal(datos: TiposAlpha.EstadoJefeHUD)
	if PlacesConfig.EsLobby() then return end
	if not datos or typeof(datos) ~= "table" then return end
	if not HUDController.ContenedorVidaJefe then return end

	if not datos.Activo then
		HUDController.JefeActivoLocal = false
		HUDController.ContenedorVidaJefe.Visible = false
		return
	end

	HUDController.JefeActivoLocal = true

	local estabaOculto = not HUDController.ContenedorVidaJefe.Visible
	HUDController.ContenedorVidaJefe.Visible = true
	if estabaOculto then
		HUDController.ContenedorVidaJefe.Position = UDim2.new(0.5, -220, 0, 58)
		TweenService:Create(HUDController.ContenedorVidaJefe, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, -220, 0, 74),
		}):Play()
	end

	if HUDController.TextoNombreJefe then
		HUDController.TextoNombreJefe.Text = string.upper(datos.Nombre or "HERALDO DEL VACÍO")
	end

	local vidaMax = math.max(datos.VidaMax, 1)
	local ratio = math.clamp(datos.VidaActual / vidaMax, 0, 1)
	if HUDController.BarraVidaJefe then
		TweenService:Create(HUDController.BarraVidaJefe, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
			Size = UDim2.new(ratio, 0, 1, 0),
		}):Play()
	end

	if HUDController.TextoVidaJefe then
		HUDController.TextoVidaJefe.Text = string.format("%d / %d", math.max(0, math.ceil(datos.VidaActual)), math.ceil(vidaMax))
	end
end

function HUDController.SeleccionarMejoraPorIndice(indice: number)
	if PlacesConfig.EsLobby() then return end
	if not HUDController.PanelMejorasNivel or not HUDController.PanelMejorasNivel.Visible then return end
	local tarjeta = HUDController.TarjetasMejora[indice]
	if tarjeta and tarjeta.IdOpcionActual then
		local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
		local remoteSel = if remotesFolder then remotesFolder:FindFirstChild("SeleccionarMejoraNivel") :: RemoteEvent? else nil
		if remoteSel then
			remoteSel:FireServer(tarjeta.IdOpcionActual)
		end
	end
end

function HUDController.AbrirConfirmacionSalida()
	if HUDController.ModalConfirmacionSalida then
		HUDController.ModalConfirmacionSalida.Visible = true
	end
end

function HUDController.CambiarTabResultados(tabIndex: number)
	for i, sec in HUDController.SeccionesResultados do
		sec.Visible = (i == tabIndex)
	end
	for i, btn in HUDController.BotonesTabResultados do
		btn.BackgroundColor3 = if i == tabIndex
			then Color3.fromRGB(90, 50, 170)
			else Color3.fromRGB(28, 22, 44)
	end
end

function HUDController.MostrarFlujoResultados(reporte: TiposAlpha.ResultadosExpedicionIndividual)
	if PlacesConfig.EsLobby() then return end
	if not reporte or typeof(reporte) ~= "table" then return end

	local esVictoria = (reporte.Resultado == "VICTORIA")
	HUDController.DispararFinPartida(esVictoria)
	HUDController.DetenerEspectador()

	-- Poblar Sección 1: Resumen de Expedición
	local mins = math.floor((reporte.TiempoSobrevividoSegundos or 0) / 60)
	local secs = (reporte.TiempoSobrevividoSegundos or 0) % 60
	if HUDController.TextosResumen.Resultado then
		HUDController.TextosResumen.Resultado.Text = reporte.Resultado
		HUDController.TextosResumen.Resultado.TextColor3 = if esVictoria
			then Color3.fromRGB(255, 215, 80)
			else Color3.fromRGB(255, 75, 90)
	end
	if HUDController.TextosResumen.Tiempo then
		HUDController.TextosResumen.Tiempo.Text = string.format("%02d:%02d", mins, secs)
	end
	if HUDController.TextosResumen.Nivel then
		HUDController.TextosResumen.Nivel.Text = string.format("Nv. %d", reporte.NivelAlcanzado or 1)
	end
	if HUDController.TextosResumen.Enemigos then
		HUDController.TextosResumen.Enemigos.Text = tostring(reporte.EnemigosDerrotados or 0)
	end
	if HUDController.TextosResumen.Jefes then
		HUDController.TextosResumen.Jefes.Text = tostring(reporte.JefesDerrotados or 0)
	end
	if HUDController.TextosResumen.Botin then
		HUDController.TextosResumen.Botin.Text = string.format("%d Oro / %d Gemas", reporte.OroObtenido or 0, reporte.GemasObtenidas or 0)
	end

	-- Poblar Sección 2: Rendimiento de Combate (daño total + por magia, sin daño recibido ni comparación)
	if HUDController.TextoDanioTotalCombate then
		HUDController.TextoDanioTotalCombate.Text = string.format("Daño total causado: %d", reporte.DanioTotalCausado or 0)
	end
	if HUDController.ListaMagiasCombate then
		HUDController.ListaMagiasCombate:ClearAllChildren()
		local magias = reporte.MagiasUtilizadas or {}
		local maxDanio = math.max(reporte.DanioTotalCausado or 1, 1)
		for idx, mag in magias do
			local fila = Instance.new("Frame")
			fila.Size = UDim2.new(1, -8, 0, 34)
			fila.Position = UDim2.new(0, 0, 0, (idx - 1) * 38)
			fila.BackgroundColor3 = Color3.fromRGB(30, 22, 48)
			fila.BorderSizePixel = 0
			fila.ZIndex = 68
			fila.Parent = HUDController.ListaMagiasCombate

			local cornerF = Instance.new("UICorner")
			cornerF.CornerRadius = UDim.new(0, 6)
			cornerF.Parent = fila

			local lblNombre = Instance.new("TextLabel")
			lblNombre.Size = UDim2.new(0.55, -8, 0, 20)
			lblNombre.Position = UDim2.new(0, 8, 0, 2)
			lblNombre.BackgroundTransparency = 1
			lblNombre.TextXAlignment = Enum.TextXAlignment.Left
			lblNombre.TextColor3 = Color3.fromRGB(245, 245, 255)
			lblNombre.Font = Enum.Font.GothamBold
			lblNombre.TextSize = 12
			lblNombre.Text = string.format("%s (Nv. %d)", mag.Nombre, mag.NivelFinal)
			lblNombre.ZIndex = 69
			lblNombre.Parent = fila

			local lblDanio = Instance.new("TextLabel")
			lblDanio.Size = UDim2.new(0.45, -8, 0, 20)
			lblDanio.Position = UDim2.new(0.55, 0, 0, 2)
			lblDanio.BackgroundTransparency = 1
			lblDanio.TextXAlignment = Enum.TextXAlignment.Right
			lblDanio.TextColor3 = Color3.fromRGB(255, 210, 100)
			lblDanio.Font = Enum.Font.GothamBlack
			lblDanio.TextSize = 12
			lblDanio.Text = string.format("%d daño", mag.DanioCausado)
			lblDanio.ZIndex = 69
			lblDanio.Parent = fila

			local fondoBar = Instance.new("Frame")
			fondoBar.Size = UDim2.new(1, -16, 0, 6)
			fondoBar.Position = UDim2.new(0, 8, 0, 24)
			fondoBar.BackgroundColor3 = Color3.fromRGB(16, 12, 26)
			fondoBar.BorderSizePixel = 0
			fondoBar.ZIndex = 69
			fondoBar.Parent = fila

			local bar = Instance.new("Frame")
			bar.Size = UDim2.new(math.clamp(mag.DanioCausado / maxDanio, 0, 1), 0, 1, 0)
			bar.BackgroundColor3 = Color3.fromRGB(140, 90, 255)
			bar.BorderSizePixel = 0
			bar.ZIndex = 70
			bar.Parent = fondoBar
		end
		HUDController.ListaMagiasCombate.CanvasSize = UDim2.new(0, 0, 0, #magias * 38)
	end

	-- Poblar Sección 3: Recompensas
	if HUDController.TextosRecompensas.Oro then
		HUDController.TextosRecompensas.Oro.Text = string.format("Oro obtenido: %d", reporte.OroObtenido or 0)
	end
	if HUDController.TextosRecompensas.Gemas then
		HUDController.TextosRecompensas.Gemas.Text = string.format("Gemas obtenidas: %d", reporte.GemasObtenidas or 0)
	end

	-- Transición de 3 segundos con logotipo UMBRA y luego Pantalla de Resultados
	task.spawn(function()
		if HUDController.PantallaTransicionFin and HUDController.TextoTransicionResultado then
			HUDController.TextoTransicionResultado.Text = reporte.Resultado
			HUDController.TextoTransicionResultado.TextColor3 = if esVictoria
				then Color3.fromRGB(255, 215, 80)
				else Color3.fromRGB(255, 70, 85)
			HUDController.PantallaTransicionFin.Visible = true
		end

		task.wait(3)

		if HUDController.PantallaTransicionFin then
			HUDController.PantallaTransicionFin.Visible = false
		end
		if HUDController.PanelResultados then
			HUDController.CambiarTabResultados(1)
			HUDController.PanelResultados.Visible = true
		end
	end)
end

return HUDController
