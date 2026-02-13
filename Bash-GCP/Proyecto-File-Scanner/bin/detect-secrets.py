#!/usr/bin/env python3
import os, re, json, sys, tempfile, shutil, requests
from datetime import datetime

PATTERNS = {
    'API_KEYS': [r'(?i)api[_-]?key\s*[:=]\s*["\']?([a-zA-Z0-9\-_]{20,})["\']?'],
    #'AWS_CREDENTIALS': [r'(?i)(AKIA[0-9A-Z]{16})', r'(?i)aws[_-]?access[_-]?key[_-]?id\s*[:=]\s*["\']?([A-Z0-9]{20})'],
    #'GCP_CREDENTIALS': [r'(?i)["\']?type["\']?\s*[:=]\s*["\']service_account["\']', r'(?i)["\']?project_id["\']?\s*[:=]\s*["\']([a-z0-9-]+)["\']'],
    'DATABASE_CREDENTIALS': [r'(?i)db[_-]?password\s*[:=]\s*["\']?([^"\':\s]{8,})["\']?', r'(?i)password\s*[:=]\s*["\']?([^"\':\s]{8,})["\']?'],
    'TOKENS': [r'(?i)token\s*[:=]\s*["\']?([a-zA-Z0-9_.]{32,})["\']?'],
    'PRIVATE_KEYS': [r'-----BEGIN (RSA |DSA |EC )?PRIVATE KEY-----'],
    'ENCRYPTION_KEYS': [r'(?i)encripcion[_-]?key\s*[:=]\s*["\']?([a-zA-Z0-9#\*\+_\-]{16,})["\']?', r'(?i)encripcion[_-]?iv\s*[:=]\s*["\']?([a-zA-Z0-9\*\+_\-]+)["\']?'],
    'CUSTOM_PATTERNS': [r'(?i)crm[_-]?key\s*[:=]\s*["\']?([a-zA-Z0-9]{32,})["\']?', r'l7xx[a-zA-Z0-9]{30,}']
}

EXCLUDED = [r'\.git', r'node_modules', r'__pycache__', r'\.env\.example', r'\.pyc', r'\.zip']

def skip_file(f):
    for p in EXCLUDED:
        if re.search(p, str(f)):
            return True
    return False

def scan_file(fp):
    findings = []
    seen = set()
    try:
        with open(fp, 'r', encoding='utf-8', errors='ignore') as f:
            for ln, line in enumerate(f, 1):
                for stype, patterns in PATTERNS.items():
                    for pat in patterns:
                        try:
                            for m in re.finditer(pat, line):
                                if 'example' not in line.lower():
                                    dk = (ln, line.strip())
                                    if dk not in seen:
                                        seen.add(dk)
                                        findings.append({'line': ln, 'type': stype, 'content': line.strip()[:100], 'severity': 'CRITICAL' if stype in ['PRIVATE_KEYS', 'AWS_CREDENTIALS', 'DATABASE_CREDENTIALS', 'CUSTOM_PATTERNS'] else 'HIGH'})
                        except:
                            pass
    except:
        pass
    return findings

def scan_dir(root, out=None):
    res = {}
    total = 0
    print(f"🔍 Escaneando: {root}\n" + "-"*80)
    for r, ds, fs in os.walk(root):
        ds[:] = [d for d in ds if not skip_file(os.path.join(r, d))]
        for f in fs:
            fp = os.path.join(r, f)
            if skip_file(fp):
                continue
            findings = scan_file(fp)
            if findings:
                rp = os.path.relpath(fp, root)
                res[rp] = findings
                total += len(findings)
                print(f"⚠️  {rp}")
                for fi in findings:
                    print(f"  {'🔴' if fi['severity']=='CRITICAL' else '🟠'} [{fi['severity']}] L{fi['line']}: {fi['type']}\n     {fi['content'][:80]}")
    print("\n" + "="*80 + f"\n📊 Total: {total} hallazgos en {len(res)} archivos")
    if total > 0:
        crit = sum(1 for v in res.values() for f in v if f['severity']=='CRITICAL')
        print(f"   �� Crítico: {crit}")
    if out or total > 0:
        op = out or 'security-scan-report.json'
        with open(op, 'w') as f:
            json.dump({'scan_date': datetime.now().isoformat(), 'total': total, 'results': res}, f, indent=2)
        print(f"✅ Reporte: {op}")

def get_token():
    for p in ['/home/admin/Documents/GNP/PersonalGitLabToken', os.path.expanduser('~/.gitlab_token')]:
        if os.path.exists(p):
            try:
                return open(p).read().strip()
            except:
                pass
    return os.environ.get('GITLAB_TOKEN', '')

