#!/usr/bin/env python3
"""
GNP File Promotion - Setup de usuario
Solicita acrónimo del usuario una sola vez durante instalación
"""

import json
from pathlib import Path

def main():
    config_file = Path('promotion-config.json')
    
    # Si ya existe config, no preguntar
    if config_file.exists():
        with open(config_file) as f:
            config = json.load(f)
            if 'user' in config:
                print(f"✓ Usuario ya configurado: {config['user']}")
                return
    
    print("\n" + "="*60)
    print("GNP File Promotion - Configuración de Usuario")
    print("="*60 + "\n")
    
    while True:
        print("👤 Acrónimo de usuario (ej: JDO):")
        user = input("> ").strip()
        if user and len(user) <= 10:
            print(f"   ✓ Usuario: {user}\n")
            break
        else:
            print("   ✗ Acrónimo inválido. Max 10 caracteres.\n")
    
    # Crear o actualizar config con usuario
    if config_file.exists():
        with open(config_file) as f:
            config = json.load(f)
    else:
        config = {
            "gitlab_url": "https://gitlab.com",
            "promotions": []
        }
    
    config['user'] = user
    
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)
    
    print("✓ Usuario guardado en configuración\n")

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nCancelado.")
