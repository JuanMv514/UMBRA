--!strict
-- AtributosConfig.luau
-- Configuración de regeneración pasiva base y los 4 atributos mejorables por nivel (Sección 6).

export type AtributoMejorableDef = {
	Id: string,
	Nombre: string,
	Descripcion: string,
	PorcentajePorNivel: number,
	MaxSelecciones: number,
}

local AtributosConfig = {
	-- Regeneración automática de vida muy baja (no mejorable mediante atributos)
	RegeneracionVidaPasivaPorSegundo = 0.5, -- [PENDIENTE DE BALANCE - SECCIÓN 18]

	AtributosMejorables = {
		VidaMaxima = {
			Id = "VidaMaxima",
			Nombre = "Vitalidad del Alba",
			Descripcion = "+10% de Vida Máxima actual y restaura la diferencia añadida.",
			PorcentajePorNivel = 0.10, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			MaxSelecciones = 10, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		},
		VelocidadMovimiento = {
			Id = "VelocidadMovimiento",
			Nombre = "Paso Etéreo",
			Descripcion = "+6% de Velocidad de Movimiento actual.",
			PorcentajePorNivel = 0.06, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			MaxSelecciones = 8, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		},
		PoderMagico = {
			Id = "PoderMagico",
			Nombre = "Resplandor Arcano",
			Descripcion = "+8% de Poder Mágico actual en todas tus magias.",
			PorcentajePorNivel = 0.08, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			MaxSelecciones = 10, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		},
		ReduccionCooldown = {
			Id = "ReduccionCooldown",
			Nombre = "Flujo Acelerado",
			Descripcion = "+5% de reducción de enfriamiento actual en tus magias.",
			PorcentajePorNivel = 0.05, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			MaxSelecciones = 8, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		},
	} :: { [string]: AtributoMejorableDef },
}

return AtributosConfig
