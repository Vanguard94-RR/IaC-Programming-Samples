#!/bin/bash

################################################################################
# Workflow Deployment - Fixes & Recommendations
################################################################################
# Script de reparación y guía de uso correcto
#
# Autor: GNP Infrastructure Team
################################################################################

# COLOR CODES
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
LGREEN='\033[1;32m'
LCYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ============================================================================
# ISSUE 1: Fix GCloud Authentication in Non-Interactive Mode
# ============================================================================
fix_gcloud_authentication() {
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════════════════╗
║ SOLUCIÓN 1: Autenticación gcloud en Modo No-Interactivo                   ║
╚════════════════════════════════════════════════════════════════════════════╝

PROBLEMA:
  ERROR: Reauthentication failed. cannot prompt during non-interactive execution.

CAUSA:
  - Las credenciales de gcloud han expirado
  - No se pueden re-autenticar en scripts no-interactivos

SOLUCIÓN RECOMENDADA: Usar Service Account (Para CI/CD)
────────────────────────────────────────────────────────

Paso 1: Crear Service Account
  $ gcloud iam service-accounts create workflow-deployer \
      --display-name="Workflow Deployment Service Account"

Paso 2: Otorgar permisos (workflows.admin)
  $ gcloud projects add-iam-policy-binding gnp-wf-danios-qa \
      --member="serviceAccount:workflow-deployer@gnp-wf-danios-qa.iam.gserviceaccount.com" \
      --role="roles/workflows.admin"

Paso 3: Crear clave JSON
  $ gcloud iam service-accounts keys create workflow-key.json \
      --iam-account=workflow-deployer@gnp-wf-danios-qa.iam.gserviceaccount.com

Paso 4: Usar en scripts
  export GOOGLE_APPLICATION_CREDENTIALS=/path/to/workflow-key.json
  gcloud workflows deploy --quiet ...

ALTERNATIVA: Reautenticar (Para desarrollo local)
─────────────────────────────────────────────────

  $ gcloud auth login
  $ gcloud auth application-default login
  $ gcloud config set project gnp-wf-danios-qa

VERIFICACIÓN:
────────────
  $ gcloud auth list                    # Ver cuentas autenticadas
  $ gcloud config get-value account     # Ver cuenta activa
  $ gcloud config get-value project     # Ver proyecto activo

EOF
}

# ============================================================================
# ISSUE 2: Complete the Bash Script
# ============================================================================
fix_bash_script_completion() {
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════════════════╗
║ SOLUCIÓN 2: Completar el Script Bash                                      ║
╚════════════════════════════════════════════════════════════════════════════╝

PROBLEMA:
  - workflow-deploy-interactive.sh está truncado (incompleto)
  - Faltan funciones al final
  - El script termina en medio de la función main()

ESTADO:
  ✗ Línea ~430: Falta el cierre de la función main()
  ✗ Falta la siguiente línea:
      }
      
      main "$@"

SOLUCIÓN: Añadir estas líneas al final del archivo
──────────────────────────────────────────────────

Abre: workflow-deploy-interactive.sh
Ir al final del archivo
Añade:

    }
}

# Llamar a la función principal
main "$@"

VERIFICACIÓN:
────────────
  $ bash -n workflow-deploy-interactive.sh    # Verificar sintaxis
  $ chmod +x workflow-deploy-interactive.sh   # Hacer ejecutable

EOF
}

# ============================================================================
# ISSUE 3: Verify GitLab File Paths
# ============================================================================
fix_gitlab_file_paths() {
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════════════════╗
║ SOLUCIÓN 3: Verificar Rutas en GitLab                                     ║
╚════════════════════════════════════════════════════════════════════════════╝

PROBLEMA:
  ERROR: Archivo no encontrado: gnp-danios-wf/GoogleWF/workflow-emision-danios.yml
         (rama: feature-paquete2-WF)

CAUSA:
  - La rama feature-paquete2-WF NO contiene el archivo en esa ruta
  - O la ruta exacta es diferente

CÓMO VERIFICAR:
───────────────

Opción 1: Acceso directo a GitLab
  $ curl -H "PRIVATE-TOKEN: $(cat PersonalGitLabToken)" \
    "https://gitlab.com/api/v4/projects/gitnp%2Fcotizadores%2Fgke-gnp-danios-config-back-end/repository/tree?ref=feature-paquete2-WF"

Opción 2: Clonar la rama y verificar
  $ git clone -b feature-paquete2-WF \
    https://gitlab.com/gitnp/cotizadores/gke-gnp-danios-config-back-end.git
  $ ls -la gnp-danios-wf/GoogleWF/

SOLUCIONES:
───────────

1. Usar rama principal (si existe en main)
   URL: https://gitlab.com/gitnp/cotizadores/gke-gnp-danios-config-back-end/
        -/blob/main/gnp-danios-wf/GoogleWF/workflow-emision-danios.yml

2. Encontrar la ruta correcta
   $ git branch -a
   $ find . -name "*workflow-emision*"

3. Crear el archivo en la rama
   git checkout feature-paquete2-WF
   mkdir -p gnp-danios-wf/GoogleWF
   cp workflow-emision-danios.yml gnp-danios-wf/GoogleWF/
   git add .
   git commit -m "Add workflow file"
   git push origin feature-paquete2-WF

EOF
}

