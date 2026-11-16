--!strict
-- TiposAlpha.luau
-- Contratos y tipos estrictos compartidos para el Alcance Alpha v1.0 de UMBRA: La última luz.

export type EstadoPartida =
	"Waiting"
	| "Starting"
	| "Playing"
	| "Victory"
	| "GameOver"
	| "ReturningToLobby"

export type EstadoJugador =
	"Alive"
	| "Dead"
	| "Spectating"
	| "Disconnected"
	| "ReturningToLobby"
	| "Returned"

export type ModoExpedicion = "Solo" | "Coop"

export type EstadoRelojExpedicion = {
	TiempoLogicoSegundos: number,
	DuracionObjetivoSegundos: number,
	MultiplicadorTiempo: number,
	ModoAceleradoActivo: boolean,
	OleadaActual: number?,
	EnemigosActivosCount: number?,
}

-- Sección 3: Información pública de sala / emparejamiento cooperativo
export type EstadoParticipanteSala = "Conectado" | "Ausente"

export type ParticipanteSalaInfo = {
	UserId: number,
	Nombre: string,
	EsResponsable: boolean,
	Estado: EstadoParticipanteSala,
	OrdenLlegada: number,
}

export type EstadoSalaCooperativa = {
	SalaId: string,
	ResponsableUserId: number,
	PlazasOcupadas: number,
	CapacidadMaxima: number,
	Cerrada: boolean,
	IniciandoExpedicion: boolean,
	Participantes: { ParticipanteSalaInfo },
	MensajeAlerta: string?,
}

export type AccionLobby =
	"IniciarIndividual"
	| "BuscarCoop"
	| "IniciarExpedicionSala"
	| "AbandonarSala"

export type SalaPublicaInfo = {
	Id: string,
	Nombre: string,
	JugadoresActuales: number,
	CapacidadMaxima: number,
	CuentaActiva: boolean,
	CuentaAtrasSegundos: number,
}

-- Sección 7: Magia y habilidades del jugador
export type MagiaJugador = {
	Id: string,
	Nombre: string,
	Nivel: number,
	DanioBase: number,
	Cooldown: number,
	Rango: number?,
}

-- Sección 7: Atributos base y escalables del superviviente
export type AtributosJugador = {
	SaludActual: number,
	SaludMaxima: number,
	VelocidadMovimiento: number,
	PoderMagico: number,
	Armadura: number,
	RadioRecoleccion: number,
	Nivel: number,
	ExperienciaActual: number,
	ExperienciaSiguienteNivel: number,
}

-- Sección 10: Orbes de experiencia / esencia en el campo
export type TipoOrbe = "XP" | "Salud" | "Luz"
export type CategoriaOrbeId = "Menor" | "Medio" | "Mayor"
export type AccionOrbeCliente = "Crear" | "Eliminar" | "LimpiarTodos"

export type OrbeInstancia = {
	Id: string,
	Tipo: TipoOrbe,
	Valor: number,
	Posicion: Vector3,
	TiempoCreacion: number,
}

export type OrbeSincronizado = {
	Id: string,
	Categoria: CategoriaOrbeId,
	ValorXp: number,
	Posicion: Vector3,
	TiempoExpiracion: number,
}

-- Secciones 6 y 10: Progresión, niveles y selección de mejoras
export type TipoAlternativaMejora = "MagiaNueva" | "MagiaMejora" | "Atributo"

export type OpcionMejora = {
	IdOpcion: string,
	Tipo: TipoAlternativaMejora,
	ReferenciaId: string,
	Titulo: string,
	Descripcion: string,
	NivelActual: number,
	NivelSiguiente: number,
}

export type EstadoProgresionJugador = {
	Nivel: number,
	XpActual: number,
	XpRequerida: number,
	SeleccionesPendientes: number,
	OpcionesActuales: { OpcionMejora }?,
}

-- Secciones 7, 11 y 14: Ranuras de magia en HUD y telemetría de daño
export type RanuraMagiaHUD = {
	Orden: number,
	Id: string,
	Nombre: string,
	Nivel: number,
	MaxNivel: number,
	Color: Color3,
}

export type EstadoMagiasJugador = {
	MaxRanuras: number,
	RanurasOcupadas: number,
	Magias: { RanuraMagiaHUD },
}

export type EstadisticasMagiaResultado = {
	Id: string,
	Nombre: string,
	NivelFinal: number,
	DanioCausado: number,
}

-- Secciones 9 y 11: Estado de la barra de vida del Jefe Final en el HUD
export type EstadoJefeHUD = {
	Activo: boolean,
	Nombre: string,
	VidaActual: number,
	VidaMax: number,
}

-- Sección 12: Datos de cada integrante en el modo espectador cooperativo
export type MiembroEquipoEspectador = {
	UserId: number,
	Name: string,
	Vivo: boolean,
	Estado: EstadoJugador,
	Nivel: number,
	SaludActual: number,
	SaludMaxima: number,
}

-- Sección 13: Estado de reconexión en el Lobby
export type DatosReconexionLobby = {
	Disponible: boolean,
	SegundosRestantes: number,
	ModoExpedicion: ModoExpedicion?,
}

-- Sección 14: Reporte individual completo de finalización de expedición
export type ResultadosExpedicionIndividual = {
	Resultado: "VICTORIA" | "DERROTA",
	TiempoSobrevividoSegundos: number,
	NivelAlcanzado: number,
	EnemigosDerrotados: number,
	JefesDerrotados: number,
	OroObtenido: number,
	GemasObtenidas: number,
	DanioTotalCausado: number,
	MagiasUtilizadas: { EstadisticasMagiaResultado },
}

-- Sección 14: Resumen de resultados al finalizar una expedición
export type ResumenResultadosJugador = {
	UserId: number,
	Nombre: string,
	TiempoSobrevividoSegundos: number,
	EnemigosDerrotados: number,
	NivelAlcanzado: number,
	DanioInfligido: number,
	EstadoFinal: EstadoJugador,
}

-- Sección 15: Comandos de desarrollo autorizados
export type AccionComandoDev = "AlternarVelocidad" | "SaltarTiempo"

return {}
