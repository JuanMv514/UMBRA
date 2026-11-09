--!strict
-- EnemigosConfig.luau
-- Definición de estadísticas y tipos de horda para UMBRA.

export type EnemigoDef = {
	Id: string,
	Nombre: string,
	VidaBase: number,
	VelocidadBase: number,
	DanioBase: number,
	XpOtorga: number,
	Color: Color3,
	Tamanio: Vector3,
}

local EnemigosConfig: { [string]: EnemigoDef } = {
	EspectroMenor = {
		Id = "EspectroMenor",
		Nombre = "Espectro Menor",
		VidaBase = 30,
		VelocidadBase = 12,
		DanioBase = 8,
		XpOtorga = 5,
		Color = Color3.fromRGB(120, 50, 180),
		Tamanio = Vector3.new(2, 3, 2),
	},
	AcechadorRapido = {
		Id = "AcechadorRapido",
		Nombre = "Acechador Rápido",
		VidaBase = 20,
		VelocidadBase = 18,
		DanioBase = 5,
		XpOtorga = 8,
		Color = Color3.fromRGB(200, 30, 80),
		Tamanio = Vector3.new(1.8, 2, 1.8),
	},
	GolemSombrío = {
		Id = "GolemSombrío",
		Nombre = "Golem Sombrío",
		VidaBase = 150,
		VelocidadBase = 7,
		DanioBase = 20,
		XpOtorga = 25,
		Color = Color3.fromRGB(40, 40, 50),
		Tamanio = Vector3.new(4, 5, 4),
	},
}

return EnemigosConfig
