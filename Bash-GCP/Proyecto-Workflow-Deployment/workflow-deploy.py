#!/usr/bin/env python3
"""
Workflow Deployment Tool
========================
Despliega workflows desde GitLab hacia Google Cloud Workflows.

Características:
- Descarga automática desde GitLab (ramas o tags)
- Validación de estructura para GCP Workflows
- Auto-detección de región para workflows existentes
- Modo dry-run para simulación segura

Uso:
    python3 workflow-deploy.py --url URL --name NAME --project PROJECT [opciones]

Autor: GNP Infrastructure Team
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse, unquote

import requests
import yaml

# ============================================================================
# Configuración de Logging
# ============================================================================

LOG_FILE = Path(__file__).parent / "workflow.log"
LOG_FORMAT = "%(asctime)s │ %(levelname)-5s │ %(message)s"
LOG_DATE_FORMAT = "%H:%M:%S"

logging.basicConfig(
    level=logging.INFO,
    format=LOG_FORMAT,
    datefmt=LOG_DATE_FORMAT,
    handlers=[
        logging.FileHandler(LOG_FILE, encoding="utf-8"),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger("workflow-deploy")

# ============================================================================
# Constantes
# ============================================================================

DEFAULT_LOCATION = "us-central1"
DEFAULT_GITLAB_URL = "https://gitlab.com"
GCLOUD_TIMEOUT_SECONDS = 120
GITLAB_TIMEOUT_SECONDS = 15


# ============================================================================
# Modelos de Datos
# ============================================================================

@dataclass
class GitLabSource:
    """Representa la fuente de un archivo en GitLab."""
    project: str
    branch: str
    file_path: str
    
    def __str__(self) -> str:
        return f"{self.project}@{self.branch}:{self.file_path}"


@dataclass  
class DeploymentTarget:
    """Representa el destino del despliegue en GCP."""
    workflow_name: str
    project_id: str
    location: str = DEFAULT_LOCATION
    
    def __str__(self) -> str:
        return f"{self.workflow_name} → {self.project_id}/{self.location}"


@dataclass
class DeploymentResult:
    """Resultado de una operación de despliegue."""
    success: bool
    message: str
    command: Optional[str] = None


# ============================================================================
# Validador de Workflows
# ============================================================================

class WorkflowValidator:
    """
    Valida la estructura de workflows para Google Cloud Workflows.
    
    GCP Workflows requiere:
    - Un workflow 'main' como punto de entrada
    - Cada workflow debe tener una lista de 'steps'
    """
    
    REQUIRED_ENTRY_POINT = "main"
    
    @classmethod
    def validate(cls, content: str) -> tuple[bool, list[str]]:
        """
        Valida el contenido YAML de un workflow.
        
        Args:
            content: Contenido YAML del workflow
            
        Returns:
            Tupla (es_válido, lista_de_errores)
        """
        errors: list[str] = []
        
        # Parsear YAML
        try:
            data = yaml.safe_load(content)
        except yaml.YAMLError as e:
            return False, [f"Error de sintaxis YAML: {cls._format_yaml_error(e)}"]
        
        # Validar estructura básica
        if not isinstance(data, dict):
            return False, ["El archivo debe contener un diccionario YAML"]
        
        if not data:
            return False, ["El archivo está vacío"]
        
        # Validar punto de entrada
        if cls.REQUIRED_ENTRY_POINT not in data:
            errors.append(
                f"Falta el workflow '{cls.REQUIRED_ENTRY_POINT}' "
                "(punto de entrada requerido por GCP)"
            )
        else:
            cls._validate_workflow_structure(data[cls.REQUIRED_ENTRY_POINT], "main", errors)
        
        # Validar subworkflows
        for name, workflow in data.items():
            if name != cls.REQUIRED_ENTRY_POINT and isinstance(workflow, dict):
                cls._validate_workflow_structure(workflow, name, errors)
        
        return len(errors) == 0, errors
    
    @classmethod
    def _validate_workflow_structure(
        cls, 
        workflow: dict, 
        name: str, 
        errors: list[str]
    ) -> None:
        """Valida la estructura interna de un workflow."""
        if not isinstance(workflow, dict):
            return
            
        if "steps" not in workflow:
            errors.append(f"El workflow '{name}' debe contener 'steps'")
        elif not isinstance(workflow["steps"], list):
            errors.append(f"'{name}.steps' debe ser una lista")
        elif len(workflow["steps"]) == 0:
            errors.append(f"'{name}.steps' no puede estar vacío")
    
    @staticmethod
    def _format_yaml_error(error: yaml.YAMLError) -> str:
        """Formatea un error de YAML para mejor legibilidad."""
        if hasattr(error, 'problem_mark'):
            mark = error.problem_mark
            return f"línea {mark.line + 1}, columna {mark.column + 1}"
        return str(error)


# ============================================================================
# Cliente GitLab
# ============================================================================

class GitLabClient:
    """
    Cliente para interactuar con la API de GitLab.
    
    Maneja autenticación, descarga de archivos y validación de tokens
    de forma segura y eficiente.
    """
    
    def __init__(self, base_url: str, token: str):
        """
        Inicializa el cliente GitLab.
        
        Args:
            base_url: URL base de GitLab (ej: https://gitlab.com)
            token: Token de acceso personal
        """
        self.base_url = base_url.rstrip("/")
        self._session = self._create_session(token)
        self._user_info: Optional[dict] = None
    
    @staticmethod
    def _create_session(token: str) -> requests.Session:
        """Crea una sesión HTTP configurada con el token."""
        session = requests.Session()
        session.headers.update({
            "PRIVATE-TOKEN": token,
            "Accept": "application/json",
            "User-Agent": "GNP-Workflow-Deployer/1.0"
        })
        return session
    
    def authenticate(self) -> bool:
        """
        Verifica que el token sea válido.
        
        Returns:
            True si el token es válido
        """
        try:
            response = self._session.get(
                f"{self.base_url}/api/v4/user",
                timeout=GITLAB_TIMEOUT_SECONDS
            )
            
            if response.status_code == 200:
                self._user_info = response.json()
                return True
            
            if response.status_code == 401:
                logger.error("Token inválido o expirado")
            else:
                logger.error(f"Error de autenticación (HTTP {response.status_code})")
            
            return False
            
        except requests.Timeout:
            logger.error("Timeout al conectar con GitLab")
            return False
        except requests.RequestException as e:
            logger.error(f"Error de conexión: {e}")
            return False
    
    def download_file(self, source: GitLabSource) -> Optional[str]:
        """
        Descarga un archivo desde GitLab.
        
        Args:
            source: Información del archivo a descargar
            
        Returns:
            Contenido del archivo o None si falla
        """
        # Codificar parámetros para URL
        encoded_project = source.project.replace("/", "%2F")
        encoded_path = source.file_path.replace("/", "%2F")
        
        url = (
            f"{self.base_url}/api/v4/projects/{encoded_project}"
            f"/repository/files/{encoded_path}/raw"
        )
        
        try:
            response = self._session.get(
                url,
                params={"ref": source.branch},
                timeout=GITLAB_TIMEOUT_SECONDS
            )
            
            if response.status_code == 200:
                logger.info(f"Descargado: {source.file_path}")
                return response.text
            
            if response.status_code == 404:
                logger.error(
                    f"Archivo no encontrado: {source.file_path} "
                    f"(rama: {source.branch})"
                )
            else:
                logger.error(f"Error al descargar (HTTP {response.status_code})")
            
            return None
            
        except requests.Timeout:
            logger.error("Timeout al descargar archivo")
            return None
        except requests.RequestException as e:
            logger.error(f"Error de descarga: {e}")
            return None


# ============================================================================
# Desplegador GCP
# ============================================================================

class GCPWorkflowDeployer:
    """
    Gestiona el despliegue de workflows en Google Cloud Workflows.
    
    Características:
    - Auto-detección de región para workflows existentes
    - Manejo seguro de archivos temporales
    - Soporte para modo dry-run
    """
    
    @classmethod
    def find_existing_location(
        cls, 
        workflow_name: str, 
        project_id: str
    ) -> Optional[str]:
        """
        Busca la ubicación de un workflow existente.
        
        Args:
            workflow_name: Nombre del workflow
            project_id: ID del proyecto GCP
            
        Returns:
            Ubicación del workflow o None si no existe
        """
        command = [
            "gcloud", "workflows", "list",
            f"--project={project_id}",
            "--format=json",
            "--quiet"
        ]
        
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode != 0:
                return None
            
            if not result.stdout.strip():
                return None
            
            workflows = json.loads(result.stdout)
            
            for workflow in workflows:
                # Formato: projects/PROJECT/locations/LOCATION/workflows/NAME
                name = workflow.get("name", "")
                if name.endswith(f"/workflows/{workflow_name}"):
                    parts = name.split("/")
                    if len(parts) >= 4:
                        location = parts[3]
                        logger.info(f"Workflow existente en: {location}")
                        return location
            
            return None
            
        except subprocess.TimeoutExpired:
            logger.debug("Timeout buscando workflow existente")
            return None
        except (json.JSONDecodeError, subprocess.SubprocessError):
            return None
    
    @classmethod
    def deploy(
        cls,
        target: DeploymentTarget,
        content: str,
        dry_run: bool = False
    ) -> DeploymentResult:
        """
        Despliega un workflow en GCP.
        
        Args:
            target: Configuración del destino
            content: Contenido YAML del workflow
            dry_run: Si es True, solo simula el despliegue
            
        Returns:
            Resultado del despliegue
        """
        # Crear archivo temporal de forma segura
        temp_file = cls._create_temp_file(content)
        if not temp_file:
            return DeploymentResult(
                success=False,
                message="Error al crear archivo temporal"
            )
        
        try:
            command = [
                "gcloud", "workflows", "deploy", target.workflow_name,
                f"--source={temp_file}",
                f"--project={target.project_id}",
                f"--location={target.location}",
                "--quiet"
            ]
            
            command_str = " ".join(command)
            logger.info(f"Comando: {command_str}")
            
            if dry_run:
                logger.info("🔸 DRY-RUN: Comando no ejecutado")
                return DeploymentResult(
                    success=True,
                    message="Simulación completada",
                    command=command_str
                )
            
            return cls._execute_deployment(command)
            
        finally:
            # Limpiar archivo temporal de forma segura
            cls._cleanup_temp_file(temp_file)
    
    @staticmethod
    def _create_temp_file(content: str) -> Optional[str]:
        """Crea un archivo temporal con el contenido del workflow."""
        try:
            with tempfile.NamedTemporaryFile(
                mode="w",
                suffix=".yaml",
                delete=False,
                encoding="utf-8"
            ) as f:
                f.write(content)
                return f.name
        except OSError as e:
            logger.error(f"Error creando archivo temporal: {e}")
            return None
    
    @staticmethod
    def _cleanup_temp_file(file_path: str) -> None:
        """Elimina el archivo temporal de forma segura."""
        try:
            Path(file_path).unlink(missing_ok=True)
        except OSError:
            pass  # Ignorar errores de limpieza
    
    @classmethod
    def _execute_deployment(cls, command: list[str]) -> DeploymentResult:
        """Ejecuta el comando de despliegue."""
        try:
            # Ejecutar mostrando salida en tiempo real
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True
            )
            
            output_lines = []
            for line in process.stdout:
                line = line.rstrip()
                if line:
                    logger.info(f"  {line}")
                    output_lines.append(line)
            
            process.wait(timeout=GCLOUD_TIMEOUT_SECONDS)
            
            if process.returncode == 0:
                return DeploymentResult(
                    success=True,
                    message="Workflow desplegado exitosamente"
                )
            
            error_msg = "\n".join(output_lines) or "Error desconocido"
            return DeploymentResult(
                success=False,
                message=f"Error de gcloud: {error_msg}"
            )
            
        except subprocess.TimeoutExpired:
            return DeploymentResult(
                success=False,
                message=f"Timeout: el despliegue excedió {GCLOUD_TIMEOUT_SECONDS}s"
            )
        except FileNotFoundError:
            return DeploymentResult(
                success=False,
                message="gcloud CLI no encontrado. Instala Google Cloud SDK."
            )
        except subprocess.SubprocessError as e:
            return DeploymentResult(
                success=False,
                message=f"Error de ejecución: {e}"
            )


# ============================================================================
# Parser de URLs
# ============================================================================

class GitLabURLParser:
    """
    Parsea URLs de GitLab para extraer información del archivo.
    
    Soporta formatos:
    - https://gitlab.com/grupo/proyecto/-/blob/rama/ruta/archivo.yml
    - https://gitlab.com/grupo/proyecto/-/blob/tag/archivo.yml?ref_type=tags
    """
    
    @classmethod
    def parse(cls, url: str) -> GitLabSource:
        """
        Extrae información de una URL de GitLab.
        
        Args:
            url: URL completa del archivo en GitLab
            
        Returns:
            GitLabSource con la información extraída
            
        Raises:
            ValueError: Si la URL no tiene el formato esperado
        """
        # Limpiar query strings
        clean_url = url.split("?")[0]
        
        # Buscar el separador de blob
        if "/-/blob/" not in clean_url:
            raise ValueError(
                "URL inválida. Formato esperado: "
                "https://gitlab.com/grupo/proyecto/-/blob/rama/archivo.yml"
            )
        
        try:
            # Separar base del proyecto y ruta del archivo
            base, blob_path = clean_url.split("/-/blob/", 1)
            
            # Extraer proyecto (todo después de gitlab.com/)
            project = cls._extract_project(base)
            
            # Separar rama/tag del path del archivo
            branch, file_path = cls._split_branch_and_path(blob_path)
            
            return GitLabSource(
                project=project,
                branch=branch,
                file_path=file_path
            )
            
        except (ValueError, IndexError) as e:
            raise ValueError(f"Error parseando URL: {e}")
    
    @staticmethod
    def _extract_project(base_url: str) -> str:
        """Extrae el nombre del proyecto de la URL base."""
        # Manejar tanto http como https
        for prefix in ["https://gitlab.com/", "http://gitlab.com/"]:
            if prefix in base_url:
                return base_url.split(prefix)[-1]
        
        # Si no tiene prefijo conocido, intentar extraer después del host
        parsed = urlparse(base_url)
        return parsed.path.lstrip("/")
    
    @staticmethod
    def _split_branch_and_path(blob_path: str) -> tuple[str, str]:
        """Separa la rama/tag del path del archivo."""
        parts = blob_path.split("/", 1)
        
        if len(parts) < 2:
            raise ValueError("Falta la ruta del archivo en la URL")
        
        branch = unquote(parts[0])
        file_path = unquote(parts[1])
        
        return branch, file_path


# ============================================================================
# Función Principal
# ============================================================================

def create_argument_parser() -> 'argparse.ArgumentParser':
    """Crea el parser de argumentos de línea de comandos."""
    import argparse
    
    parser = argparse.ArgumentParser(
        prog="workflow-deploy",
        description="Despliega workflows de GitLab a Google Cloud Workflows",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Ejemplos:
  # Desde URL de GitLab
  %(prog)s --url "https://gitlab.com/org/repo/-/blob/main/workflow.yml" \\
           --name mi-workflow --project gcp-project

  # Con componentes separados  
  %(prog)s --gitlab-project org/repo --branch main --path workflow.yml \\
           --name mi-workflow --project gcp-project

  # Simulación (dry-run)
  %(prog)s --url "..." --name workflow --project proj --dry-run

Variables de entorno:
  GITLAB_TOKEN    Token de acceso personal de GitLab (requerido)
        """
    )
    
    # Grupo: Fuente del archivo
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument(
        "--url",
        metavar="URL",
        help="URL completa del archivo en GitLab"
    )
    source.add_argument(
        "--gitlab-project",
        metavar="PROYECTO",
        help="Proyecto GitLab (formato: grupo/proyecto)"
    )
    
    # Parámetros de fuente adicionales
    parser.add_argument(
        "--branch", "-b",
        default="main",
        metavar="RAMA",
        help="Rama o tag (default: main)"
    )
    parser.add_argument(
        "--path",
        metavar="RUTA",
        help="Ruta al archivo YAML (requerido con --gitlab-project)"
    )
    
    # Destino GCP
    parser.add_argument(
        "--name", "-n",
        required=True,
        metavar="NOMBRE",
        help="Nombre del workflow en GCP"
    )
    parser.add_argument(
        "--project", "-p",
        required=True,
        metavar="PROYECTO",
        help="ID del proyecto en GCP"
    )
    parser.add_argument(
        "--location", "-l",
        metavar="REGION",
        help="Región de GCP (auto-detecta si el workflow existe)"
    )
    
    # Opciones
    parser.add_argument(
        "--dry-run", "-d",
        action="store_true",
        help="Simular sin ejecutar el despliegue"
    )
    parser.add_argument(
        "--skip-validation", "-s",
        action="store_true",
        help="Omitir validación del workflow"
    )
    parser.add_argument(
        "--gitlab-url",
        default=DEFAULT_GITLAB_URL,
        metavar="URL",
        help=f"URL base de GitLab (default: {DEFAULT_GITLAB_URL})"
    )
    
    return parser


