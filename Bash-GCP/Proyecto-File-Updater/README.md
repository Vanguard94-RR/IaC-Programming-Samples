# GNP File Promotion

Promociona archivos entre repositorios GitLab automáticamente.

## Instalación

```bash
make install
```

## Configuración

```bash
make setup
# Pega URL origen y destino de GitLab
```

## Uso

```bash
# Test (sin cambios)
make promote-dry

# Ejecutar
make promote

# Ver logs
make logs
```

## Token

Guardar token en: `/home/admin/Documents/GNP/PersonalGitLabToken`

```bash
echo "tu-token" > ../PersonalGitLabToken
chmod 600 ../PersonalGitLabToken
```

## Resultado

- `promotion.log` - Logs de ejecución
- `promotion-report.json` - Reporte con status

**Idempotent**: Segunda ejecución skippea archivos sin cambios.
