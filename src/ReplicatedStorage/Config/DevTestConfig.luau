--!strict
-- DevTestConfig.luau
-- Configuración del Modo Acelerado de Desarrollo (Sección 15) para UMBRA: La última luz.
-- Responsabilidad: Definir multiplicadores de tiempo, hitos de salto rápido y validación autoritativa de acceso.

local RunService = game:GetService("RunService")

local DevTestConfig = {
	HabilitadoEnStudio = true,
	WhitelistUserIds = {} :: { [number]: boolean },

	DuracionExpedicionNormalSegundos = 1800, -- 30 minutos objetivo
	MultiplicadorPorDefecto = 1.0, -- Partida normal
	MultiplicadorAcelerado = 10.0, -- 30 min lógicos en 3 min reales

	HitosSaltoRapido = {
		Inicio = 0,
		Mitad = 900, -- 15:00
		PreJefe = 1790, -- 29:50
	},

	RecompensasPlaceholderAlpha = {
		OroVictoria = 0,
		GemasVictoria = 0,
		OroDerrota = 0,
		GemasDerrota = 0,
	}, -- [PENDIENTE DE FÓRMULA ECONÓMICA - SECCIÓN 14: No inventar valores definitivos]
}

-- Valida de forma estricta si un jugador está autorizado para usar herramientas de desarrollo.
function DevTestConfig.EsJugadorAutorizado(player: Player): boolean
	if not player then
		return false
	end

	if DevTestConfig.HabilitadoEnStudio and RunService:IsStudio() then
		return true
	end

	if game.CreatorId > 0 and player.UserId == game.CreatorId then
		return true
	end

	if DevTestConfig.WhitelistUserIds[player.UserId] == true then
		return true
	end

	return false
end

return DevTestConfig
