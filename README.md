# UMBRA 🌑
**Videojuego Roguelite de Supervivencia para Roblox**  
Inspirado en el género de *Magic Survival* y *Vampire Survivors*, con mecánicas propias de hordas sombrías, evolución de habilidades y supervivencia progresiva.

---

## 🏗️ Arquitectura del Proyecto

```text
📁 src/
├── 📁 ReplicatedStorage/
│   ├── 📁 Config/                   # Datos puros (Habilidades, Enemigos, Oleadas)
│   └── 📁 Modules/                  # Funciones compartidas (Utilidades, Pooling)
│
├── 📁 ServerScriptService/           # Lógica autoritativa del servidor
│   ├── 📄 ServerMain.server.luau    # Punto de entrada único del servidor
│   └── 📁 Services/                 # Servicios modulares (GameManager, Spawner, Combat)
│
└── 📁 StarterPlayer/
    └── 📁 StarterPlayerScripts/     # Controladores locales del cliente
        ├── 📄 ClientMain.client.luau# Punto de entrada único del cliente
        └── 📁 Controllers/          # Controladores (Input, SpellRenderer, HUD)
```

---

## 🛠️ Herramientas
- **Visual Studio Code** con Antigravity.
- **Roblox Studio** conectado vía protocolo MCP.
- **Git & GitHub**: Control de versiones en `https://github.com/JuanMv514/UMBRA`.
