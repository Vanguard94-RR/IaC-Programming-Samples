#!/usr/bin/env python3
"""
GNP File Promotion - Setup interactivo
Solicita URLs y genera la configuración automáticamente
"""

import json
import sys
import re
from pathlib import Path

def parse_gitlab_url(url):
    """
    Extrae información de una URL de GitLab
    Limpia parámetros query como ?ref_type=heads
    Ejemplos:
    - https://gitlab.com/gitgnp/foundry/repo/-/blob/branch/path/file.yaml
    - https://gitlab.com/gitgnp/gcp/repo/-/blob/master/path/file.yaml?ref_type=heads
    """
    url = url.strip()
    
    # Remover parámetros query (?...)
    if '?' in url:
        url = url.split('?')[0]
    
    # Patrón para URLs de GitLab (soporta múltiples niveles)
    pattern = r'https://gitlab\.com/(.+?)/-/blob/([^/]+)/(.+)'
    match = re.match(pattern, url)
    
    if not match:
        return None
    
    project = match.group(1)
    branch = match.group(2)
    file_path = match.group(3)
    
    return {
        'project': project,
        'branch': branch,
        'file_path': file_path
    }

def main():
    print("\n" + "="*60)
    print("GNP File Promotion - Configuración")
    print("="*60 + "\n")
    
    print("Proporciona las URLs de GitLab con la ruta del archivo:")
    print("Formato: https://gitlab.com/grupo/subgrupo/proyecto/-/blob/rama/ruta/archivo.yaml\n")
    
    # URL origen
    while True:
        print("📥 URL de ORIGEN (repositorio de desarrollo):")
        source_url = input("> ").strip()
        source = parse_gitlab_url(source_url)
        if source:
            print(f"   ✓ Proyecto: {source['project']}")
            print(f"   ✓ Rama: {source['branch']}")
            print(f"   ✓ Archivo: {source['file_path']}\n")
            break
        else:
            print("   ✗ URL inválida. Intenta de nuevo.\n")
    
    # URL destino
    while True:
        print("📤 URL de DESTINO (repositorio de infraestructura):")
        dest_url = input("> ").strip()
        dest = parse_gitlab_url(dest_url)
        if dest:
            print(f"   ✓ Proyecto: {dest['project']}")
            print(f"   ✓ Rama: {dest['branch']}")
            print(f"   ✓ Archivo: {dest['file_path']}\n")
            break
        else:
            print("   ✗ URL inválida. Intenta de nuevo.\n")
    
    # Pedir solo ticket
    print("🎫 Número de TICKET (ej: CTASK0342189):")
    ticket = input("> ").strip()
    if not ticket:
        print("   ✗ Ticket requerido.\n")
        sys.exit(1)
    print(f"   ✓ Ticket: {ticket}\n")
    
    # Generar configuración
    config = {
        "gitlab_url": "https://gitlab.com",
        "ticket": ticket,
        "promotions": [
            {
                "source": {
                    "project": source['project'],
                    "branch": source['branch']
                },
                "destination": {
                    "project": dest['project'],
                    "branch": dest['branch']
                },
                "source_path": source['file_path'],
                "dest_path": dest['file_path']
            }
        ]
    }
    
    # Guardar configuración (preservar user si existe)
    config_file = Path('promotion-config.json')
    if config_file.exists():
        with open(config_file) as f:
            existing = json.load(f)
            if 'user' in existing:
                config['user'] = existing['user']
    
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)
    
    print("✓ Configuración guardada en: promotion-config.json\n")
    
    # Mostrar resumen
    print("Resumen:")
    print(f"  Origen:      {source['project']}/{source['file_path']}")
    print(f"  Destino:     {dest['project']}/{dest['file_path']}")
    print(f"  Ticket:      {ticket}")
    print(f"  Ticket:      {ticket}")
    print("\nPróximos pasos:")
    print("  1. make promote-dry    (simular)")
    print("  2. make promote        (ejecutar)")

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nCancelado.")
        sys.exit(0)
