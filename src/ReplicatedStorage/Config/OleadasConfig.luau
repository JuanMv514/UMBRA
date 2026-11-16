--!strict
-- OleadasConfig.luau
-- Definición de fases de tiempo (0 a 30 minutos), tipos de enemigos activos y multiplicadores de dificultad.

export type OleadaFase = {
	MinutoInicio: number,
	MinutoFin: number,
	EnemigosPermitidos: { string },
	TasaSpawnPorSegundo: number,
	MultiplicadorVida: number,
}

local OleadasConfig: { OleadaFase } = {
	{
		MinutoInicio = 0, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		MinutoFin = 2, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		EnemigosPermitidos = { "EspectroMenor" },
		TasaSpawnPorSegundo = 2.0, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		MultiplicadorVida = 1.0, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
	},
	{
		MinutoInicio = 2, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		MinutoFin = 5, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		EnemigosPermitidos = { "EspectroMenor", "AcechadorRapido" },
		TasaSpawnPorSegundo = 3.5, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		MultiplicadorVida = 1.25, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
	},
	{
		MinutoInicio = 5, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		MinutoFin = 10, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		EnemigosPermitidos = { "EspectroMenor", "AcechadorRapido", "GolemSombrio" },
		TasaSpawnPorSegundo = 5.0, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		MultiplicadorVida = 1.6, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
	},
	{
		MinutoInicio = 10, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		MinutoFin = 15, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		EnemigosPermitidos = { "EspectroMenor", "AcechadorRapido", "GolemSombrio" },
		TasaSpawnPorSegundo = 6.5, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		MultiplicadorVida = 2.2, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
	},
	{
		MinutoInicio = 15, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		MinutoFin = 20, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		EnemigosPermitidos = { "EspectroMenor", "AcechadorRapido", "GolemSombrio" },
		TasaSpawnPorSegundo = 8.0, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		MultiplicadorVida = 3.0, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
	},
	{
		MinutoInicio = 20, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		MinutoFin = 25, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		EnemigosPermitidos = { "EspectroMenor", "AcechadorRapido", "GolemSombrio" },
		TasaSpawnPorSegundo = 10.0, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		MultiplicadorVida = 4.0, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
	},
	{
		MinutoInicio = 25, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		MinutoFin = 30, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		EnemigosPermitidos = { "AcechadorRapido", "GolemSombrio" },
		TasaSpawnPorSegundo = 12.0, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		MultiplicadorVida = 5.5, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
	},
}

return OleadasConfig
