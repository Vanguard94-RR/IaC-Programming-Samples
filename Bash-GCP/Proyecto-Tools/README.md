# Proyecto-Tools

Herramienta ligera para instalar alias/funciones de shell que apuntan a scripts.

Objetivo

- Proveer `make install` y `make uninstall` para registrar funciones/alias en el shell de forma idempotente.

Instalación rápida

1. Desde la raíz del repo:

```bash
cd /home/admin/Documents/GNP/Proyecto-Tools
make install
```

2. Cierra y abre tu terminal (o ejecuta `source ~/.bashrc`).

Uso

- Edita `tools/aliases.conf` para añadir líneas con el formato `name=/absolute/or/relative/path/to/script`.
- Si la ruta es relativa, `make install` instalará el script en `~/.gnp-tools/bin` y creará una función que lo invoque.
 - Si la ruta es relativa, `make install` instalará el script en `~/.gnp-tools/bin` y creará una función que lo invoque.
 - Alternativamente (recomendado): coloca ejecutables en `Proyecto-Tools/bin/` — todos los archivos ejecutables dentro de esa carpeta serán instalados automáticamente y se generará un alias con el nombre del fichero (se elimina la extensión `.sh` si existe).

Notas

- Diseñado para ser idempotente: puedes ejecutar `make install` varias veces sin duplicar líneas en tus rc files. Antes de modificar cualquier archivo de configuración personal el instalador crea una copia de seguridad (`~/.bashrc.proyecto_tools.bak`, `~/.profile.proyecto_tools.bak`, etc.).

- Soporta bash y zsh (detecta `zsh` y añadirá la carga en `~/.zshrc` si procede).

- Si quieres que las aliases se activen automáticamente en tu sesión actual, ejecuta el instalador con `source`:

```bash
# desde el proyecto
source ./install.sh
```

Si ejecutas `./install.sh` o `make install` el instalador abrirá una nueva shell interactiva (si es posible) para que los cambios se apliquen, o te mostrará el comando `source ~/.gnp-tools/aliases.sh` si prefieres activar manualmente las aliases.

- En Google Cloud Shell tu home puede ser `/home/juan_cortes`; el instalador usa `$HOME` para el destino y por eso es portable.

Idempotencia y seguridad

- El archivo `aliases.sh` se escribe de forma atómica (se crea un fichero temporal y luego se mueve), evitando estados parciales.
- Las modificaciones a archivos rc se envuelven entre marcadores para que `make uninstall` pueda eliminarlas de forma limpia.
- `make uninstall` intentará eliminar los scripts instalados y limpiar los bloques añadidos a los rc files.
