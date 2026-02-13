#!/usr/bin/env python3
"""
Genera un reporte HTML a partir del JSON de escaneo de secretos.
"""

import json
import sys
import os
from datetime import datetime
from pathlib import Path

def generate_html_report(json_file, output_html=None):
    """Genera un reporte HTML a partir del JSON del escaneo."""
    
    if not os.path.exists(json_file):
        print(f"❌ Archivo JSON no encontrado: {json_file}")
        sys.exit(1)
    
    with open(json_file, 'r') as f:
        data = json.load(f)
    
    output_html = output_html or json_file.replace('.json', '.html')
    
    # Calcular estadísticas
    total_findings = data.get('total_findings', 0)
    critical_count = sum(1 for findings in data.get('results', {}).values() 
                        for f in findings if f['severity'] == 'CRITICAL')
    high_count = sum(1 for findings in data.get('results', {}).values() 
                    for f in findings if f['severity'] == 'HIGH')
    medium_count = total_findings - critical_count - high_count
    
    # Agrupar por tipo de secreto
    by_type = {}
    for file_path, findings in data.get('results', {}).items():
        for finding in findings:
            secret_type = finding['type']
            if secret_type not in by_type:
                by_type[secret_type] = []
            by_type[secret_type].append({
                'file': file_path,
                'line': finding['line'],
                'severity': finding['severity'],
                'preview': finding['content_preview']
            })
    
    # Generar HTML
    html_content = f"""<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Reporte de Escaneo de Secretos</title>
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        
        body {{
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #f5f5f5;
            color: #333;
            line-height: 1.6;
        }}
        
        .container {{
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }}
        
        header {{
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: white;
            padding: 30px;
            border-radius: 8px;
            margin-bottom: 30px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }}
        
        header h1 {{
            font-size: 2.5em;
            margin-bottom: 10px;
        }}
        
        .scan-info {{
            font-size: 0.95em;
            opacity: 0.9;
        }}
        
        .stats {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }}
        
        .stat-card {{
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            text-align: center;
        }}
        
        .stat-card h3 {{
            color: #666;
            font-size: 0.9em;
            margin-bottom: 10px;
            text-transform: uppercase;
            letter-spacing: 1px;
        }}
        
        .stat-number {{
            font-size: 2.5em;
            font-weight: bold;
            color: #2a5298;
        }}
        
        .stat-card.critical .stat-number {{
            color: #d32f2f;
        }}
        
        .stat-card.high .stat-number {{
            color: #f57c00;
        }}
        
        .stat-card.medium .stat-number {{
            color: #fbc02d;
        }}
        
        .findings {{
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            margin-bottom: 20px;
        }}
        
        .findings h2 {{
            color: #1e3c72;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid #2a5298;
        }}
        
        .finding {{
            padding: 15px;
            margin-bottom: 15px;
            border-left: 4px solid #ccc;
            background: #fafafa;
            border-radius: 4px;
        }}
        
        .finding.critical {{
            border-left-color: #d32f2f;
            background: #ffebee;
        }}
        
        .finding.high {{
            border-left-color: #f57c00;
            background: #fff3e0;
        }}
        
        .finding.medium {{
            border-left-color: #fbc02d;
            background: #fffde7;
        }}
        
        .finding-header {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 8px;
        }}
        
        .finding-file {{
            font-weight: bold;
            color: #1e3c72;
        }}
        
        .finding-meta {{
            display: flex;
            gap: 15px;
            font-size: 0.85em;
            color: #666;
        }}
        
        .finding-type {{
            display: inline-block;
            background: #2a5298;
            color: white;
            padding: 3px 8px;
            border-radius: 3px;
            font-size: 0.85em;
        }}
        
        .finding-type.critical {{
            background: #d32f2f;
        }}
        
        .finding-type.high {{
            background: #f57c00;
        }}
        
        .finding-type.medium {{
            background: #fbc02d;
            color: #333;
        }}
        
        .finding-preview {{
            background: white;
            padding: 10px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
            font-size: 0.85em;
            overflow-x: auto;
            color: #d32f2f;
            margin-top: 8px;
            border: 1px solid #ddd;
        }}
        
        .type-section {{
            margin-bottom: 30px;
        }}
        
        .type-section h3 {{
            color: #2a5298;
            margin-bottom: 15px;
            padding: 10px;
            background: #f5f5f5;
            border-radius: 4px;
        }}
        
        footer {{
            text-align: center;
            color: #666;
            font-size: 0.9em;
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #ddd;
        }}
        
        .alert {{
            background: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 15px;
            border-radius: 4px;
            margin-bottom: 20px;
        }}
        
        .alert strong {{
            color: #856404;
        }}
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🔒 Reporte de Escaneo de Secretos</h1>
            <div class="scan-info">
                <p>📁 Ruta: <strong>{data.get('scan_path', 'N/A')}</strong></p>
                <p>📅 Fecha: <strong>{data.get('scan_date', 'N/A')}</strong></p>
            </div>
        </header>
        
        <div class="alert">
            <strong>⚠️ ALERTA DE SEGURIDAD:</strong> Este reporte contiene información confidencial. 
            Mantenga este archivo en un lugar seguro y no lo comparta sin autorización.
        </div>
        
        <div class="stats">
            <div class="stat-card critical">
                <h3>🔴 Crítico</h3>
                <div class="stat-number">{critical_count}</div>
            </div>
            <div class="stat-card high">
                <h3>🟠 Alto</h3>
                <div class="stat-number">{high_count}</div>
            </div>
            <div class="stat-card medium">
                <h3>🟡 Medio</h3>
                <div class="stat-number">{medium_count}</div>
            </div>
            <div class="stat-card">
                <h3>📊 Total</h3>
                <div class="stat-number">{total_findings}</div>
            </div>
        </div>
        
        <div class="findings">
            <h2>Hallazgos por Tipo de Secreto</h2>
"""
    
    # Agregar hallazgos por tipo
    for secret_type in sorted(by_type.keys()):
        items = by_type[secret_type]
        html_content += f"""
        <div class="type-section">
            <h3>🔑 {secret_type} ({len(items)} hallazgos)</h3>
"""
        
        for item in sorted(items, key=lambda x: (x['severity'], x['file'])):
            severity_class = item['severity'].lower()
            html_content += f"""
            <div class="finding {severity_class}">
                <div class="finding-header">
                    <div class="finding-file">📄 {item['file']}</div>
                    <div class="finding-meta">
                        <span class="finding-type {severity_class}">{item['severity']}</span>
                        <span>Línea: {item['line']}</span>
                    </div>
                </div>
                <div class="finding-preview">{item['preview']}</div>
            </div>
"""
        
        html_content += """
        </div>
"""
    
    html_content += f"""
        </div>
        
        <footer>
            <p>Reporte generado automáticamente por Secret Scanner</p>
            <p>Generado: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
        </footer>
    </div>
</body>
</html>
"""
    
    with open(output_html, 'w', encoding='utf-8') as f:
        f.write(html_content)
    
    print(f"✅ Reporte HTML generado: {output_html}")
    return output_html

if __name__ == '__main__':
    if len(sys.argv) > 1:
        json_file = sys.argv[1]
        output_html = sys.argv[2] if len(sys.argv) > 2 else None
        generate_html_report(json_file, output_html)
    else:
        print("Uso:")
        print("  python3 generate-report.py security-scan-report.json")
        print("  python3 generate-report.py security-scan-report.json reporte.html")
