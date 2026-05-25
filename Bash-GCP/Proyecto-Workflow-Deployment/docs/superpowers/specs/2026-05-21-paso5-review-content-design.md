# Design: Paso 5 — Revisión de Contenido antes de Deploy

**Date:** 2026-05-21  
**File:** `workflow-deploy-interactive.sh`  
**Scope:** Insertar paso de revisión del YAML descargado entre validación y deploy.

---

## Problem

After pressing `1` in Step 4 (Confirmación), `execute_deployment` runs download → validate → deploy with no pause. The user cannot inspect the downloaded YAML content before `gcloud workflows deploy` fires.

---

## Solution

Add `step_5_review_content` function. Call it inside `execute_deployment` after `validate_workflow` and before `deploy_workflow`.

---

## Architecture

### New function: `step_5_review_content(yaml_file)`

- Clears screen, prints header "Paso 5: Revisión del Contenido"
- Displays `head -50 "$yaml_file"` in cyan
- Shows total line count: `wc -l < "$yaml_file"`
- Presents two options: `[1] Continuar con el despliegue` / `[0] Cancelar`
- Returns `0` to proceed, `1` to abort
- Recursive call on invalid input (same pattern as steps 3 and 4)

### Modified: `execute_deployment`

Insert one call after the validate block:

```
download_workflow  →  validate_workflow  →  step_5_review_content  →  deploy_workflow
```

`$temp_file` is in scope throughout `execute_deployment`. The `trap 'rm -f "$temp_file"' RETURN` already handles cleanup — no leak.

---

## Data Flow

```
Step 4: [1] →
  execute_deployment()
    download_workflow "$GITLAB_URL" "$temp_file"     # fetches YAML
    validate_workflow "$temp_file"                   # checks main: entry point
    step_5_review_content "$temp_file"               # NEW — shows head -50, waits
      [1] → continue
      [0] → return 1 → execute_deployment returns early (no deploy)
    deploy_workflow "$temp_file" ...                 # gcloud workflows deploy
```

---

## Changes

| Location | Change |
|---|---|
| `workflow-deploy-interactive.sh` | Add `step_5_review_content()` function |
| `execute_deployment()` | Add one call: `step_5_review_content "$temp_file" \|\| return 1` |

No changes to steps 1–4, `main` loop, or any other function.

---

## Error Handling

- Invalid input → recursive retry (same pattern as existing steps)
- User cancels → `execute_deployment` returns `1` → `main` loop does not prompt for another deployment
- `$temp_file` cleanup handled by existing `trap`

---

## Out of Scope

- Editing the YAML before deploy
- Saving a local copy
- Paginating with `less` (user chose head-50 preview)
