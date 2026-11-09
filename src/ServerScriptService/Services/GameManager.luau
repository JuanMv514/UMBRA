--!strict
-- GameManager.luau
-- Servicio central de estado de la partida para UMBRA (Cerebro del Servidor).

local Players = game:GetService("Players")

local GameManager = {
	TiempoPartida = 0,
	PartidaActiva = false,
}

function GameManager.Iniciar()
	GameManager.PartidaActiva = true
	GameManager.TiempoPartida = 0
	print("[UMBRA Server] GameManager iniciado. Esperando supervivientes...")
end

function GameManager.OnPlayerAdded(player: Player)
	print(string.format("[UMBRA Server] Superviviente conectado: %s (UserId: %d)", player.Name, player.UserId))
end

function GameManager.OnPlayerRemoving(player: Player)
	print(string.format("[UMBRA Server] Superviviente desconectado: %s", player.Name))
end

return GameManager
