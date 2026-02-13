# Proyecto-Tools — Diagrama de flujo

El siguiente diagrama describe el flujo principal del proyecto `Proyecto-Tools`: cómo se definen alias, cómo `make install` los instala de forma idempotente, y cómo `make uninstall` limpia los cambios.

```mermaid
flowchart TD
  subgraph User
    U[User edits `tools/aliases.conf`]
    U2[Runs `make install` or `source ./install.sh`] 
  end

  subgraph Installer[install.sh / Makefile]
    direction TB
    A[Read `tools/aliases.conf`]
    B[Resolve paths (relative → project, absolute kept)]
    C[Copy scripts → PREFIX/bin (e.g. ~/.gnp-tools/bin)]
    D[Create symlinks → ~/.local/bin]
    E[Generate aliases.sh atomically (tmp → mv)]
    F[Insert marked block into rc file (bash/zsh) with backups]
    G[Ensure ~/.local/bin in PATH (idempotent)]
  end

  subgraph Runtime[User shell]
    R1[aliases.sh is sourced via rc block]
    R2[Functions available: alias-name() { /path/to/bin "$@" }]
  end

  subgraph Uninstall[uninstall.sh]
    U_A[Remove aliases.sh & aliases.conf]
    U_B[Remove binaries in PREFIX/bin]
    U_C[Remove symlinks in ~/.local/bin]
    U_D[Remove marked block from rc files]
  end

  U --> U2
  U2 --> A --> B --> C --> D --> E --> F --> G
  F --> R1 --> R2
  R2 -->|user runs| U2
  U2 -->|if uninstall| Uninstall
  Uninstall --> U_A --> U_B --> U_C --> U_D

  classDef infra fill:#f9f,stroke:#333,stroke-width:1px;
  class Installer,Uninstall infra;

  %% Notes
  click C href "./README.md" "More info in README"
```

Descripción corta
- Idempotencia: las inserciones en los rc files están envueltas en marcadores BEGIN/END y se crean backups antes de modificar.
- Atomicidad: `aliases.sh` se escribe de forma atómica (archivo temporal mv).
- Portabilidad: los scripts referenciados se copian a `PREFIX/bin` y se crean symlinks en `~/.local/bin`, por eso funciona en Cloud Shell (donde $HOME cambia por usuario).

Cómo visualizar
- Abre `ARCHITECTURE.md` en VS Code y usa la extensión Mermaid Preview o Markdown Preview Enhanced para renderizar el diagrama.
