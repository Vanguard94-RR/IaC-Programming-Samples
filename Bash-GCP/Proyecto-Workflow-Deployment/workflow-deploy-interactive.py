#!/usr/bin/env python3
"""
Workflow Deployment - Interactive Mode
========================================
Interfaz amigable e interactiva para desplegar workflows desde GitLab a GCP.

Características:
- Entrada paso a paso
- Validación en tiempo real
- Preview visual antes de desplegar
- Opción de volver atrás
- Historial de despliegues

Uso:
    python3 workflow-deploy-interactive.py

Autor: GNP Infrastructure Team
"""

import sys
import os
from pathlib import Path

# Agregar directorio actual al path para importar workflow-deploy
sys.path.insert(0, str(Path(__file__).parent))

def clear_screen():
    """Limpia la pantalla."""
    os.system('clear' if os.name == 'posix' else 'cls')

class Colors:
    """Códigos ANSI para colores."""
    HEADER = '\033[95m'
    CYAN = '\033[96m'
    BLUE = '\033[94m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    WHITE = '\033[1;37m'
    GRAY = '\033[90m'
    NC = '\033[0m'  # No Color

def print_header(title: str):
    """Imprime un encabezado formateado."""
    width = 70
    print(f"\n{Colors.CYAN}{'═' * width}{Colors.NC}")
    print(f"{Colors.CYAN}║{Colors.NC} {Colors.WHITE}{title.center(width-2)}{Colors.NC} {Colors.CYAN}║{Colors.NC}")
    print(f"{Colors.CYAN}{'═' * width}{Colors.NC}\n")

def print_menu(options: dict, title: str = "Selecciona una opción"):
    """Imprime un menú formateado."""
    print(f"{Colors.YELLOW}{title}{Colors.NC}")
    print(f"{Colors.GRAY}{'─' * 60}{Colors.NC}")
    for key, value in options.items():
        print(f"  {Colors.CYAN}{key}){Colors.NC} {value}")
    print()

def get_input(prompt: str, default: str = None, validate_func=None) -> str:
    """Obtiene entrada del usuario con validación opcional."""
    while True:
        if default:
            msg = f"{Colors.YELLOW}{prompt}{Colors.NC} [{Colors.GRAY}{default}{Colors.NC}]: "
        else:
            msg = f"{Colors.YELLOW}{prompt}{Colors.NC}: "
        
        user_input = input(msg).strip()
        
        if not user_input and default:
            return default
        
        if not user_input:
            print(f"{Colors.RED}✗ Campo requerido{Colors.NC}")
            continue
        
        if validate_func and not validate_func(user_input):
            print(f"{Colors.RED}✗ Entrada inválida{Colors.NC}")
            continue
        
        return user_input

def validate_url(url: str) -> bool:
    """Valida que sea una URL de GitLab válida."""
    return "gitlab.com" in url and "/-/blob/" in url

def validate_project_id(project_id: str) -> bool:
    """Valida el formato del project ID de GCP."""
    return len(project_id) > 0 and all(c.isalnum() or c == '-' for c in project_id)

def validate_workflow_name(name: str) -> bool:
    """Valida el nombre del workflow."""
    return len(name) > 0 and all(c.isalnum() or c == '-' for c in name)

def step_1_gitlab_source() -> dict:
    """Paso 1: Obtener información de GitLab."""
    print_header("Paso 1: Fuente de GitLab")
    
    print(f"{Colors.GRAY}¿De dónde descargar el workflow?{Colors.NC}\n")
    
    options = {
        "1": "Ingresar URL completa de GitLab",
        "2": "Ingresar detalles por separado (proyecto, rama, archivo)",
        "0": "Cancelar"
    }
    
    print_menu(options)
    choice = input(f"{Colors.YELLOW}Opción{Colors.NC}: ").strip()
    
    if choice == "1":
        url = get_input(
            "URL de GitLab",
            validate_func=validate_url
        )
        return {
            "type": "url",
            "url": url
        }
    elif choice == "2":
        project = get_input("Proyecto GitLab (ej: grupo/proyecto)")
        branch = get_input("Rama o tag", "main")
        file_path = get_input("Ruta del archivo (ej: workflows/workflow.yml)")
        return {
            "type": "components",
            "project": project,
            "branch": branch,
            "file_path": file_path
        }
    else:
        return None

def step_2_gcp_target() -> dict:
    """Paso 2: Configuración de destino en GCP."""
    print_header("Paso 2: Destino en Google Cloud")
    
    workflow_name = get_input(
        "Nombre del workflow en GCP",
        validate_func=validate_workflow_name
    )
    
    project_id = get_input(
        "Project ID de GCP",
        validate_func=validate_project_id
    )
    
    location = get_input(
        "Región de GCP",
        "us-central1"
    )
    
    return {
        "workflow_name": workflow_name,
        "project_id": project_id,
        "location": location
    }

def step_3_options() -> dict:
    """Paso 3: Opciones adicionales."""
    print_header("Paso 3: Opciones Adicionales")
    
    options = {
        "1": "Normal - Desplegar después de validar",
        "2": "DRY-RUN - Simular sin desplegar",
        "3": "SKIP-VALIDATION - Omitir validación",
        "0": "Volver"
    }
    
    print_menu(options, "¿Qué modo de despliegue deseas?")
    choice = input(f"{Colors.YELLOW}Opción{Colors.NC}: ").strip()
    
    if choice == "0":
        return None
    
    return {
        "dry_run": choice in ["2"],
        "skip_validation": choice in ["3"]
    }

def step_4_preview(gitlab_source: dict, gcp_target: dict, options: dict) -> bool:
    """Paso 4: Preview y confirmación."""
    print_header("Paso 4: Confirmación")
    
    print(f"{Colors.WHITE}Resumen de la configuración:{Colors.NC}\n")
    
    print(f"{Colors.CYAN}Fuente (GitLab):{Colors.NC}")
    if gitlab_source["type"] == "url":
        print(f"  {Colors.GRAY}URL:{Colors.NC} {gitlab_source['url']}")
    else:
        print(f"  {Colors.GRAY}Proyecto:{Colors.NC} {gitlab_source['project']}")
        print(f"  {Colors.GRAY}Rama/Tag:{Colors.NC} {gitlab_source['branch']}")
        print(f"  {Colors.GRAY}Archivo:{Colors.NC} {gitlab_source['file_path']}")
    
    print(f"\n{Colors.CYAN}Destino (GCP):{Colors.NC}")
    print(f"  {Colors.GRAY}Workflow:{Colors.NC} {gcp_target['workflow_name']}")
    print(f"  {Colors.GRAY}Proyecto:{Colors.NC} {gcp_target['project_id']}")
    print(f"  {Colors.GRAY}Región:{Colors.NC} {gcp_target['location']}")
    
    print(f"\n{Colors.CYAN}Opciones:{Colors.NC}")
    print(f"  {Colors.GRAY}Modo:{Colors.NC} {'🔸 DRY-RUN' if options['dry_run'] else '✓ Normal'}")
    print(f"  {Colors.GRAY}Validación:{Colors.NC} {'Omitida' if options['skip_validation'] else 'Habilitada'}")
    
    print()
    options_menu = {
        "1": "Continuar con el despliegue",
        "2": "Volver al paso anterior",
        "0": "Cancelar todo"
    }
    
    print_menu(options_menu, "¿Qué deseas hacer?")
    choice = input(f"{Colors.YELLOW}Opción{Colors.NC}: ").strip()
    
    if choice == "1":
        return True
    elif choice == "2":
        return None  # Señal de volver
    else:
        return False  # Cancelar

def build_command(gitlab_source: dict, gcp_target: dict, options: dict) -> str:
    """Construye el comando a ejecutar."""
    cmd_parts = ["python3", "workflow-deploy.py"]
    
    # Fuente GitLab
    if gitlab_source["type"] == "url":
        cmd_parts.append(f"--url '{gitlab_source['url']}'")
    else:
        cmd_parts.append(f"--gitlab-project '{gitlab_source['project']}'")
        cmd_parts.append(f"--branch '{gitlab_source['branch']}'")
        cmd_parts.append(f"--path '{gitlab_source['file_path']}'")
    
    # Destino GCP
    cmd_parts.append(f"--name '{gcp_target['workflow_name']}'")
    cmd_parts.append(f"--project '{gcp_target['project_id']}'")
    cmd_parts.append(f"--location '{gcp_target['location']}'")
    
    # Opciones
    if options["dry_run"]:
        cmd_parts.append("--dry-run")
    if options["skip_validation"]:
        cmd_parts.append("--skip-validation")
    
    return " ".join(cmd_parts)

def execute_deployment(cmd: str) -> int:
    """Ejecuta el comando de despliegue."""
    print_header("Ejecutando Despliegue")
    print(f"{Colors.GRAY}Comando:{Colors.NC}")
    print(f"  {cmd}\n")
    
    print(f"{Colors.GRAY}{'─' * 70}{Colors.NC}\n")
    
    result = os.system(cmd)
    
    print(f"\n{Colors.GRAY}{'─' * 70}{Colors.NC}\n")
    
    if result == 0:
        print(f"{Colors.GREEN}✓ Despliegue completado exitosamente{Colors.NC}\n")
        return 0
    else:
        print(f"{Colors.RED}✗ El despliegue finalizó con errores{Colors.NC}\n")
        return 1

def save_to_history(gitlab_source: dict, gcp_target: dict):
    """Guarda el despliegue en historial."""
    history_file = Path(__file__).parent / "deployment_history.log"
    
    from datetime import datetime
    
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    entry = f"{timestamp} | {gcp_target['workflow_name']} | {gcp_target['project_id']}\n"
    
    try:
        with open(history_file, "a") as f:
            f.write(entry)
    except OSError:
        pass  # Ignorar errores de escritura

def main():
    """Función principal."""
    clear_screen()
    print(f"{Colors.GREEN}╔{'═' * 68}╗{Colors.NC}")
    print(f"{Colors.GREEN}║{Colors.NC} {Colors.WHITE}Workflow Deployment Manager - Modo Interactivo{Colors.NC.rjust(46)} {Colors.GREEN}║{Colors.NC}")
    print(f"{Colors.GREEN}╚{'═' * 68}╝{Colors.NC}\n")
    
    step = 1
    gitlab_source = None
    gcp_target = None
    options = {"dry_run": False, "skip_validation": False}
    
    while True:
        try:
            if step == 1:
                gitlab_source = step_1_gitlab_source()
                if gitlab_source is None:
                    print(f"{Colors.YELLOW}Despliegue cancelado{Colors.NC}")
                    break
                step = 2
            
            elif step == 2:
                gcp_target = step_2_gcp_target()
                step = 3
            
            elif step == 3:
                result = step_3_options()
                if result is None:
                    step = 1
                    continue
                options = result
                step = 4
            
            elif step == 4:
                clear_screen()
                result = step_4_preview(gitlab_source, gcp_target, options)
                
                if result is True:
                    # Ejecutar despliegue
                    cmd = build_command(gitlab_source, gcp_target, options)
                    exit_code = execute_deployment(cmd)
                    
                    if exit_code == 0:
                        save_to_history(gitlab_source, gcp_target)
                    
                    # Preguntar si continuar
                    print_menu({"1": "Nuevo despliegue", "0": "Salir"})
                    if input(f"{Colors.YELLOW}Opción{Colors.NC}: ").strip() == "1":
                        gitlab_source = None
                        gcp_target = None
                        options = {"dry_run": False, "skip_validation": False}
                        step = 1
                        clear_screen()
                    else:
                        break
                
                elif result is None:
                    step = 3
                else:
                    print(f"{Colors.YELLOW}Despliegue cancelado{Colors.NC}")
                    break
        
        except KeyboardInterrupt:
            print(f"\n{Colors.YELLOW}Operación cancelada por el usuario{Colors.NC}")
            break
        except Exception as e:
            print(f"{Colors.RED}✗ Error: {e}{Colors.NC}")
            break
    
    print(f"\n{Colors.GRAY}¡Hasta luego!{Colors.NC}\n")

if __name__ == "__main__":
    main()
