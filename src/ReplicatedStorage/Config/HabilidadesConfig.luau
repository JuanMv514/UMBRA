--!strict
-- HabilidadesConfig.luau
-- Catálogo oficial de las 8 magias de la Alpha v1.0 de UMBRA: La Última Luz (Sección 7).

export type TipoMagia =
	"ProyectilDirigido"
	| "AreaPersonaje"
	| "RelampagoCadena"
	| "Orbital"
	| "NovaRalentizadora"
	| "ProyectilPerforante"
	| "ImpactoZona"
	| "ZonaPersistente"

export type HabilidadDef = {
	Id: string,
	Nombre: string,
	Descripcion: string,
	Tipo: TipoMagia,
	EtapaDesbloqueo: number,
	CooldownBase: number,
	DanioBase: number,
	RadioBase: number,
	VelocidadBase: number?,
	MaxNivel: number,
	ColorVisual: Color3,
}

local HabilidadesConfig = {
	EtapaMagiasActiva = 2, -- 1 = primeras 3 magias | 2 = las 8 magias de la Alpha
	MaxRanurasActivas = 6,
	NivelMaximoMagia = 7,

	Catalogo = {
		-- =====================================================================
		-- ETAPA 1 (Primeras 3 magias aprobadas - Sección 7.1)
		-- =====================================================================
		EsferaIgnea = {
			Id = "EsferaIgnea",
			Nombre = "Esfera Ígnea",
			Descripcion = "Dispara automáticamente una esfera de fuego dirigida al enemigo más cercano.",
			Tipo = "ProyectilDirigido",
			EtapaDesbloqueo = 1,
			CooldownBase = 1.4, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			DanioBase = 24, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			RadioBase = 55, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			VelocidadBase = 62, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			MaxNivel = 7,
			ColorVisual = Color3.fromRGB(255, 110, 40),
		},
		AnilloIncineracion = {
			Id = "AnilloIncineracion",
			Nombre = "Anillo de Incineración",
			Descripcion = "Libera un pulso ardiente alrededor del personaje que daña a todos los enemigos en su radio.",
			Tipo = "AreaPersonaje",
			EtapaDesbloqueo = 1,
			CooldownBase = 1.6, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			DanioBase = 16, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			RadioBase = 15, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			MaxNivel = 7,
			ColorVisual = Color3.fromRGB(255, 65, 30),
		},
		DescargaRelampago = {
			Id = "DescargaRelampago",
			Nombre = "Descarga Relámpago",
			Descripcion = "Impacta instantáneamente a un objetivo en rango y salta en cadena a enemigos cercanos.",
			Tipo = "RelampagoCadena",
			EtapaDesbloqueo = 1,
			CooldownBase = 2.0, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			DanioBase = 28, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			RadioBase = 42, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			MaxNivel = 7,
			ColorVisual = Color3.fromRGB(100, 225, 255),
		},

		-- =====================================================================
		-- ETAPA 2 (5 magias restantes hasta completar las 8 - Sección 7.2)
		-- =====================================================================
		OrbesUmbrios = {
			Id = "OrbesUmbrios",
			Nombre = "Orbes Umbríos",
			Descripcion = "Esferas sombrías que orbitan continuamente alrededor del personaje dañando al contacto.",
			Tipo = "Orbital",
			EtapaDesbloqueo = 2,
			CooldownBase = 0.25, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			DanioBase = 14, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			RadioBase = 9.5, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			MaxNivel = 7,
			ColorVisual = Color3.fromRGB(165, 60, 255),
		},
		NovaEscarcha = {
			Id = "NovaEscarcha",
			Nombre = "Nova de Escarcha",
			Descripcion = "Onda expansiva gélida que daña y ralentiza un 35% durante 2.5s a los enemigos alcanzados.",
			Tipo = "NovaRalentizadora",
			EtapaDesbloqueo = 2,
			CooldownBase = 3.2, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			DanioBase = 18, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			RadioBase = 18, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			MaxNivel = 7,
			ColorVisual = Color3.fromRGB(130, 240, 255),
		},
		LanzaAbisal = {
			Id = "LanzaAbisal",
			Nombre = "Lanza Abisal",
			Descripcion = "Proyectil veloz en línea recta que atraviesa y daña a múltiples enemigos en su trayectoria.",
			Tipo = "ProyectilPerforante",
			EtapaDesbloqueo = 2,
			CooldownBase = 2.1, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			DanioBase = 22, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			RadioBase = 58, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			VelocidadBase = 85, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			MaxNivel = 7,
			ColorVisual = Color3.fromRGB(210, 50, 150),
		},
		MeteoritoAstral = {
			Id = "MeteoritoAstral",
			Nombre = "Meteorito Astral",
			Descripcion = "Invoca un impacto astral descendente sobre un enemigo cercano, dañando en área al aterrizar.",
			Tipo = "ImpactoZona",
			EtapaDesbloqueo = 2,
			CooldownBase = 3.5, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			DanioBase = 42, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			RadioBase = 45, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			MaxNivel = 7,
			ColorVisual = Color3.fromRGB(255, 195, 60),
		},
		VorticeVacio = {
			Id = "VorticeVacio",
			Nombre = "Vórtice del Vacío",
			Descripcion = "Crea una grieta oscura persistente en el suelo que inflige daño periódico en su área.",
			Tipo = "ZonaPersistente",
			EtapaDesbloqueo = 2,
			CooldownBase = 4.2, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			DanioBase = 12, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			RadioBase = 40, -- [PENDIENTE DE BALANCE - SECCIÓN 18]
			MaxNivel = 7,
			ColorVisual = Color3.fromRGB(115, 30, 190),
		},
	} :: { [string]: HabilidadDef },
}

return HabilidadesConfig
