# Deployment Guide: GitLab File Promotion System

## Overview
Complete production deployment guide for the GitLab File Promotion System with verification steps and troubleshooting.

---

## Phase 1: Pre-Deployment Setup (5 minutes)

### 1.1 System Requirements
```bash
# Check Python version (3.6+)
python3 --version
# Expected: Python 3.x.x

# Check pip
pip3 --version
# Expected: pip 20.x+ from ...
```

### 1.2 Install Dependencies
```bash
cd /home/admin/Documents/GNP/Proyecto-File-Updater
make install
# or: pip3 install requests
```

### 1.3 Prepare GitLab Token
```bash
# 1. Create a GitLab Personal Access Token (PAT) at:
#    https://gitlab.com/profile/personal_access_tokens
#
# 2. Required scopes: api, read_repository, write_repository
#
# 3. Store securely:
echo "your-gitlab-token-here" > /home/admin/Documents/GNP/PersonalGitLabToken
chmod 600 /home/admin/Documents/GNP/PersonalGitLabToken

# 4. Verify access:
ls -l /home/admin/Documents/GNP/PersonalGitLabToken
# Expected: -rw------- (only owner readable)
```

### 1.4 Prepare GitLab Repositories
Ensure you have access to both:
- **Source Repository**: Where files originate (must have read access)
- **Destination Repository**: Where files are promoted (must have write access)

Document the full GitLab paths:
```
Source Project: <GROUP>/<SUBGROUP>/<PROJECT>
Destination Project: <GROUP>/<SUBGROUP>/<PROJECT>
```

---

## Phase 2: Configuration (5 minutes)

### 2.1 Setup Configuration via URLs
```bash
cd /home/admin/Documents/GNP/Proyecto-File-Updater
make setup

# Follow interactive prompts:
# Paste source repo URL:
# https://gitlab.com/gitgnp/foundry/GKE-GNP-Solicitud-Foundry-Agente/-/blob/configuracion-servicio/configuracion/deployment.yaml

# Paste destination repo URL:
# https://gitlab.com/gitgnp/gcp/gke-config-files/-/blob/master/harness-manifests/.../deployment.yaml
```

### 2.2 Verify Generated Configuration
```bash
cat promotion-config.json | jq '.'

# Expected output:
{
  "promotions": [
    {
      "source": {
        "project": "gitgnp/foundry/GKE-GNP-Solicitud-Foundry-Agente",
        "branch": "configuracion-servicio"
      },
      "destination": {
        "project": "gitgnp/gcp/gke-config-files",
        "branch": "master"
      },
      "source_path": "configuracion/deployment.yaml",
      "dest_path": "harness-manifests/gnp-suscrip-gmmi-foundry/qa/.../deployment.yaml"
    }
  ]
}
```

### 2.3 Alternative: Manual Configuration
If `make setup` doesn't work, edit `promotion-config.json` directly:
```json
{
  "promotions": [
    {
      "source": {
        "project": "GROUP/SUBGROUP/PROJECT",
        "branch": "source-branch-name"
      },
      "destination": {
        "project": "GROUP/SUBGROUP/PROJECT",
        "branch": "dest-branch-name"
      },
      "source_path": "path/to/file.yaml",
      "dest_path": "path/to/destination/file.yaml"
    }
  ]
}
```

---

## Phase 3: Pre-Flight Testing (10 minutes)

### 3.1 Dry-Run Mode (Recommended First Step)
```bash
# Test without making any changes
make promote-dry

# Expected output:
# 2025-01-15 14:23:45,123 - INFO - [DRY-RUN] Sería creado/actualizado: configuracion/deployment.yaml
# 2025-01-15 14:23:46,234 - INFO - Token válido: usuario 'Your Name'
# 2025-01-15 14:23:47,345 - INFO - Archivo sin cambios (idempotente): ...
# 2025-01-15 14:23:47,456 - INFO - Promoción completada:
#   Total: 1
#   Exitosas: 1
#   Fallidas: 0
```

### 3.2 Check Dry-Run Report
```bash
cat promotion-report.json | jq '.details[0].status'
# Expected: "skipped" or "changed" (in dry-run, still appears as changed)
```

