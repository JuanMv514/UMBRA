--!strict
-- HabilidadesConfig.luau
-- Configuración de habilidades activas y pasivas para UMBRA (Roguelite).

export type HabilidadDef = {
	Id: string,
	Nombre: string,
	Descripcion: string,
	Tipo: "Aura" | "Proyectil" | "Orbital" | "Area",
	CooldownBase: number,
	DanioBase: number,
	RadioBase: number,
	VelocidadBase: number?,
	MaxNivel: number,
}

local HabilidadesConfig: { [string]: HabilidadDef } = {
	AuraOscura = {
		Id = "AuraOscura",
		Nombre = "Aura Umbría",
		Descripcion = "Genera un campo de energía oscura que daña periódicamente a los enemigos cercanos.",
		Tipo = "Aura",
		CooldownBase = 1.0,
		DanioBase = 12,
		RadioBase = 14,
		MaxNivel = 5,
	},
	ChispaEspiritual = {
		Id = "ChispaEspiritual",
		Nombre = "Chispa Espiritual",
		Descripcion = "Dispara proyectiles automáticos hacia el enemigo más cercano.",
		Tipo = "Proyectil",
		CooldownBase = 1.8,
		DanioBase = 25,
		RadioBase = 50, -- Rango de detección
		VelocidadBase = 60,
		MaxNivel = 5,
	},
	FragmentoGiratorio = {
		Id = "FragmentoGiratorio",
		Nombre = "Cuchilla Espectral",
		Descripcion = "Fragmentos que orbitan alrededor del jugador repeliendo y cortando enemigos.",
		Tipo = "Orbital",
		CooldownBase = 0.2,
		DanioBase = 8,
		RadioBase = 9,
		MaxNivel = 5,
	},
}

return HabilidadesConfig
