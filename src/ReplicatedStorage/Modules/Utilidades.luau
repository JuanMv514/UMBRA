--!strict
-- Utilidades.luau
-- Funciones utilitarias y cálculos compartidos entre Servidor y Cliente.

local Utilidades = {}

-- Da formato abreviado a números (ej. 1500 -> "1.5K", 2000000 -> "2.0M")
function Utilidades.FormatearNumero(numero: number): string
	if numero >= 1_000_000 then
		return string.format("%.1fM", numero / 1_000_000)
	elseif numero >= 1_000 then
		return string.format("%.1fK", numero / 1_000)
	end
	return tostring(math.floor(numero))
end

-- Calcula distancia euclidiana en el plano X-Z (ignorando elevación Y)
function Utilidades.DistanciaXZ(posA: Vector3, posB: Vector3): number
	local dx = posA.X - posB.X
	local dz = posA.Z - posB.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Espera segura sin advertencias infinitas
function Utilidades.EsperarHijo(padre: Instance, nombre: string, timeout: number?): Instance?
	return padre:WaitForChild(nombre, timeout or 5)
end

return Utilidades
