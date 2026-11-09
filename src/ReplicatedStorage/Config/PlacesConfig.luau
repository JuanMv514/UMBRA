--!strict
-- PlacesConfig.luau
-- Configuración autoritativa de Places y detección de entorno para UMBRA: La última luz.
-- Responsabilidad: Centralizar los identificadores de Places y distinguir entre Lobby y Expedición.

local PlacesConfig = {
	-- PLACE 1: Santuario / Lobby principal (identificador verificado del Place actual)
	LobbyPlaceId = 82280448337693,

	-- PLACE 2: Arena de Expedición / Supervivencia
	-- NOTA TÉCNICA: Actualmente la experiencia UMBRA (UniverseId: 10775489451) solo cuenta con
	-- un (1) Place creado: el Lobby (82280448337693).
	-- Cuando se cree el segundo Place desde Roblox Studio (Asset Manager > Places > Add Place),
	-- se debe asignar aquí su PlaceId numérico real (ej: 1234567890).
	ExpeditionPlaceId = 0,
}

-- Determina si el entorno actual de ejecución es el Lobby principal
function PlacesConfig.EsLobby(): boolean
	local currentId = game.PlaceId
	-- Si coincide con el LobbyPlaceId o si no existe un Place de expedición configurado
	if currentId == PlacesConfig.LobbyPlaceId or PlacesConfig.ExpeditionPlaceId <= 0 then
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