def get_gitlab_token() -> str:
    """
    Obtiene el token de GitLab de las variables de entorno.
    
    Returns:
        Token de GitLab
        
    Raises:
        SystemExit: Si el token no está definido
    """
    token = os.environ.get("GITLAB_TOKEN", "").strip()
    
    if not token:
        logger.error(
            "Variable GITLAB_TOKEN no definida.\n"
            "Configúrala con: export GITLAB_TOKEN='tu-token'"
        )
        sys.exit(1)
    
    # Validación básica de seguridad
    if len(token) < 20:
        logger.warning("El token parece muy corto, podría ser inválido")
    
    return token


def print_header(source: GitLabSource, target: DeploymentTarget, dry_run: bool) -> None:
    """Imprime el encabezado con la configuración del despliegue."""
    separator = "═" * 55
    
    logger.info(separator)
    logger.info(f"  Workflow   : {target.workflow_name}")
    logger.info(f"  Origen     : {source.project}")
    logger.info(f"  Rama/Tag   : {source.branch}")
    logger.info(f"  Archivo    : {source.file_path}")
    logger.info(f"  Proyecto   : {target.project_id}")
    if dry_run:
        logger.info(f"  Modo       : 🔸 DRY-RUN (simulación)")
    logger.info(separator)


def main() -> None:
    """Punto de entrada principal del programa."""
    parser = create_argument_parser()
    args = parser.parse_args()
    
    # Obtener token de forma segura
    token = get_gitlab_token()
    
    # Parsear fuente
    try:
        if args.url:
            source = GitLabURLParser.parse(args.url)
        else:
            if not args.path:
                parser.error("--path es requerido cuando se usa --gitlab-project")
            source = GitLabSource(
                project=args.gitlab_project,
                branch=args.branch,
                file_path=args.path
            )
    except ValueError as e:
        logger.error(str(e))
        sys.exit(1)
    
    # Crear target inicial (location se determina después)
    target = DeploymentTarget(
        workflow_name=args.name,
        project_id=args.project,
        location=args.location or DEFAULT_LOCATION
    )
    
    # Mostrar configuración
    print_header(source, target, args.dry_run)
    
    # Autenticar con GitLab
    gitlab = GitLabClient(args.gitlab_url, token)
    if not gitlab.authenticate():
        sys.exit(1)
    
    # Auto-detectar ubicación si no se especificó
    if not args.location:
        logger.info(f"Buscando workflow existente...")
        detected = GCPWorkflowDeployer.find_existing_location(
            args.name, 
            args.project
        )
        if detected:
            target.location = detected
        else:
            logger.info(f"Workflow nuevo → {DEFAULT_LOCATION}")
    
    logger.info(f"Ubicación: {target.location}")
    
    # Descargar archivo
    content = gitlab.download_file(source)
    if not content:
        sys.exit(1)
    
    # Validar workflow
    if not args.skip_validation:
        is_valid, errors = WorkflowValidator.validate(content)
        if not is_valid:
            logger.error("Validación fallida:")
            for error in errors:
                logger.error(f"  • {error}")
            sys.exit(1)
        logger.info("✓ Validación OK")
    else:
        logger.info("⚠ Validación omitida")
    
    # Desplegar
    result = GCPWorkflowDeployer.deploy(target, content, args.dry_run)
    
    # Mostrar resultado
    logger.info("═" * 55)
    if result.success:
        logger.info(f"✓ {result.message}")
        sys.exit(0)
    else:
        logger.error(f"✗ {result.message}")
        sys.exit(1)


if __name__ == "__main__":
    main()
