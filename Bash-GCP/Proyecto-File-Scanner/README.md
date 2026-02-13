# 🔒 Proyecto File Scanner - Secret Detection Suite

Herramienta automatizada para detectar y reportar valores críticos expuestos en repositorios.

## ⚡ Uso Rápido

```bash
cd /home/admin/Documents/GNP/Proyecto-File-Scanner

# Escanear archivo individual
make scan URL="https://gitlab.com/grupo/repo/-/blob/branch/path/.env"

# Escanear repositorio completo
make scan-repo URL="https://github.com/usuario/repo.git"

# Generar reporte HTML
make report JSON=scan.json HTML=reporte.html

# Ver ayuda
make help
```

## 🔍 Qué Detecta

- 🔴 **CRÍTICO**: Claves privadas, credenciales GCP, DB, API Keys custom
- 🟠 **ALTO**: Tokens, JWT, API Keys genéricas
- 🟡 **MEDIO**: Contraseñas, claves de encriptación

## 📋 Características

✅ Acceso a repositorios GitLab SAML via API  
✅ Generación de reportes JSON y HTML  
✅ Deduplicación de hallazgos  
✅ Token automático desde archivo  
✅ Uso via Make o línea de comandos

## 📂 Estructura

```
Proyecto-File-Scanner/
├── bin/
│   ├── detect-secrets.py      # Motor de detección
│   ├── generate-report.py     # Generador de reportes
│   └── secret-scanner.sh      # Script auxiliar
├── Makefile                   # Orquestación
└── README.md                  # Este archivo
```

## 🛠️ Targets del Makefile

| Target | Uso |
|--------|-----|
| `make scan URL=...` | Escanear archivo o repositorio |
| `make scan-repo URL=...` | Forzar escaneo de repositorio |
| `make report JSON=...` | Generar reporte HTML |
| `make clean` | Limpiar temporales |
| `make install` | Instalar permisos |

## 📝 Ejemplos

**Archivo en GitLab:**
```bash
make scan URL="https://gitlab.com/gitgnp/proyecto/-/blob/main/.env"
```

**Repositorio en GitHub:**
```bash
make scan-repo URL="https://github.com/usuario/repo.git"
```

**Con reporte personalizado:**
```bash
make scan URL="..." && make report JSON=security-scan-report.json HTML=mi-reporte.html
```

---

**Versión:** 1.0  
**Última actualización:** 2025-12-02
