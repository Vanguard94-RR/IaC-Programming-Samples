package executor

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// writeScript creates a bash script in dir with the given body and returns its path.
func writeScript(t *testing.T, dir, name, body string) {
	t.Helper()
	path := filepath.Join(dir, name)
	content := "#!/usr/bin/env bash\nset -euo pipefail\n" + body + "\n"
	if err := os.WriteFile(path, []byte(content), 0755); err != nil {
		t.Fatalf("writeScript %s: %v", name, err)
	}
}

// writeSuccessPhases writes all 3 scripts that exit 0 with logged output.
func writeSuccessPhases(t *testing.T, dir string) {
	t.Helper()
	writeScript(t, dir, "validate-pre.sh", `echo "[PRE] OK"`)
	writeScript(t, dir, "execute.sh", `echo "[EXEC] done"`)
	writeScript(t, dir, "validate.sh", `echo "[VAL] OK"`)
}

func TestRunSuccess(t *testing.T) {
	dir := t.TempDir()
	writeSuccessPhases(t, dir)

	result, err := Run("CTASK0001", dir, 10*time.Second)
	if err != nil {
		t.Fatalf("Run() error: %v", err)
	}
	if !result.Success {
		t.Error("expected Success=true")
	}
	if result.FailedPhase != "" {
		t.Errorf("expected no FailedPhase, got %q", result.FailedPhase)
	}
	if len(result.Phases) != 3 {
		t.Errorf("expected 3 phases, got %d", len(result.Phases))
	}
	for _, p := range result.Phases {
		if p.ExitCode != 0 {
			t.Errorf("phase %s: expected exit 0, got %d", p.Phase, p.ExitCode)
		}
	}
}

func TestRunPhaseNames(t *testing.T) {
	dir := t.TempDir()
	writeSuccessPhases(t, dir)

	result, _ := Run("CTASK0002", dir, 10*time.Second)
	wantPhases := []string{PhaseValidatePre, PhaseExecute, PhaseValidate}
	for i, want := range wantPhases {
		if result.Phases[i].Phase != want {
			t.Errorf("phases[%d].Phase = %q, want %q", i, result.Phases[i].Phase, want)
		}
	}
}

func TestRunOutputCaptured(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "validate-pre.sh", `echo "stdout-pre"; echo "stderr-pre" >&2`)
	writeScript(t, dir, "execute.sh", `echo "stdout-exec"`)
	writeScript(t, dir, "validate.sh", `echo "stdout-val"`)

	result, err := Run("CTASK0003", dir, 10*time.Second)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	pre := result.Phases[0]
	if !strings.Contains(pre.Stdout, "stdout-pre") {
		t.Errorf("Stdout: expected 'stdout-pre', got %q", pre.Stdout)
	}
	if !strings.Contains(pre.Stderr, "stderr-pre") {
		t.Errorf("Stderr: expected 'stderr-pre', got %q", pre.Stderr)
	}
}

func TestRunValidatePreFailure(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "validate-pre.sh", `echo "pre failed" >&2; exit 1`)
	writeScript(t, dir, "execute.sh", `echo "should not run"`)
	writeScript(t, dir, "validate.sh", `echo "should not run"`)

	result, err := Run("CTASK0004", dir, 10*time.Second)
	if err != nil {
		t.Fatalf("unexpected Go error: %v", err)
	}
	if result.Success {
		t.Error("expected Success=false")
	}
	if result.FailedPhase != PhaseValidatePre {
		t.Errorf("FailedPhase = %q, want %q", result.FailedPhase, PhaseValidatePre)
	}
	// execute.sh must NOT have run
	if len(result.Phases) != 1 {
		t.Errorf("expected 1 phase run, got %d", len(result.Phases))
	}
	if result.Phases[0].ExitCode != 1 {
		t.Errorf("expected exit code 1, got %d", result.Phases[0].ExitCode)
	}
}

func TestRunExecuteFailure(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "validate-pre.sh", `echo "pre OK"`)
	writeScript(t, dir, "execute.sh", `echo "exec failed" >&2; exit 2`)
	writeScript(t, dir, "validate.sh", `echo "should not run"`)

	result, err := Run("CTASK0005", dir, 10*time.Second)
	if err != nil {
		t.Fatalf("unexpected Go error: %v", err)
	}
	if result.Success {
		t.Error("expected Success=false")
	}
	if result.FailedPhase != PhaseExecute {
		t.Errorf("FailedPhase = %q, want %q", result.FailedPhase, PhaseExecute)
	}
	if len(result.Phases) != 2 {
		t.Errorf("expected 2 phases run, got %d", len(result.Phases))
	}
	if result.Phases[1].ExitCode != 2 {
		t.Errorf("execute phase exit code = %d, want 2", result.Phases[1].ExitCode)
	}
}

func TestRunScriptNotFound(t *testing.T) {
	dir := t.TempDir()
	// Only create validate-pre.sh; execute.sh is missing
	writeScript(t, dir, "validate-pre.sh", `echo "OK"`)

	_, err := Run("CTASK0006", dir, 10*time.Second)
	if err == nil {
		t.Fatal("expected error for missing script, got nil")
	}
	if !strings.Contains(err.Error(), "execute.sh") {
		t.Errorf("error should mention missing script: %v", err)
	}
}

func TestRunTimeout(t *testing.T) {
	dir := t.TempDir()
	writeScript(t, dir, "validate-pre.sh", `sleep 30`)
	writeScript(t, dir, "execute.sh", `echo "should not reach"`)
	writeScript(t, dir, "validate.sh", `echo "should not reach"`)

	start := time.Now()
	_, err := Run("CTASK0007", dir, 200*time.Millisecond)
	elapsed := time.Since(start)

	if err == nil {
		t.Fatal("expected timeout error, got nil")
	}
	if elapsed > 5*time.Second {
		t.Errorf("timeout took too long: %s", elapsed)
	}
	if !strings.Contains(err.Error(), "timeout") && !strings.Contains(err.Error(), "context") {
		t.Errorf("expected timeout error, got: %v", err)
	}
}

func TestRunEmptyTicketID(t *testing.T) {
	dir := t.TempDir()
	writeSuccessPhases(t, dir)
	// Empty TicketID is allowed by executor — it's the generator/parser that validates
	result, err := Run("", dir, 10*time.Second)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.TicketID != "" {
		t.Errorf("TicketID = %q, expected empty", result.TicketID)
	}
}

func TestResultSummary(t *testing.T) {
	dir := t.TempDir()
	writeSuccessPhases(t, dir)

	result, _ := Run("CTASK0008", dir, 10*time.Second)
	summary := result.Summary()

	for _, want := range []string{PhaseValidatePre, PhaseExecute, PhaseValidate, "exit=0"} {
		if !strings.Contains(summary, want) {
			t.Errorf("Summary() missing %q:\n%s", want, summary)
		}
	}
}

func TestPhaseResultOK(t *testing.T) {
	p := PhaseResult{ExitCode: 0}
	if !p.OK() {
		t.Error("ExitCode=0 should be OK")
	}
	p.ExitCode = 1
	if p.OK() {
		t.Error("ExitCode=1 should not be OK")
	}
}

func TestDefaultTimeout(t *testing.T) {
	if DefaultTimeout != 5*time.Minute {
		t.Errorf("DefaultTimeout = %s, want 5m", DefaultTimeout)
	}
}
