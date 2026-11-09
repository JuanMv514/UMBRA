--!strict
-- GameManager.luau
-- Servicio central de ciclo de vida de la sesión para UMBRA: La última luz.
-- Responsabilidad: Administrar estados de partida, sesiones de jugadores y transiciones seguras.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type EstadoPartida = "Waiting" | "Starting" | "Playing" | "GameOver"

local TRANSICIONES_VALIDAS: { [EstadoPartida]: { [EstadoPartida]: boolean } } = {
	Waiting = { Starting = true },
	Starting = { Playing = true, Waiting = true },
	Playing = { GameOver = true, Waiting = true },
	GameOver = { Starting = true, Waiting = true },
}

local GameManager = {
	EstadoActual = "Waiting" :: EstadoPartida,
	JugadoresConectados = {} :: { [Player]: boolean },
	ConexionesPersonajes = {} :: { [Player]: { RBXScriptConnection } },
	TransicionEnProgreso = false,
	RemoteSincronizar = nil :: RemoteEvent?,
}

-- Inicializa el servicio y localiza canales de comunicación
function GameManager.Iniciar()
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 5)
	if remotesFolder then
		local remote = remotesFolder:WaitForChild("SincronizarEstadoPartida", 5) :: RemoteEvent?
		if remote and remote:IsA("RemoteEvent") then
			GameManager.RemoteSincronizar = remote
		else
			warn("[GameManager] Advertencia: No se encontró el RemoteEvent 'SincronizarEstadoPartida'.")
		end
	end

	GameManager.EstadoActual = "Waiting"
	GameManager.TransicionEnProgreso = false
	print("[UMBRA Server] GameManager iniciado. Estado inicial: Waiting (Esperando supervivientes).")
end

-- Retorna el estado actual de la sesión
function GameManager.ObtenerEstado(): EstadoPartida
	return GameManager.EstadoActual
end

-- Valida y ejecuta un cambio de estado en la máquina de estados
function GameManager.CambiarEstado(nuevoEstado: EstadoPartida): boolean
	if GameManager.EstadoActual == nuevoEstado then
		return false
	end

	if GameManager.TransicionEnProgreso then
		warn(string.format("[GameManager] Transición rechazada: ya hay un cambio en progreso (%s -> %s)", GameManager.EstadoActual, nuevoEstado))
		return false
	end

	local permitidas = TRANSICIONES_VALIDAS[GameManager.EstadoActual]
	if not permitidas or not permitidas[nuevoEstado] then
		warn(string.format("[GameManager] Transición INVÁLIDA rechazada: %s -> %s", GameManager.EstadoActual, nuevoEstado))
		return false
	end

	GameManager.TransicionEnProgreso = true
	local estadoAnterior = GameManager.EstadoActual
	GameManager.EstadoActual = nuevoEstado

	print(string.format("[UMBRA Server] Transición de sesión: %s -> %s", estadoAnterior, nuevoEstado))

	-- Notificar a todos los clientes conectados de forma autoritativa
	if GameManager.RemoteSincronizar then
		GameManager.RemoteSincronizar:FireAllClients(nuevoEstado)
	end

	-- Lógica de entrada a cada estado
	if nuevoEstado == "Starting" then
		task.spawn(function()
			-- Pequeña pausa preparatoria para asegurar carga de entidades
			task.wait(1)
			GameManager.TransicionEnProgreso = false
			local total = #Players:GetPlayers()
			if total > 0 then
				GameManager.CambiarEstado("Playing")
			else
				GameManager.CambiarEstado("Waiting")
			end
		end)
		return true
	elseif nuevoEstado == "Playing" then
		print("[UMBRA Server] ¡Partida de supervivencia en curso!")
	elseif nuevoEstado == "GameOver" then
		print("[UMBRA Server] Fin de la sesión: Superviviente caído.")
	elseif nuevoEstado == "Waiting" then
		print("[UMBRA Server] Sesión reseteada. Esperando supervivientes...")
	end

	GameManager.TransicionEnProgreso = false
	return true
end

-- Manejador de conexión de nuevo jugador
function GameManager.OnPlayerAdded(player: Player)
	if GameManager.JugadoresConectados[player] then
		return -- Evitar registros duplicados
	end

	GameManager.JugadoresConectados[player] = true
	GameManager.ConexionesPersonajes[player] = {}
	print(string.format("[UMBRA Server] Superviviente registrado: %s (UserId: %d)", player.Name, player.UserId))

	-- Sincronizar estado actual inmediatamente al jugador que entra
	if GameManager.RemoteSincronizar then
		GameManager.RemoteSincronizar:FireClient(player, GameManager.EstadoActual)
	end

	-- Escuchar carga y reaparición del personaje
	local connChar = player.CharacterAdded:Connect(function(character)
		GameManager.OnCharacterAdded(player, character)
	end)
	table.insert(GameManager.ConexionesPersonajes[player], connChar)

	if player.Character then
		task.spawn(GameManager.OnCharacterAdded, player, player.Character)
	end

	-- Si estábamos esperando, iniciar la partida
	if GameManager.EstadoActual == "Waiting" then
		GameManager.CambiarEstado("Starting")
	end
end

-- Manejador de desconexión de jugador
function GameManager.OnPlayerRemoving(player: Player)
	GameManager.JugadoresConectados[player] = nil

	-- Limpiar conexiones del personaje
	local conns = GameManager.ConexionesPersonajes[player]
	if conns then
		for _, conn in conns do
			conn:Disconnect()
		end
		GameManager.ConexionesPersonajes[player] = nil
	end

	print(string.format("[UMBRA Server] Superviviente desconectado: %s", player.Name))

	-- Comprobar si quedan jugadores en la partida
	if #Players:GetPlayers() <= 1 and GameManager.EstadoActual ~= "Waiting" then
		GameManager.TransicionEnProgreso = false
		GameManager.CambiarEstado("Waiting")
	end
end

-- Manejador de ciclo de vida del personaje (muerte y salud autoritativa)
function GameManager.OnCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then return end

	local connDied: RBXScriptConnection? = nil
	connDied = humanoid.Died:Connect(function()
		if connDied then
			connDied:Disconnect()
		end
		print(string.format("[UMBRA Server] Superviviente %s ha muerto.", player.Name))

		-- Si la partida estaba en curso, transicionar a GameOver
		if GameManager.EstadoActual == "Playing" then
			GameManager.CambiarEstado("GameOver")
		end
	end)

	if GameManager.ConexionesPersonajes[player] and connDied then
		table.insert(GameManager.ConexionesPersonajes[player], connDied)
	end
end

-- Permite reiniciar una sesión de prueba limpia
function GameManager.ReiniciarPartida()
	print("[UMBRA Server] Solicitud de reinicio de sesión de prueba...")
	GameManager.TransicionEnProgreso = false

	-- Reaparecer personajes de jugadores conectados
	for _, player in Players:GetPlayers() do
		player:LoadCharacter()
	end

	GameManager.CambiarEstado("Starting")
end

return GameManager