def dl_file(url, td):
    try:
        print(f"📥 Descargando: {url}")
        url = url.split('?')[0]
        if '/-/blob/' in url:
            parts = url.split('/-/blob/')
            base = parts[0]
            pp = parts[1].split('/', 1)
            branch = pp[0]
            fp = pp[1] if len(pp) > 1 else ''
            proj = base.replace('https://gitlab.com/', '')
            ep = requests.utils.quote(proj, safe='')
            ef = requests.utils.quote(fp, safe='')
            url = f"https://gitlab.com/api/v4/projects/{ep}/repository/files/{ef}/raw?ref={branch}"
        fn = url.split('/')[-1].split('?')[0] or 'file'
        path = os.path.join(td, fn)
        h = {'PRIVATE-TOKEN': get_token()} if get_token() else {}
        r = requests.get(url, headers=h, timeout=30)
        r.raise_for_status()
        with open(path, 'wb') as f:
            f.write(r.content)
        print(f"✅ Descargado: {fn}")
        return td
    except Exception as e:
        print(f"❌ Error: {e}")
        return None

def dl_repo(url, td):
    try:
        print("📦 Accediendo al repositorio...")
        url = url.split('?')[0]
        if '/-/tree/' in url:
            base = url.split('/-/tree/')[0]
            pp = url.split('/-/tree/')[1].split('/', 1)
            branch = pp[0]
        else:
            base = url.replace('.git', '')
            branch = 'master'
        proj = base.replace('https://gitlab.com/', '')
        ep = requests.utils.quote(proj, safe='')
        h = {'PRIVATE-TOKEN': get_token()} if get_token() else {}
        api = f"https://gitlab.com/api/v4/projects/{ep}/repository/tree"
        print("🔍 Listando archivos...")
        
        ext = {'.env', '.yaml', '.yml', '.json', '.py', '.js', '.sh', '.conf', '.xml', '.md', '.sql', '.go', '.java', '.rb', '.properties'}
        all_f = []
        pg = 1
        max_pages = 5  # Limitar a 5 páginas (5000 archivos)
        
        try:
            while pg <= max_pages:
                try:
                    r = requests.get(api, headers=h, params={'ref': branch, 'recursive': 'true', 'per_page': 1000, 'page': pg}, timeout=15)
                    if r.status_code != 200:
                        print(f"⚠️  Página {pg}: Status {r.status_code}")
                        break
                    files = r.json()
                    if not files:
                        break
                    # Filtrar solo archivos de interés
                    for f in files:
                        if f['type'] == 'blob':
                            _, e = os.path.splitext(f['name'])
                            if e.lower() in ext or not e or f['name'].endswith(('.env', '.cfg', '.conf')):
                                all_f.append(f)
                    pg += 1
                except requests.exceptions.Timeout:
                    print(f"⚠️  Timeout en página {pg}")
                    break
                except Exception as e:
                    print(f"⚠️  Error página {pg}: {str(e)[:50]}")
                    break
        except KeyboardInterrupt:
            print("\n⚠️  Cancelado por usuario")
            
        print(f"✅ {len(all_f)} archivos encontrados")
        
        cnt = 0
        for i, fi in enumerate(all_f[:500]):  # Máximo 500 archivos
            fp = fi['path']
            try:
                ef = requests.utils.quote(fp, safe='')
                fu = f"https://gitlab.com/api/v4/projects/{ep}/repository/files/{ef}/raw"
                fr = requests.get(fu, headers=h, params={'ref': branch}, timeout=5)
                if fr.status_code == 200:
                    lp = os.path.join(td, fp)
                    os.makedirs(os.path.dirname(lp), exist_ok=True)
                    with open(lp, 'wb') as f:
                        f.write(fr.content)
                    cnt += 1
                    if (i + 1) % 50 == 0:
                        print(f"  ⏳ Descargados {i + 1} archivos...")
            except KeyboardInterrupt:
                print("\n⚠️  Cancelado por usuario")
                break
            except:
                pass
        
        print(f"✅ {cnt} archivos descargados del repositorio")
        return cnt > 0
    except KeyboardInterrupt:
        print("\n⚠️  Cancelado")
        return False
    except Exception as e:
        print(f"❌ Error: {str(e)[:100]}")
        return False

def is_url(p):
    return p.startswith(('http://', 'https://'))

def is_file_url(u):
    u = u.split('?')[0]
    return '/-/blob/' in u or u.endswith(('.env', '.py', '.sh'))

def process(path, out=None):
    if is_url(path):
        td = tempfile.mkdtemp(prefix='scan_')
        print(f"📁 Temp: {td}\n")
        try:
            if is_file_url(path):
                if not dl_file(path, td):
                    return
            else:
                if not dl_repo(path, td):
                    return
            scan_dir(td, out)
        finally:
            print("\n🧹 Limpiando...")
            shutil.rmtree(td, ignore_errors=True)
    else:
        # Verificar si es directorio o archivo local
        if os.path.isdir(path):
            print(f"📂 Analizando directorio: {path}\n")
            scan_dir(path, out)
        elif os.path.isfile(path):
            td = tempfile.mkdtemp(prefix='scan_')
            try:
                shutil.copy(path, td)
                scan_dir(td, out)
            finally:
                shutil.rmtree(td, ignore_errors=True)
        else:
            print(f"❌ Error: Ruta no encontrada: {path}")
            sys.exit(1)

if __name__ == '__main__':
    if len(sys.argv) > 1:
        process(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
    else:
        print("Uso: python3 detect-secrets.py <url-o-ruta> [salida.json]")
        sys.exit(1)
