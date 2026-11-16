--!strict
-- JefeConfig.luau
-- Configuración del Jefe Final del minuto 30 en UMBRA: La Última Luz (Sección 9).

local JefeConfig = {
	Id = "HeraldoDelVacio",
	Nombre = "Heraldo del Vacío",
	MinutoAparicionSegundos = 1800, -- 30 minutos lógicos [PENDIENTE DE BALANCE - SECCIÓN 18]
	FactorSpawnHordaDuranteJefe = 0.25, -- Reduce el spawn de enemigos comunes al 25% [PENDIENTE DE BALANCE - SECCIÓN 18]

	VidaBase = 3500, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
	EscaladoVidaPorJugadorExtra = 0.45, -- +45% de vida por cada jugador extra en cooperativo [PENDIENTE DE BALANCE - SECCIÓN 18]
	VelocidadBase = 10.5, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
	DanioContacto = 18, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
	Tamanio = Vector3.new(6.5, 9, 6.5),
	Color = Color3.fromRGB(95, 15, 160),
	ResistenciaRalentizacion = 0.5, -- Las ralentizaciones le afectan a la mitad [PENDIENTE DE BALANCE - SECCIÓN 18]

	EnfriamientoEntrePatrones = 2.5, -- [PENDIENTE DE BALANCE - SECCIÓN 18]

	Patrones = {
		CuerpoACuerpo = {
			Radio = 13, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			TiempoTelegrafo = 1.0, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			Danio = 28, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		},
		ADistancia = {
			CantidadOrbes = 3, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			AnguloDispersionGrados = 22, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			TiempoTelegrafo = 0.9, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			VelocidadProyectil = 48, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			Alcance = 65, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			Danio = 22, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		},
		AtaqueArea = {
			CantidadZonas = 3, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			RadioZona = 11, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			TiempoTelegrafo = 1.5, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			Danio = 35, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
		},
	},
}

return JefeConfig