### 3.3 Verify Log Output
```bash
make logs  # or: tail -20 promotion.log

# Look for:
# ✓ "Token válido"
# ✓ "Verificaciones previas: OK"
# ✓ "Archivo creado/actualizado" OR "Archivo sin cambios"
# ✗ No error lines (ERROR, Exception, etc.)
```

---

## Phase 4: First Production Run (5 minutes)

### 4.1 Execute Promotion
```bash
# Option 1: Basic promotion
make promote

# Option 2: With custom commit info (skips prompts)
GITLAB_TOKEN=$(cat ../PersonalGitLabToken) python3 promote-files.py \
  --config promotion-config.json \
  --user INITIALS \
  --ticket CTASK123

# Examples:
GITLAB_TOKEN=$(cat ../PersonalGitLabToken) python3 promote-files.py \
  --config promotion-config.json \
  --user JMCM \
  --ticket CTASK0342189
```

### 4.2 Monitor Execution
Watch log output for:
```
✓ Token validation: "Token válido: usuario 'Your Name'"
✓ Pre-flight checks: "Verificaciones previas: OK"
✓ File promotion: "Archivo creado/actualizado" or "Archivo sin cambios"
✓ Completion: "Promoción completada" with stats
```

### 4.3 Verify Results
```bash
# 1. Check final report
cat promotion-report.json | jq '.'

# 2. Verify file in destination repo
# Visit: https://gitlab.com/gitgnp/gcp/gke-config-files
# Navigate to: harness-manifests/.../deployment.yaml
# Confirm file exists with correct content

# 3. Check commit message format
# Should be: USER-TICKET-DATE (e.g., JMCM-CTASK0342189-2025-01-15)
```

---

## Phase 5: Idempotence Verification (2 minutes)

### 5.1 Run Second Time (Should Skip)
```bash
make promote

# Expected output:
# Status for the file should be "skipped"
# Log should show: "Archivo sin cambios (idempotente): ..."
# No new commit created in destination
```

### 5.2 Verify Report
```bash
cat promotion-report.json | jq '.stats.details'

# Expected output after second run:
# [
#   {
#     "file": "configuracion/deployment.yaml",
#     "status": "skipped"
#   }
# ]
```

### 5.3 Modify Source and Run Again
```bash
# 1. Modify source file
# 2. Run promotion again
make promote

# Expected output:
# Status should be "changed" (file is different)
# New commit created in destination
```

---

## Phase 6: Production Monitoring

### 6.1 Setup Log Monitoring
```bash
# Daily: Check for errors
grep -i "error\|failed" promotion.log

# Weekly: Review promotion history
ls -lht promotion-report*.json | head -10

# Monthly: Archive old logs
mkdir -p logs/archive
mv promotion.log logs/archive/promotion.log.$(date +%Y%m%d)
```

### 6.2 Alerts & Notifications
Configure monitoring for:
- **Exit code != 0**: Promotion failed
- **"failed": > 0**: One or more files didn't promote
- **Log file size > 100MB**: Implement log rotation
- **No promotions in 30 days**: Verify system is still active

### 6.3 Periodic Validation
```bash
# Every week: Dry-run validation
make promote-dry

# Every month: Full test cycle
# 1. Modify a test file
# 2. Run promotion
# 3. Verify file and commit message
# 4. Run again and verify idempotence
```

---

## Troubleshooting

### Issue: "Token inválido o expirado"

**Cause**: GitLab token is invalid or expired

**Solutions**:
```bash
# 1. Check token file
cat /home/admin/Documents/GNP/PersonalGitLabToken

# 2. Verify token is in URL-safe format (no newlines)
wc -c /home/admin/Documents/GNP/PersonalGitLabToken
# Should be: 20 chars (or without newline)

# 3. Remove newline if present
tr -d '\n' < /home/admin/Documents/GNP/PersonalGitLabToken > /tmp/token.tmp
mv /tmp/token.tmp /home/admin/Documents/GNP/PersonalGitLabToken

# 4. Re-generate token from GitLab if expired
```

### Issue: "No se encontró proyecto: ..."

**Cause**: Project path is incorrect or not accessible