# ============================================================================
# ISSUE 4: GitLab Token Validation
# ============================================================================
fix_gitlab_token() {
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════════════════╗
║ SOLUCIÓN 4: Validar Token de GitLab                                       ║
╚════════════════════════════════════════════════════════════════════════════╝

PROBLEMA:
  WARNING: El token parece muy corto, podría ser inválido

CAUSA:
  - Token incompleto o vacío en PersonalGitLabToken
  - Token expirado

CÓMO VERIFICAR:
───────────────
  $ cat PersonalGitLabToken
  $ wc -c PersonalGitLabToken    # Debe tener >20 caracteres

  # Probar autenticación
  $ curl -H "PRIVATE-TOKEN: $(cat PersonalGitLabToken)" \
    https://gitlab.com/api/v4/user

CREAR NUEVO TOKEN:
──────────────────
1. Ir a: https://gitlab.com/-/user_settings/personal_access_tokens
2. Crear nuevo token con:
   - Nombre: "GNP Workflow Deployment"
   - Scopes: read_repository, read_api
   - Expiración: 1 año

3. Guardar en PersonalGitLabToken:
   $ echo "glpat-xxxxxxxxxxxxxxxxxx" > PersonalGitLabToken
   $ chmod 600 PersonalGitLabToken

4. Verificar:
   $ curl -H "PRIVATE-TOKEN: $(cat PersonalGitLabToken)" \
     https://gitlab.com/api/v4/user | grep username

EOF
}

# ============================================================================
# RECOMMENDATION 1: Use Python Instead of Bash
# ============================================================================
recommendation_use_python() {
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════════════════╗
║ RECOMENDACIÓN 1: Usar workflow-deploy.py en Lugar de Bash                 ║
╚════════════════════════════════════════════════════════════════════════════╝

¿POR QUÉ?
─────────
✓ Mejor manejo de errores
✓ Validación YAML más robusta
✓ Token más seguro (en headers, no en CLI)
✓ Logging estructurado
✓ Better integration with CI/CD

USO BÁSICO:
───────────

  python3 workflow-deploy.py \
    --url "https://gitlab.com/gitnp/cotizadores/gke-gnp-danios-config-back-end/-/blob/main/gnp-danios-wf/GoogleWF/workflow-emision-danios.yml" \
    --name workflow-emision-danios \
    --project gnp-wf-danios-qa \
    --location us-central1

MODO DRY-RUN (Sin desplegar):
──────────────────────────────

  python3 workflow-deploy.py \
    --url "https://gitlab.com/..." \
    --name workflow-emision-danios \
    --project gnp-wf-danios-qa \
    --dry-run

VERIFICAR AYUDA:
────────────────

  python3 workflow-deploy.py --help

EOF
}

# ============================================================================
# RECOMMENDATION 2: Use Diagnostics Script
# ============================================================================
recommendation_use_diagnostics() {
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════════════════╗
║ RECOMENDACIÓN 2: Usar diagnostics.sh Para Verificación                    ║
╚════════════════════════════════════════════════════════════════════════════╝

VERIFICAR SISTEMA:
──────────────────

  chmod +x diagnostics.sh
  ./diagnostics.sh

ESTO VERIFICARÁ:
────────────────
✓ Autenticación gcloud
✓ Token de GitLab
✓ Archivos en GitLab
✓ Permisos en GCP
✓ Integridad de scripts
✓ Conectividad de red

RESULTADO:
──────────
- Todos los tests PASS: Sistema listo
- Algún test FAIL: Seguir instrucciones para corregir

EOF
}

