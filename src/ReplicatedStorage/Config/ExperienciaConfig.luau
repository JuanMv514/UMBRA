--!strict
-- ExperienciaConfig.luau
-- Configuración de experiencia, niveles, categorías de orbes y probabilidades de drop (Sección 10).

export type CategoriaOrbeDef = {
	MultiplicadorValor: number,
	TiempoVidaSegundos: number,
	Color: Color3,
	Tamanio: Vector3,
}

export type PesosOrbe = {
	Menor: number,
	Medio: number,
	Mayor: number,
}

local ExperienciaConfig = {
	NivelMaximoJugador = 100, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
	RatioXpDirectaMuerte = 0.5, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
	RatioXpOrbe = 0.5, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
	RadioRecogidaDirectaStuds = 3.5, -- [PENDIENTE DE BALANCE - SECCIÓN 18] (sin atracción magnética automática)

	CategoriasOrbe = {
		Menor = {
			MultiplicadorValor = 1.0, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			TiempoVidaSegundos = 25, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			Color = Color3.fromRGB(70, 190, 255),
			Tamanio = Vector3.new(1.1, 1.1, 1.1),
		},
		Medio = {
			MultiplicadorValor = 2.0, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			TiempoVidaSegundos = 40, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			Color = Color3.fromRGB(175, 70, 255),
			Tamanio = Vector3.new(1.4, 1.4, 1.4),
		},
		Mayor = {
			MultiplicadorValor = 4.0, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			TiempoVidaSegundos = 60, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			Color = Color3.fromRGB(255, 205, 65),
			Tamanio = Vector3.new(1.75, 1.75, 1.75),
		},
	} :: { [string]: CategoriaOrbeDef },

	PesosOrbePorEnemigo = {
		EspectroMenor = { Menor = 85, Medio = 13, Mayor = 2 }, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		AcechadorRapido = { Menor = 35, Medio = 55, Mayor = 10 }, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		GolemSombrio = { Menor = 10, Medio = 45, Mayor = 45 }, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
	} :: { [string]: PesosOrbe },
}

-- Calcula la experiencia requerida para avanzar desde nivelActual hacia nivelActual + 1
function ExperienciaConfig.CalcularXpParaNivel(nivelActual: number): number
	local nivelSeguro = math.max(1, nivelActual)
	return math.floor(25 * (nivelSeguro ^ 1.35)) -- [PENDIENTE DE BALANCE - SECCIÓN 18]
end

return ExperienciaConfig
