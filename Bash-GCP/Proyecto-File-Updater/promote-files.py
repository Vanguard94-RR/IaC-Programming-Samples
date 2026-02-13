#!/usr/bin/env python3
"""
GitLab File Promotion Script
Promociona archivos desde repositorios de desarrollo a repositorios de infraestructura
"""

import os
import sys
import json
import base64
import argparse
import logging
from pathlib import Path
from typing import Dict, List, Tuple, Optional
import requests
from datetime import datetime

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('promotion.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


class GitLabFilePromoter:
    """Maneja la promoción de archivos entre repositorios de GitLab"""
    
    def __init__(self, gitlab_url: str, token: str, dry_run: bool = False):
        """
        Inicializa el promotor
        
        Args:
            gitlab_url: URL base de GitLab (ej: https://gitlab.com)
            token: Token de acceso personal de GitLab
            dry_run: Si True, simula sin hacer cambios
        """
        self.gitlab_url = gitlab_url.rstrip('/')
        self.token = token
        self.dry_run = dry_run
        self.session = requests.Session()
        self.session.headers.update({
            'PRIVATE-TOKEN': token,
            'Content-Type': 'application/json'
        })
    
    def validate_token(self) -> bool:
        """
        Valida que el token sea válido antes de iniciar promociones
        
        Returns:
            True si token es válido, False en caso contrario
        """
        try:
            url = f"{self.gitlab_url}/api/v4/user"
            response = self.session.get(url, timeout=5)
            if response.status_code == 200:
                user = response.json().get('name', 'Unknown')
                logger.info(f"Token válido: usuario '{user}'")
                return True
            else:
                logger.error(f"Token inválido o expirado (status: {response.status_code})")
                return False
        except requests.Timeout:
            logger.error("Timeout al validar token - conexión lenta")
            return False
        except Exception as e:
            logger.error(f"Error al validar token: {e}")
            return False
    
    def get_project_id(self, project_path: str) -> Optional[str]:
        """
        Obtiene el ID de proyecto a partir de la ruta (grupo/proyecto)
        
        Args:
            project_path: Ruta del proyecto (ej: gitgnp/foundry/GKE-GNP-Solicitud-Foundry-Agente)
        
        Returns:
            ID del proyecto o None si no existe
        """
        try:
            # Codificar la ruta para uso en URL
            encoded_path = requests.utils.quote(project_path, safe='')
            url = f"{self.gitlab_url}/api/v4/projects/{encoded_path}"
            response = self.session.get(url)
            
            if response.status_code == 200:
                project_id = response.json().get('id')
                logger.info(f"Proyecto encontrado: {project_path} (ID: {project_id})")
                return str(project_id)
            else:
                logger.error(f"No se encontró proyecto: {project_path}")
                return None
        except Exception as e:
            logger.error(f"Error al obtener ID de proyecto {project_path}: {e}")
            return None
    
    def get_file_content(self, project_id: str, file_path: str, branch: str = 'master') -> Optional[str]:
        """
        Obtiene el contenido de un archivo desde un repositorio
        
        Args:
            project_id: ID del proyecto
            file_path: Ruta del archivo en el repositorio
            branch: Rama del repositorio
        
        Returns:
            Contenido del archivo en base64 o None
        """
        try:
            encoded_path = requests.utils.quote(file_path, safe='')
            url = f"{self.gitlab_url}/api/v4/projects/{project_id}/repository/files/{encoded_path}"
            params = {'ref': branch}
            response = self.session.get(url, params=params)
            
            if response.status_code == 200:
                content = response.json().get('content')
                logger.info(f"Archivo obtenido: {file_path} desde rama {branch}")
                return content
            else:
                logger.error(f"Error al obtener archivo {file_path}: {response.status_code}")
                return None
        except Exception as e:
            logger.error(f"Error al descargar {file_path}: {e}")
            return None
    
    def file_exists_with_content(self, project_id: str, file_path: str, content: str, 
                                branch: str = 'master') -> Tuple[bool, Optional[str]]:
        """
        Verifica si un archivo existe y tiene el mismo contenido
        
        Args:
            project_id: ID del proyecto
            file_path: Ruta del archivo
            content: Contenido en base64 a comparar
            branch: Rama
        
        Returns:
            Tupla (existe_con_mismo_contenido, contenido_actual)
        """
        try:
            encoded_path = requests.utils.quote(file_path, safe='')
            url = f"{self.gitlab_url}/api/v4/projects/{project_id}/repository/files/{encoded_path}"
            params = {'ref': branch}
            response = self.session.get(url, params=params)
            
            if response.status_code == 200:
                existing = response.json().get('content')
                logger.debug(f"Archivo encontrado: {file_path}")
                # Comparar base64 directamente sin strip para evitar perder datos
                if existing and existing == content:
                    logger.info(f"Archivo sin cambios (idempotente): {file_path}")
                    return True, existing
                return False, existing
            return False, None
        except Exception as e:
            logger.debug(f"Archivo no existe o error al verificar: {file_path} - {e}")
            return False, None
    
    def create_or_update_file(self, project_id: str, file_path: str, content: str, 
                             branch: str = 'master', commit_message: str = None) -> bool:
        """
        Crea o actualiza un archivo en un repositorio
        
        Args:
            project_id: ID del proyecto
            file_path: Ruta del archivo
            content: Contenido del archivo en base64
            branch: Rama destino
            commit_message: Mensaje de commit
        
        Returns:
            True si fue exitoso, False en caso de error
        """
        try:
            if commit_message is None:
                commit_message = f"Promoción automática de {file_path}"
            
            encoded_path = requests.utils.quote(file_path, safe='')
            url = f"{self.gitlab_url}/api/v4/projects/{project_id}/repository/files/{encoded_path}"
            
            data = {
                'branch': branch,
                'content': content,
                'commit_message': commit_message,
                'encoding': 'base64'
            }
            
            # Modo dry-run: simular sin hacer cambios
            if self.dry_run:
                logger.info(f"[DRY-RUN] Sería creado/actualizado: {file_path}")
                return True
            
            # Intentar crear el archivo
            response = self.session.post(url, json=data)
            
            if response.status_code == 201:
                logger.info(f"Archivo creado: {file_path}")
                return True
            elif response.status_code == 400:
                # Archivo ya existe, intentar actualizar
                response = self.session.put(url, json=data)
                if response.status_code == 200:
                    logger.info(f"Archivo actualizado: {file_path}")
                    return True
                else:
                    logger.error(f"Error al actualizar {file_path}: {response.status_code}")
                    logger.debug(f"Response: {response.text}")
                    return False
            else:
                logger.error(f"Error al crear/actualizar {file_path}: {response.status_code}")
                logger.debug(f"Response: {response.text}")
                return False
        except Exception as e:
            logger.error(f"Error al guardar {file_path}: {e}")
            return False
    
    def promote_file(self, source_config: Dict, dest_config: Dict, 
                    source_file_path: str, dest_file_path: str, 
                    commit_message: str = None) -> Dict:
        """
        Promueve un archivo de un repositorio a otro (idempotente)
        
        Args:
            source_config: Configuración del repositorio fuente
            dest_config: Configuración del repositorio destino
            source_file_path: Ruta del archivo fuente
            dest_file_path: Ruta del archivo destino
            commit_message: Mensaje de commit personalizado
        
        Returns:
            Dict con 'success' (bool) y 'changed' (bool)
        """
        logger.info(f"Iniciando promoción: {source_file_path} -> {dest_file_path}")
        
        # Obtener ID del proyecto fuente
        source_project_id = self.get_project_id(source_config['project'])
        if not source_project_id:
            return {'success': False, 'changed': False}
        
        # Obtener contenido del archivo
        content = self.get_file_content(
            source_project_id,
            source_file_path,
            source_config.get('branch', 'master')
        )
        if not content:
            return {'success': False, 'changed': False}
        
        # Obtener ID del proyecto destino
        dest_project_id = self.get_project_id(dest_config['project'])
        if not dest_project_id:
            return {'success': False, 'changed': False}
        
        # Verificar si el contenido ya es idéntico (sin cambios)
        # Devuelve tupla (existe_con_mismo_contenido, contenido_actual)
        same_content, _ = self.file_exists_with_content(dest_project_id, dest_file_path, content, 
                                                        dest_config.get('branch', 'master'))
        if same_content:
            logger.info(f"✓ Archivo idéntico, sin cambios: {source_file_path}")
            return {'success': True, 'changed': False}
        
        # Usar commit_message proporcionado o generar uno por defecto
        if commit_message is None:
            commit_message = f"Promoción automática de {source_file_path}"
        
        # Crear/actualizar archivo en destino
        success = self.create_or_update_file(
            dest_project_id,
            dest_file_path,
            content,
            dest_config.get('branch', 'master'),
            commit_message
        )
        
        if success:
            logger.info(f"✓ Promoción completada: {source_file_path}")
            return {'success': True, 'changed': True}
        else:
            logger.error(f"✗ Promoción fallida: {source_file_path}")
            return {'success': False, 'changed': False}
    
    def promote_multiple_files(self, promotions: List[Dict], user_acronym: str = None, ticket: str = None) -> Dict:
        """
        Promueve múltiples archivos
        
        Args:
            promotions: Lista de configuraciones de promoción
            user_acronym: Acrónimo del usuario (ej: JDO)
            ticket: Número de ticket (ej: CTASK0337281)
        
        Returns:
            Diccionario con estadísticas de promoción
        """
        stats = {
            'total': len(promotions),
            'successful': 0,
            'failed': 0,
            'details': []
        }
        
        # Generar commit message si se proporcionan datos
        commit_msg = None
        if user_acronym and ticket:
            today = datetime.now().strftime('%Y-%m-%d')
            commit_msg = f"{user_acronym}-{ticket}-{today}"
        
        for promotion in promotions:
            try:
                result = self.promote_file(
                    promotion['source'],
                    promotion['destination'],
                    promotion['source_path'],
                    promotion['dest_path'],
                    commit_msg
                )
                
                if result['success']:
                    stats['successful'] += 1
                    status = 'changed' if result['changed'] else 'skipped'
                    stats['details'].append({
                        'file': promotion['source_path'],
                        'status': status
                    })
                else:
                    stats['failed'] += 1
                    stats['details'].append({
                        'file': promotion['source_path'],
                        'status': 'failed'
                    })
            except Exception as e:
                logger.error(f"Error al procesar promoción: {e}")
                stats['failed'] += 1
                stats['details'].append({
                    'file': promotion.get('source_path', 'unknown'),
                    'status': 'error',
                    'error': str(e)
                })
        
        return stats


def load_config(config_file: str) -> Dict:
    """Carga y valida la configuración desde archivo JSON"""
    try:
        with open(config_file, 'r') as f:
            config = json.load(f)
        
        # Validar estructura requerida
        if 'promotions' not in config:
            raise ValueError("Config: Falta sección 'promotions'")
        
        if not isinstance(config['promotions'], list):
            raise ValueError("Config: 'promotions' debe ser una lista")
        
        if len(config['promotions']) == 0:
            raise ValueError("Config: 'promotions' está vacía")
        
        # Validar cada promoción
        required_keys = ['source', 'destination', 'source_path', 'dest_path']
        for i, promo in enumerate(config['promotions']):
            for key in required_keys:
                if key not in promo:
                    raise ValueError(f"Promoción {i}: Falta clave requerida '{key}'")
            
            # Validar sub-campos
            if 'project' not in promo['source'] or 'project' not in promo['destination']:
                raise ValueError(f"Promoción {i}: Falta 'project' en source o destination")
        
        logger.info(f"Configuración válida: {len(config['promotions'])} promociones")
        return config
    
    except json.JSONDecodeError as e:
        logger.error(f"Error al parsear JSON en {config_file}: {e}")
        sys.exit(1)
    except ValueError as e:
        logger.error(f"Configuración inválida: {e}")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Error al cargar configuración: {e}")
        sys.exit(1)


def load_token(token_file: str = '../PersonalGitLabToken') -> str:
    """Carga el token desde archivo. No usar env vars."""
    try:
        with open(token_file, 'r') as f:
            token = f.read().strip()
            if not token:
                raise ValueError("Token file is empty")
            return token
    except FileNotFoundError:
        logger.error(f"Token file not found: {token_file}")
        logger.error(f"Create it with: echo 'your-token' > {token_file}")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Error reading token: {e}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description='Promueve archivos entre repositorios de GitLab'
    )
    parser.add_argument(
        '--config',
        default='promotion-config.json',
        help='Archivo de configuración (default: promotion-config.json)'
    )
    parser.add_argument(
        '--gitlab-url',
        default='https://gitlab.com',
        help='URL de GitLab (default: https://gitlab.com)'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Simular sin hacer cambios'
    )
    
    args = parser.parse_args()
    
    # Cargar token automáticamente
    token = load_token('../PersonalGitLabToken')
    
    # Cargar configuración
    if not os.path.exists(args.config):
        logger.error(f"Archivo de configuración no encontrado: {args.config}")
        sys.exit(1)
    
    config = load_config(args.config)
    
    # Obtener user y ticket desde config
    user = config.get('user')
    ticket = config.get('ticket')
    
    if not user or not ticket:
        logger.error("Usuario y ticket no encontrados en configuración. Ejecuta: make setup")
        sys.exit(1)
    
    if args.dry_run:
        logger.info("=== MODO DRY-RUN (sin cambios reales) ===")
    
    # Crear promotor
    promoter = GitLabFilePromoter(args.gitlab_url, token, dry_run=args.dry_run)
    
    # Pre-flight checks
    logger.info("Ejecutando verificaciones previas...")
    if not promoter.validate_token():
        logger.error("Token de GitLab inválido. Abortando.")
        sys.exit(1)
    
    logger.info("Verificaciones previas: OK")
    
    # Promocionar archivos
    logger.info(f"Procesando {len(config['promotions'])} promociones...")
    logger.info(f"Commit message: {user}-{ticket}-{datetime.now().strftime('%Y-%m-%d')}")
    stats = promoter.promote_multiple_files(config['promotions'], user, ticket)
    
    # Reportar resultados
    logger.info("\n" + "="*50)
    logger.info(f"Promoción completada:")
    logger.info(f"  Total: {stats['total']}")
    logger.info(f"  Exitosas: {stats['successful']}")
    logger.info(f"  Fallidas: {stats['failed']}")
    logger.info("="*50)
    
    # Guardar reporte
    report = {
        'timestamp': datetime.now().isoformat(),
        'stats': stats
    }
    
    report_file = 'promotion-report.json'
    with open(report_file, 'w') as f:
        json.dump(report, f, indent=2)
    logger.info(f"Reporte guardado en: {report_file}")
    
    return 0 if stats['failed'] == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
