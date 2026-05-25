# Paso 5 — Revisión de Contenido antes de Deploy

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a review step inside `execute_deployment` that shows the first 50 lines of the downloaded YAML and asks the user to confirm before `gcloud workflows deploy` runs.

**Architecture:** Single new function `step_5_review_content(yaml_file)` inserted between `validate_workflow` and `deploy_workflow` inside `execute_deployment`. Returns 0 to proceed, 1 to abort. No changes to steps 1–4, `main` loop, or any other function.

**Tech Stack:** Bash, `head`, `wc -l`, ANSI color codes (same pattern as existing step functions).

---

### Task 1: Add `step_5_review_content` function

**Files:**
- Modify: `workflow-deploy-interactive.sh` — insert new function after line 286 (end of `step_4_preview`), before line 292 (`parse_gitlab_url`)

- [ ] **Step 1: Open the file and locate insertion point**

Find the blank line between `step_4_preview` and `parse_gitlab_url`. In the file that is around line 288–291:

```bash
    esac
}

################################################################################
# Deployment Execution
################################################################################
```

- [ ] **Step 2: Insert the new function**

Add the following block between the closing `}` of `step_4_preview` and the `################################# Deployment Execution` separator:

```bash
step_5_review_content() {
    local yaml_file="$1"

    clear_screen
    print_header "Paso 5: Revisión del Contenido"

    local total_lines
    total_lines=$(wc -l < "$yaml_file")

    echo -e "${GRAY}Primeras 50 líneas del workflow descargado (${total_lines} líneas totales):${NC}\n"
    echo -e "${CYAN}$(head -50 "$yaml_file")${NC}"
    echo ""

    echo -e "${GRAY}¿Qué deseas hacer?${NC}\n"
    echo -e "  ${LCYAN}1)${NC} Continuar con el despliegue"
    echo -e "  ${LCYAN}0)${NC} Cancelar"
    echo ""

    echo -ne "${YELLOW}Opción${NC}: "
    read -r choice

    case "$choice" in
        1) return 0 ;;
        0) return 1 ;;
        *)
            print_error "Opción inválida"
            step_5_review_content "$yaml_file"
            return $?
            ;;
    esac
}
```

- [ ] **Step 3: Verify syntax**

```bash
bash -n workflow-deploy-interactive.sh
```

Expected: no output (no syntax errors).

---

### Task 2: Call `step_5_review_content` inside `execute_deployment`

**Files:**
- Modify: `workflow-deploy-interactive.sh` — insert 2 lines inside `execute_deployment`, after the validate block and before the DRY_RUN check

- [ ] **Step 1: Locate insertion point in `execute_deployment`**

Find this block (around line 426–432 after Task 1 edit):

```bash
    # Validar
    if [[ "$SKIP_VALIDATION" != "true" ]]; then
        validate_workflow "$temp_file" || return 1
        echo ""
    fi

    # Desplegar
    if [[ "$DRY_RUN" == "true" ]]; then
```

- [ ] **Step 2: Insert review call between validate and deploy**

Replace that block with:

```bash
    # Validar
    if [[ "$SKIP_VALIDATION" != "true" ]]; then
        validate_workflow "$temp_file" || return 1
        echo ""
    fi

    # Revisar contenido antes de deployar
    step_5_review_content "$temp_file" || return 1
    echo ""

    # Desplegar
    if [[ "$DRY_RUN" == "true" ]]; then
```

- [ ] **Step 3: Verify syntax**

```bash
bash -n workflow-deploy-interactive.sh
```

Expected: no output.

- [ ] **Step 4: Manual smoke test — cancel at Step 5**

```bash
./workflow-deploy-interactive.sh
```

Walk through steps 1–4 with any valid inputs. At Step 5, press `0`.

Expected:
- Step 5 screen appears with header "Paso 5: Revisión del Contenido"
- First 50 lines of YAML shown in cyan
- Total line count displayed
- Pressing `0` exits without deploying (no `gcloud` call)

- [ ] **Step 5: Manual smoke test — invalid option at Step 5**

Repeat and enter `9` at Step 5 prompt.

Expected:
- "✗ Opción inválida" printed
- Step 5 re-displays (recursive retry)

- [ ] **Step 6: Manual smoke test — DRY-RUN through Step 5**

Run again, choose DRY-RUN mode (Step 3 option 2), continue through Step 4, press `1` at Step 5.

Expected:
- Step 5 appears after download+validate
- Pressing `1` reaches DRY-RUN output: `"DRY-RUN: Comando no ejecutado"` + gcloud command echo
- No actual `gcloud` call

- [ ] **Step 7: Commit**

```bash
git add workflow-deploy-interactive.sh
git commit -m "feat: add step 5 YAML content review before deploy"
```
