--!strict
-- PlacesConfig.luau
-- Configuración autoritativa de Places y detección de entorno para UMBRA: La última luz.
-- Responsabilidad: Centralizar los identificadores de Places y distinguir entre Lobby y Expedición.

local PlacesConfig = {
	-- PLACE 1: Santuario / Lobby principal (identificador verificado del Place actual)
	LobbyPlaceId = 82280448337693,

	-- PLACE 2: Arena de Expedición / Supervivencia (identificador oficial verificado)
	ExpeditionPlaceId = 100031865578609,
}

-- Determina si el entorno actual de ejecución es el Lobby principal
function PlacesConfig.EsLobby(): boolean
	local currentId = game.PlaceId
	if currentId == PlacesConfig.LobbyPlaceId then
		return true
	end
	return currentId ~= PlacesConfig.ExpeditionPlaceId
end

-- Determina si el entorno actual de ejecución es la Arena de Expedición
function PlacesConfig.EsExpedicion(): boolean
	local currentId = game.PlaceId
	return PlacesConfig.ExpeditionPlaceId > 0 and currentId == PlacesConfig.ExpeditionPlaceId
end

return PlacesConfig
