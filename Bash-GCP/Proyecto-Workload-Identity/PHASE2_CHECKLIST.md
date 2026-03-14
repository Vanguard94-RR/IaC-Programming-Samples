# FASE 2 - IMPLEMENTATION CHECKLIST

## Pre-Implementation (30 minutes)

### Environment Setup
- [ ] Go to project directory
  ```bash
  cd /home/admin/Documents/GNP/Repos/IaC-Programming-Samples/Bash-GCP/Proyecto-Workload-Identity
  ```
- [ ] Create backup of current script
  ```bash
  cp workload-identity.sh workload-identity.sh.phase1-backup
  ```
- [ ] Create feature branch
  ```bash
  git checkout -b feature/phase2-refactoring
  ```
- [ ] Verify current state
  ```bash
  bash -n workload-identity.sh  # Should pass
  ```

### Documentation Review
- [ ] Read PHASE2_PLAN.md (detailed plan)
- [ ] Read PHASE2_SUMMARY.md (visual overview)
- [ ] Have terminal open in VS Code
- [ ] Have editor ready for editing

---

## TASK 1: Extract select_cluster_from_project() Function (1.5 hrs)

### Step 1.1: Create the function (45 min)
- [ ] Open workload-identity.sh in editor
- [ ] Find location to insert: After `retry_gcloud_command()` function (around line 358)
- [ ] Create function stub with documentation
  ```bash
  # After line 358, add:
  # =============================================================================
  # Function: select_cluster_from_project
  # Description: Interactive cluster selection from GCP project
  # ...
  # =============================================================================
  select_cluster_from_project() {
      local project_id="$1"
      local prompt_msg="${2:-Select GKE cluster:}"
      
      # Implementation here...
  }
  ```
- [ ] Copy the cluster selection logic from operation_setup() (lines 750-780)
  - Get clusters with `list_gke_clusters()`
  - Parse into arrays (cluster_names, cluster_locations, cluster_options)
  - Show selection menu or auto-select if only 1
- [ ] Set output variables: `SELECTED_CLUSTER`, `SELECTED_LOCATION`
- [ ] Return codes: 0=success, 1=error/cancel
- [ ] Syntax check: `bash -n workload-identity.sh`
- [ ] Commit: `git add workload-identity.sh && git commit -m "feat: extract select_cluster_from_project function"`

### Step 1.2: Test the function (20 min)
- [ ] Create test script to verify:
  ```bash
  cat > test_select_cluster.sh << 'EOF'
  source ./workload-identity.sh
  
  # Test 1: Valid project (should list clusters)
  if select_cluster_from_project "gnp-contabilidad-qa"; then
      echo "✓ Test 1 passed: SELECTED_CLUSTER=$SELECTED_CLUSTER"
  else
      echo "✗ Test 1 failed"
  fi
  EOF
  ```
- [ ] Run test (will be interactive)
- [ ] Verify variables are set correctly

### Step 1.3: Documentation (15 min)
- [ ] Add comments to function
- [ ] Document parameters
- [ ] Document return values
- [ ] Document side effects (sets global variables)

---

## TASK 2: Refactor 4 Operations to Use New Function (2 hrs) ⭐ CRITICAL

### Step 2.1: Refactor operation_setup() (30 min)
- [ ] Find lines 750-780 (cluster selection block)
- [ ] Replace with:
  ```bash
  # --- Step 4: List and Select Cluster ---
  if ! select_cluster_from_project "$project_id"; then
      exit 1
  fi
  # Variables SELECTED_CLUSTER, SELECTED_LOCATION are now set
  local selected_cluster="$SELECTED_CLUSTER"
  local selected_location="$SELECTED_LOCATION"
  ```
- [ ] Remove the 30-line block that was replaced
- [ ] Verify remaining code works (echo statements reference `$selected_cluster` and `$selected_location`)
- [ ] Syntax check: `bash -n workload-identity.sh`
- [ ] **IMMEDIATE TEST**: Run script interactively, select option 1 (Setup), verify cluster selection works
- [ ] If OK: Commit `git commit -m "refactor(setup): use select_cluster_from_project"`
- [ ] If FAIL: Revert and debug

### Step 2.2: Refactor operation_verify() (30 min)
- [ ] Find lines 990-1020 (cluster selection block)
- [ ] Replace with same pattern as Step 2.1
- [ ] **IMMEDIATE TEST**: Run option 2 (Verify), verify cluster selection works
- [ ] Commit or rollback as needed

