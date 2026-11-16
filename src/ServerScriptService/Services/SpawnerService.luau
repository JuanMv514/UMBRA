--!strict
-- SpawnerService.luau
-- Director de oleadas y generación perimetral de enemigos en UMBRA.
-- Responsabilidad: Orquestar el ritmo de spawn durante la expedición y detenerse
-- de forma inmediata e irreversible al finalizar la partida o al morir los jugadores.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigFolder = ReplicatedStorage:WaitForChild("Config")
local OleadasConfig = require(ConfigFolder:WaitForChild("OleadasConfig") :: ModuleScript)
local JefeConfig = require(ConfigFolder:WaitForChild("JefeConfig") :: ModuleScript)

local EnemyService = nil :: any -- Inyectado al iniciar
local GameManager = nil :: any -- Inyectado al iniciar o vincular
local BossService = nil :: any -- Inyectado al vincular

local SpawnerService = {
	Activo = false,
	TiempoTranscurrido = 0,
	HilosSpawner = {} :: { thread },
	RadioMinimoSpawn = 22,
	RadioMaximoSpawn = 42,
	MaxEnemigosVivos = 200,
}

function SpawnerService.VincularGameManager(gmRef: any)
	GameManager = gmRef
end

function SpawnerService.VincularBossService(bossRef: any)
	BossService = bossRef
end

function SpawnerService.Iniciar(enemyServiceRef: any, gmRef: any?)
	-- Si ya está activo, detener previamente para evitar bucles duplicados
	SpawnerService.Detener()

	if enemyServiceRef then
		EnemyService = enemyServiceRef
	end
	if gmRef then
		GameManager = gmRef
	end

	SpawnerService.Activo = true
	SpawnerService.TiempoTranscurrido = 0

	print("[UMBRA Server] SpawnerService iniciado (Director de Oleadas activo).")

	-- 1. Hilo de respaldo de reloj lógico (si GameManager no provee ObtenerTiempoLogico)
	local hiloReloj = task.spawn(function()
		local RunService = game:GetService("RunService")
		local ultimoTiempo = os.clock()
		while SpawnerService.Activo do
			RunService.Heartbeat:Wait()
			if not SpawnerService.Activo then break end
			local ahora = os.clock()
			local dt = ahora - ultimoTiempo
			ultimoTiempo = ahora
			if GameManager and typeof(GameManager.ObtenerTiempoLogico) == "function" then
				SpawnerService.TiempoTranscurrido = GameManager.ObtenerTiempoLogico()
			else
				SpawnerService.TiempoTranscurrido += dt
			end
		end
	end)
	table.insert(SpawnerService.HilosSpawner, hiloReloj)

	-- 2. Hilo principal de generación
	local hiloSpawn = task.spawn(function()
		while SpawnerService.Activo do
			-- Verificación estricta del estado de sesión: solo generar durante "Playing"
			if GameManager and typeof(GameManager.ObtenerEstado) == "function" then
				if GameManager.ObtenerEstado() ~= "Playing" then
					task.wait(0.5)
					continue
				end
			end

			local fase = SpawnerService.ObtenerFaseActual()
			local tasaSpawn = fase.TasaSpawnPorSegundo
			if BossService and typeof(BossService.EstaJefeActivo) == "function" and BossService.EstaJefeActivo() then
				tasaSpawn *= JefeConfig.FactorSpawnHordaDuranteJefe
			end
			local intervalo = 1 / math.max(tasaSpawn, 0.2)

			task.wait(intervalo)
			if not SpawnerService.Activo then break end

			-- Re-verificación tras el yield de espera
			if GameManager and typeof(GameManager.ObtenerEstado) == "function" then
				if GameManager.ObtenerEstado() ~= "Playing" then
					continue
				end
			end

			if EnemyService and EnemyService.EnemigosActivos then
				local totalEnemigos = 0
				for _ in EnemyService.EnemigosActivos do
					totalEnemigos += 1
				end

				if totalEnemigos < SpawnerService.MaxEnemigosVivos then
					SpawnerService.GenerarEnemigoAleatorio(fase)
				end
			end
		end
	end)
	table.insert(SpawnerService.HilosSpawner, hiloSpawn)
end

function SpawnerService.ObtenerFaseActual()
	local tiempoLogico = if GameManager and typeof(GameManager.ObtenerTiempoLogico) == "function"
		then GameManager.ObtenerTiempoLogico()
		else SpawnerService.TiempoTranscurrido
	local minutos = tiempoLogico / 60
	for _, fase in OleadasConfig do
		if minutos >= fase.MinutoInicio and minutos < fase.MinutoFin then
			return fase
		end
	end
	return OleadasConfig[#OleadasConfig]
end

function SpawnerService.GenerarEnemigoAleatorio(fase: any)
	-- Validación de seguridad
	if not SpawnerService.Activo then return end
	if not EnemyService or not EnemyService.Activo then return end

	if GameManager and typeof(GameManager.ObtenerEstado) == "function" then
		if GameManager.ObtenerEstado() ~= "Playing" then
			return
		end
	end

	local jugadores = Players:GetPlayers()
	if #jugadores == 0 then return end

	local jugadorTarget = jugadores[math.random(1, #jugadores)]
	local character = jugadorTarget.Character
	if not character then return end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return end

	local listaEnemigos = fase.EnemigosPermitidos
	local tipoElegido = listaEnemigos[math.random(1, #listaEnemigos)]

	local angulo = math.random() * math.pi * 2
	local radio = math.random(SpawnerService.RadioMinimoSpawn, SpawnerService.RadioMaximoSpawn)

	local offsetX = math.cos(angulo) * radio
	local offsetZ = math.sin(angulo) * radio
	local posSpawn = Vector3.new(root.Position.X + offsetX, 3, root.Position.Z + offsetZ)

	EnemyService.CrearEnemigo(tipoElegido, posSpawn, fase.MultiplicadorVida)
end

function SpawnerService.Detener()
	SpawnerService.Activo = false

	for _, hilo in SpawnerService.HilosSpawner do
		pcall(function()
			if hilo and hilo ~= coroutine.running() then
				task.cancel(hilo)
			end
		end)
	end
	table.clear(SpawnerService.HilosSpawner)

	print("[UMBRA Server] SpawnerService detenido. Generación de enemigos cancelada.")
end

return SpawnerService
