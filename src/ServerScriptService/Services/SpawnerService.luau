--!strict
-- SpawnerService.luau
-- Director de oleadas y generación perimetral de enemigos en UMBRA.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigFolder = ReplicatedStorage:WaitForChild("Config")
local OleadasConfig = require(ConfigFolder:WaitForChild("OleadasConfig") :: ModuleScript)

local EnemyService = nil -- Inyectado al iniciar

local SpawnerService = {
	Activo = false,
	TiempoTranscurrido = 0,
	HilosSpawner = {} :: { thread },
	RadioMinimoSpawn = 45, -- Fuera del campo visual inmediato
	RadioMaximoSpawn = 65,
	MaxEnemigosVivos = 200,
}

function SpawnerService.Iniciar(enemyServiceRef: any)
	EnemyService = enemyServiceRef
	SpawnerService.Activo = true
	SpawnerService.TiempoTranscurrido = 0

	print("[UMBRA Server] SpawnerService iniciado (Director de Oleadas activo).")

	-- Hilo del reloj de oleadas
	local hiloReloj = task.spawn(function()
		while SpawnerService.Activo do
			task.wait(1)
			SpawnerService.TiempoTranscurrido += 1
		end
	end)
	table.insert(SpawnerService.HilosSpawner, hiloReloj)

	-- Hilo principal de generación
	local hiloSpawn = task.spawn(function()
		while SpawnerService.Activo do
			local fase = SpawnerService.ObtenerFaseActual()
			local intervalo = 1 / math.max(fase.TasaSpawnPorSegundo, 0.5)

			task.wait(intervalo)

			local totalEnemigos = 0
			for _ in EnemyService.EnemigosActivos do
				totalEnemigos += 1
			end

			if totalEnemigos < SpawnerService.MaxEnemigosVivos then
				SpawnerService.GenerarEnemigoAleatorio(fase)
			end
		end
	end)
	table.insert(SpawnerService.HilosSpawner, hiloSpawn)
end

function SpawnerService.ObtenerFaseActual()
	local minutos = SpawnerService.TiempoTranscurrido / 60
	for _, fase in OleadasConfig do
		if minutos >= fase.MinutoInicio and minutos < fase.MinutoFin then
			return fase
		end
	end
	-- Si excede el tiempo configurado, retorna la última fase
	return OleadasConfig[#OleadasConfig]
end

function SpawnerService.GenerarEnemigoAleatorio(fase: any)
	local jugadores = Players:GetPlayers()
	if #jugadores == 0 then return end

	-- Seleccionar un jugador objetivo aleatorio
	local jugadorTarget = jugadores[math.random(1, #jugadores)]
	local character = jugadorTarget.Character
	if not character then return end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end

	-- Elegir tipo de enemigo de la lista permitida en la fase actual
	local listaEnemigos = fase.EnemigosPermitidos
	local tipoElegido = listaEnemigos[math.random(1, #listaEnemigos)]

	-- Calcular posición en un anillo alrededor del jugador
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
		task.cancel(hilo)
	end
	SpawnerService.HilosSpawner = {}
end

return SpawnerService