### Step 2.3: Refactor operation_cleanup() (30 min)
- [ ] Find lines 1270-1300 (cluster selection block)
- [ ] Replace with same pattern
- [ ] **IMMEDIATE TEST**: Run option 3 (Delete), verify cluster selection works
- [ ] Commit or rollback

### Step 2.4: Refactor operation_list() (30 min)
- [ ] Find lines 1550-1580 (cluster selection block)
- [ ] Replace with same pattern
- [ ] **IMMEDIATE TEST**: Run option 4 (List), verify cluster selection works
- [ ] Final commit: `git commit -m "refactor: consolidate cluster selection in all operations (DRY)"`

### After Task 2.4: VERIFICATION
- [ ] Bash syntax: `bash -n workload-identity.sh` ✓
- [ ] Manual test all 4 operations with cluster selection ✓
- [ ] Line count reduced significantly ✓
- [ ] Commit history shows 4+ commits ✓

---

## TASK 3: Add Logging to 6 Functions (1.5 hrs) [PARALLEL OK with Tasks 4-6]

### Step 3.1: Add logging to verify_iam_sa() (~15 min)
- [ ] Find function at line ~409
- [ ] Add before first command:
  ```bash
  log "Verifying IAM Service Account: $sa_email"
  ```
- [ ] Add after success:
  ```bash
  log "✓ IAM SA exists: $sa_email"
  ```
- [ ] Add after failure:
  ```bash
  log "⚠ IAM SA not found: $sa_email"
  ```

### Step 3.2: Add logging to verify_ksa() (~15 min)
- [ ] Similar pattern as 3.1

### Step 3.3: Add logging to delete_ksa() (~15 min)
- [ ] Add pre-deletion log
- [ ] Add success/failure logs

### Step 3.4: Add logging to get_ksa_annotation() (~10 min)
- [ ] Light logging (function called often)

### Step 3.5: Add logging to get_current_project() (~10 min)
- [ ] Light logging

### Step 3.6: Add logging to list_gke_clusters() (~10 min)
- [ ] Light logging

### After Task 3: VERIFICATION
- [ ] All 6 functions have log() calls
- [ ] Syntax check passes
- [ ] Commit: `git commit -m "chore: add comprehensive logging to utility functions"`

---

## TASK 4: Remove Dead Code (0.5 hrs) [PARALLEL OK]

### Step 4.1: Locate and remove
- [ ] Find lines 503-507 in `list_workload_identities()`
- [ ] Identify the dead variable: `local found=false`
- [ ] Check if `found` is used anywhere in the function
  ```bash
  # Search in function for 'found'
  grep -n "found" workload-identity.sh | grep -E "50[0-9]:"
  ```
- [ ] If `found` only appears in lines 503-507: SAFE TO REMOVE
- [ ] Remove these lines:
  ```bash
  local found=false
  # ... (but KEEP the rest of the logic)
  if [[ -n "$ksa" ]]; then
      found=false  # ← REMOVE THIS LINE
  fi
  ```
- [ ] Syntax check
- [ ] Manual test: Run option 4 (List)

### After Task 4: VERIFICATION
- [ ] Dead code removed
- [ ] Function still works correctly
- [ ] Commit: `git commit -m "chore: remove dead code in list_workload_identities"`

---

## TASK 5: Create config.sh (0.5 hrs) [PARALLEL OK]

### Step 5.1: Create new file
- [ ] Create new file `config.sh` in same directory as workload-identity.sh
- [ ] Add header comments
- [ ] Add all 12 environment variables with defaults:
  ```bash
  export WI_IAM_ROLE="${WI_IAM_ROLE:-roles/iam.workloadIdentityUser}"
  export WI_DEFAULT_NAMESPACE="${WI_DEFAULT_NAMESPACE:-apps}"
  export WI_ANNOTATION_KEY="${WI_ANNOTATION_KEY:-iam.gke.io/gcp-service-account}"
  export WI_REGISTRY_FILE="${WI_REGISTRY_FILE:-workload-identity-registry.csv}"
  # ... etc (see PHASE2_PLAN.md for full list)
  ```
- [ ] Add header with copyright/license/purpose
- [ ] Add inline comments for each variable explaining usage

### Step 5.2: Verify structure
- [ ] Bash syntax: `bash -n config.sh` ✓
- [ ] Verify all 12 variables are defined ✓