**Solutions**:
```bash
# 1. Verify project path in promotion-config.json
cat promotion-config.json | jq '.promotions[0].source.project'

# 2. Test API access directly
GITLAB_TOKEN=$(cat ../PersonalGitLabToken)
curl -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://gitlab.com/api/v4/projects/GROUP%2FPROJECT"
# Should return 200 with project details

# 3. Check GitLab permissions
# - Must have "Reporter" role minimum for source
# - Must have "Developer" role minimum for destination
```

### Issue: "Error al actualizar ...filenotfound"

**Cause**: Destination file path is incorrect

**Solutions**:
```bash
# 1. Verify destination path exists in target repo
# Visit: https://gitlab.com/GROUP/PROJECT/-/tree/BRANCH/PATH

# 2. Check if directory needs to be created
# - GitLab API doesn't auto-create directories
# - Must create parent directory structure first

# 3. Re-run setup to get correct path
make setup
```

### Issue: Slow execution (30+ seconds for single file)

**Cause**: Network latency or API rate limiting

**Solutions**:
```bash
# 1. Check network connectivity
ping -c 3 gitlab.com
# Should have < 100ms latency

# 2. Monitor API rate limit
GITLAB_TOKEN=$(cat ../PersonalGitLabToken)
curl -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  -i "https://gitlab.com/api/v4/user" 2>&1 | grep -i "rate-limit"
# Should show: RateLimit-Remaining: 599 (or similar)

# 3. If rate-limited, wait 1 minute and retry
```

### Issue: "Configuración inválida"

**Cause**: promotion-config.json has incorrect structure

**Solutions**:
```bash
# 1. Validate JSON syntax
python3 -m json.tool promotion-config.json

# 2. Check required fields exist
jq '.promotions[0] | keys' promotion-config.json
# Should contain: destination, dest_path, source, source_path

# 3. Regenerate config
rm promotion-config.json
make setup
```

---

## Rollback Procedure

If a problematic promotion occurs:

### 1. Stop Current Operations
```bash
# No running processes, but stop any scheduled tasks
```

### 2. Identify Problem Commit
```bash
# Check destination repo commit history
# Find problematic commit message (USER-TICKET-DATE format)
```

### 3. Revert in Destination Repo
```bash
# Option 1: UI Revert (GitLab Web)
# 1. Go to destination repo
# 2. Click on problematic commit
# 3. Click "Revert" button

# Option 2: CLI Revert
git clone https://gitlab.com/gitgnp/gcp/gke-config-files
cd gke-config-files
git revert COMMIT_HASH
git push origin master
```

### 4. Fix Source Issue
```bash
# Identify and fix problem in source repo
# Re-run promotion after fix verified
make promote
```

---

## Maintenance Tasks

### Weekly
```bash
# Check logs for errors
grep -i "error\|failed" promotion.log | tail -20

# Verify system still responsive
GITLAB_TOKEN=$(cat ../PersonalGitLabToken) \
  python3 promote-files.py --dry-run --config promotion-config.json
```

### Monthly
```bash
# Archive old logs
tar czf promotion.log.$(date +%Y%m).tar.gz promotion.log
rm promotion.log

# Review error patterns
zcat promotion.log.*.tar.gz | grep ERROR | wc -l

# Test disaster recovery scenario
# Simulate by reverting last 3 promotions, then re-run
```

### Quarterly
```bash
# Review and update documentation
# Test with different file types (YAML, JSON, configs)
# Audit access logs for unauthorized attempts
# Plan capacity upgrades if needed
```

---

## Success Checklist

- [ ] Python 3.6+ installed
- [ ] `requests` library installed (`make install`)
- [ ] GitLab token created with correct scopes
- [ ] Token stored securely in `PersonalGitLabToken`
- [ ] Source and destination repos accessible
- [ ] `promotion-config.json` generated and validated
- [ ] Dry-run successful with no errors
- [ ] First promotion successful
- [ ] Second run shows `skipped` status (idempotence verified)
- [ ] Commit message format verified (USER-TICKET-DATE)
- [ ] Monitoring setup configured
- [ ] Rollback procedure documented and tested

---

## Support & Documentation

- **Main Documentation**: `README.md`
- **Configuration Guide**: `promotion-config.json` structure
- **Production Analysis**: `PRODUCTION-ANALYSIS.md`
- **Error Logs**: `promotion.log`
- **Last Execution Report**: `promotion-report.json`

---

**Last Updated**: 2025  
**Status**: Production Ready ✅