# ============================================================================
# STEP-BY-STEP DEPLOYMENT GUIDE
# ============================================================================
deployment_guide() {
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════════════════╗
║ GUÍA PASO A PASO: Desplegar un Workflow                                   ║
╚════════════════════════════════════════════════════════════════════════════╝

PASO 1: Diagnóstico del Sistema
─────────────────────────────────
  $ cd /home/admin/Documents/GNP/Repos/IaC-Programming-Samples/Bash-GCP/Proyecto-Workflow-Deployment
  $ chmod +x diagnostics.sh
  $ ./diagnostics.sh
  
  ✓ Si todos los tests PASS → Continuar con PASO 2
  ✗ Si algún test FALLA → Corregir según las soluciones arriba

PASO 2: Verificar Archivo en GitLab
────────────────────────────────────
  $ curl -H "PRIVATE-TOKEN: $(cat PersonalGitLabToken)" \
    "https://gitlab.com/api/v4/projects/gitnp%2Fcotizadores%2Fgke-gnp-danios-config-back-end/repository/files/gnp-danios-wf%2FGoogleWF%2Fworkflow-emision-danios.yml/raw?ref=main" \
    | head -10

  ✓ Si muestra contenido YAML → Continuar
  ✗ Si ERROR 404 → Verificar ruta en GitLab

PASO 3: Dry-Run (Simulación sin Desplegar)
────────────────────────────────────────────
  $ python3 workflow-deploy.py \
    --url "https://gitlab.com/gitnp/cotizadores/gke-gnp-danios-config-back-end/-/blob/main/gnp-danios-wf/GoogleWF/workflow-emision-danios.yml" \
    --name workflow-emision-danios \
    --project gnp-wf-danios-qa \
    --location us-central1 \
    --dry-run

  ✓ Si muestra comando sin ejecutar → OK
  ✗ Si hay errores → Revisar logs

PASO 4: Despliegue Real
───────────────────────
  $ python3 workflow-deploy.py \
    --url "https://gitlab.com/gitnp/cotizadores/gke-gnp-danios-config-back-end/-/blob/main/gnp-danios-wf/GoogleWF/workflow-emision-danios.yml" \
    --name workflow-emision-danios \
    --project gnp-wf-danios-qa \
    --location us-central1

  ✓ Si muestra "✓ Despliegue exitoso" → Completado
  ✗ Si error → Revisar logs en workflow.log

PASO 5: Verificación
──────────────────────
  $ gcloud workflows list --project=gnp-wf-danios-qa
  $ gcloud workflows describe workflow-emision-danios \
    --project=gnp-wf-danios-qa \
    --location=us-central1

LOGS:
──────
  $ tail -50 workflow.log          # Logs recientes
  $ cat deployment_history.log     # Historial de despliegues

EOF
}

# ============================================================================
# Main Menu
# ============================================================================
main() {
    clear
    
    echo -e "\n${LCYAN}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${LCYAN}║${NC} ${WHITE}Workflow Deployment - Fixes & Recommendations${NC}$(printf ' %.0s' {1..22})${LCYAN}║${NC}"
    echo -e "${LCYAN}╚════════════════════════════════════════════════════════════════════════════╝${NC}\n"
    
    while true; do
        cat << 'MENU'
Selecciona una opción:

1) Solución 1: Autenticación gcloud
2) Solución 2: Completar script bash
3) Solución 3: Verificar rutas en GitLab
4) Solución 4: Validar token GitLab
5) Recomendación 1: Usar Python
6) Recomendación 2: Usar diagnostics.sh
7) Guía paso a paso de despliegue
0) Salir

MENU
        
        read -p "Opción [0-7]: " option
        
        case "$option" in
            1) fix_gcloud_authentication | less ;;
            2) fix_bash_script_completion | less ;;
            3) fix_gitlab_file_paths | less ;;
            4) fix_gitlab_token | less ;;
            5) recommendation_use_python | less ;;
            6) recommendation_use_diagnostics | less ;;
            7) deployment_guide | less ;;
            0) break ;;
            *) echo "Opción inválida"; sleep 1 ;;
        esac
        
        clear
    done
    
    echo -e "\n${LGREEN}✓ Gracias por usar Workflow Deployment Fixer${NC}\n"
}

main