### After Task 5: VERIFICATION
- [ ] config.sh exists and is valid
- [ ] Commit: `git add config.sh && git commit -m "feat: add external configuration file"`

---

## TASK 6: Replace Hard-Coded Values (1 hr) [PARALLEL OK]

### Step 6.1: Load config in workload-identity.sh
- [ ] Find line ~45 (after color definitions)
- [ ] Add configuration loading:
  ```bash
  # --- Load Configuration ---
  readonly CONFIG_DIR="$(dirname "${BASH_SOURCE[0]}")"
  if [[ -f "$CONFIG_DIR/config.sh" ]]; then
      source "$CONFIG_DIR/config.sh"
  fi
  
  # Use config values with fallbacks
  readonly G_IAM_ROLE="${WI_IAM_ROLE:-roles/iam.workloadIdentityUser}"
  readonly G_ANNOTATION_KEY="${WI_ANNOTATION_KEY:-iam.gke.io/gcp-service-account}"
  ```

### Step 6.2: Replace hard-coded IAM role
- [ ] Find line ~491 in `add_iam_binding()`
- [ ] Change from:
  ```bash
  --role "roles/iam.workloadIdentityUser"
  ```
  To:
  ```bash
  --role "$G_IAM_ROLE"
  ```
- [ ] Syntax check

### Step 6.3: Replace hard-coded annotation key
- [ ] Find lines ~442, 480 (2 occurrences)
- [ ] Change from:
  ```bash
  "iam.gke.io/gcp-service-account=\"${iam_sa_email}\""
  ```
  To:
  ```bash
  "${G_ANNOTATION_KEY}=\"${iam_sa_email}\""
  ```
- [ ] Syntax check

### Step 6.4: Replace hard-coded namespace default
- [ ] Find line ~63 (G_NAMESPACE definition)
- [ ] Change from:
  ```bash
  G_NAMESPACE="apps"
  ```
  To:
  ```bash
  G_NAMESPACE="${WI_DEFAULT_NAMESPACE:-apps}"
  ```
- [ ] Verify operation_setup() uses this variable

### After Task 6: VERIFICATION
- [ ] All hard-coded values replaced
- [ ] Bash syntax check passes
- [ ] config.sh loads correctly
- [ ] Defaults work if config.sh missing
- [ ] Commit: `git commit -m "refactor: externalize configuration values"`

---

## TASK 7: Testing & Validation (1.5 hrs)

### Step 7.1: Syntax Validation (15 min)
- [ ] `bash -n workload-identity.sh`
  ```bash
  bash -n workload-identity.sh
  echo "Exit code: $?"  # Should be 0
  ```
- [ ] `bash -n config.sh`

### Step 7.2: Unit Tests (30 min)
- [ ] Test select_cluster_from_project()
  - [ ] Test with valid project (interactive)
  - [ ] Test cancel (press N)
  - [ ] Verify SELECTED_CLUSTER and SELECTED_LOCATION are set

- [ ] Test logging in verify_iam_sa()
  - [ ] Create temp log directory
  - [ ] Call function
  - [ ] Verify log output contains expected messages

- [ ] Test config loading
  - [ ] With config.sh present
  - [ ] Without config.sh (should use defaults)
  - [ ] With environment variable override

