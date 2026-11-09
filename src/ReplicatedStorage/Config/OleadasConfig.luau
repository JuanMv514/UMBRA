--!strict
-- OleadasConfig.luau
-- Definición de fases de tiempo, tipos de enemigos activos y multiplicadores de dificultad.

export type OleadaFase = {
	MinutoInicio: number,
	MinutoFin: number,
	EnemigosPermitidos: { string },
	TasaSpawnPorSegundo: number,
	MultiplicadorVida: number,
}

local OleadasConfig: { OleadaFase } = {
	{
		MinutoInicio = 0,
		MinutoFin = 2,
		EnemigosPermitidos = { "EspectroMenor" },
		TasaSpawnPorSegundo = 2.0,
		MultiplicadorVida = 1.0,
	},
	{
		MinutoInicio = 2,
		MinutoFin = 5,
		EnemigosPermitidos = { "EspectroMenor", "AcechadorRapido" },
		TasaSpawnPorSegundo = 4.0,
		MultiplicadorVida = 1.25,
	},
	{
		MinutoInicio = 5,
		MinutoFin = 10,
		EnemigosPermitidos = { "EspectroMenor", "AcechadorRapido", "GolemSombrío" },
		TasaSpawnPorSegundo = 6.0,
		MultiplicadorVida = 1.6,
	},
}

return OleadasConfig
