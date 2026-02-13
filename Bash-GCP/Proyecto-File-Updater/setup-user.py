#!/usr/bin/env python3
"""
Setup de usuario y ticket para promociones
"""
from pathlib import Path

env_file = Path('.env.local')

print("Configurar información de usuario")
print("-" * 40)

user = input("Acrónimo de usuario (ej: JDO): ").strip()
ticket = input("Número de ticket (ej: CTASK0337281): ").strip()

if user and ticket:
    with open(env_file, 'w') as f:
        f.write(f"USER_ACRONYM={user}\n")
        f.write(f"TICKET={ticket}\n")
    print(f"\n✓ Guardado: {user} / {ticket}")
else:
    print("\n✗ Datos vacíos")