### Step 7.3: Integration Tests (45 min)
**Test each operation end-to-end** (interactive, don't actually create resources):

- [ ] Operation 1: Setup
  - [ ] Input: project_id
  - [ ] Input: IAM SA name
  - [ ] Input: KSA name
  - [ ] Select cluster (using new function)
  - [ ] Input: namespace
  - [ ] Confirmation
  - [ ] Verify logs written
  - [ ] **Cancel before creating** (type N at confirmation)

- [ ] Operation 2: Verify
  - [ ] Verify cluster selection works (using new function)
  - [ ] Verify logging works

- [ ] Operation 3: Delete
  - [ ] Verify cluster selection works (using new function)
  - [ ] Verify double-confirm works (Phase 1 feature)
  - [ ] Cancel operation

- [ ] Operation 4: List
  - [ ] Verify cluster selection works (using new function)
  - [ ] Verify output (may be empty if no WIs)

- [ ] Operation 5: View Registry
  - [ ] Verify can list any existing records

### Step 7.4: Regression Tests (20 min)
**Verify Phase 1 fixes still work**:

- [ ] `jq` dependency check
  - [ ] Script starts (jq available)
  - [ ] ✓ Should work

- [ ] Validation functions
  - [ ] Invalid project ID → Should reject
  - [ ] Invalid KSA name → Should reject
  - [ ] Invalid namespace → Should warn

- [ ] Double-confirm delete
  - [ ] Delete operation requires "CONFIRM" text
  - [ ] ✓ Should work

- [ ] CSV file permissions
  - [ ] Verify workload-identity-registry.csv has 600 permissions
  - [ ] ✓ Should be restricted

- [ ] Token refresh
  - [ ] Main menu shows
  - [ ] ✓ Auth check passed

### Step 7.5: Final Validation
- [ ] Line count: `wc -l workload-identity.sh` (should be ~1700 ±50)
- [ ] No TODO comments left in code
- [ ] All Phase 1 fixes still working
- [ ] Commit: `git commit -m "test: verify Phase 2 changes (unit, integration, regression)"`

---

## TASK 8: Documentation (0.5 hrs)

### Step 8.1: Create PHASE2_COMPLETE.md
- [ ] Summarize changes applied
- [ ] List all commits from Phase 2
- [ ] Include metrics (before/after line counts)
- [ ] List test results
- [ ] Document config.sh variables

### Step 8.2: Update README.md (if exists)
- [ ] Add note about config.sh
- [ ] Link to PHASE2_COMPLETE.md

### Step 8.3: Create git tag
- [ ] `git tag -a v2.0-phase2 -m "Phase 2: Refactoring & Code Quality"`

### After Task 8: FINAL VERIFICATION
- [ ] `git log --oneline` shows Phase 2 commits
- [ ] All files committed
- [ ] Tag created

---

## POST-IMPLEMENTATION: Code Review

### Self-Review Checklist
- [ ] No new bugs introduced
- [ ] Phase 1 fixes still present
- [ ] Code is DRY (no duplication)
- [ ] Logging is consistent
- [ ] Comments are clear
- [ ] Configuration is flexible
- [ ] Bash style is consistent

### Verification Checklist
```bash
# Quick validation commands
bash -n workload-identity.sh && echo "✓ Syntax OK"
wc -l workload-identity.sh
grep -c "log " workload-identity.sh  # Should be many
grep -c "select_cluster_from_project" workload-identity.sh  # Should be 4-5
stat -c "%a" workload-identity-registry.csv  # Should be 600
```

---

## ROLLBACK PROCEDURE (If Something Goes Wrong)

### Option 1: Rollback Last Commit Only
```bash
git revert HEAD
```

### Option 2: Rollback to Post-Phase1 State
```bash
git checkout HEAD~8 -- workload-identity.sh
cp workload-identity.sh.phase1-backup workload-identity.sh  # Alternative
```

### Option 3: Start Over
```bash
rm workload-identity.sh config.sh
git checkout origin/main -- workload-identity.sh
cp workload-identity.sh.phase1-backup workload-identity.sh
```

---

## FINAL CHECKLIST: Phase 2 DONE ✅

- [ ] TASK 1: select_cluster_from_project() function created and tested
- [ ] TASK 2: 4 operations refactored to use new function
- [ ] TASK 3: 6 functions have logging added
- [ ] TASK 4: Dead code (5 lines) removed
- [ ] TASK 5: config.sh created with 12 variables
- [ ] TASK 6: Hard-coded values replaced with config references
- [ ] TASK 7: All tests pass (unit, integration, regression)
- [ ] TASK 8: Documentation complete
- [ ] Line count: 1,953 → ~1,700 (±50)
- [ ] Bash syntax: ✓ Passes
- [ ] Phase 1 fixes: ✓ Still work
- [ ] Git: All commits made
- [ ] Git: Tag created (v2.0-phase2)

**Phase 2 Status**: ✅ COMPLETE

---

## Next Steps

Once Phase 2 is complete:

1. **Create PR/MR** with summary of changes
2. **Get code review** (optional)
3. **Merge to main** branch
4. **Plan Phase 3**: Production features (CLI mode, dry-run, bulk operations)
5. **Estimate Phase 3 effort**: 12-14 hours

---

**Owner**: Implementation Team  
**Duration**: 8.5 hours (1 working day)  
**Status**: 📋 Ready to Execute  
**Last Updated**: March 13, 2026
