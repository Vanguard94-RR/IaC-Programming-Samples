package executor

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// Phase names used to identify each execution step.
const (
	PhaseValidatePre = "validate-pre"
	PhaseExecute     = "execute"
	PhaseValidate    = "validate"
)

// DefaultTimeout is the per-phase timeout when none is specified.
const DefaultTimeout = 5 * time.Minute

// PhaseResult captures the outcome of one bash script phase.
type PhaseResult struct {
	Phase    string
	Script   string
	ExitCode int
	Stdout   string
	Stderr   string
	Duration time.Duration
}

// OK reports whether the phase completed successfully (exit code 0).
func (p PhaseResult) OK() bool { return p.ExitCode == 0 }

// Result is the complete execution outcome for a ticket.
type Result struct {
	TicketID string
	Phases   []PhaseResult
	Success  bool
	// FailedPhase is the name of the phase that caused failure, or "" if success.
	FailedPhase string
}

// Summary returns a human-readable multi-line summary of all phases.
func (r *Result) Summary() string {
	var sb strings.Builder
	for _, p := range r.Phases {
		status := "OK  "
		if p.ExitCode != 0 {
			status = "FAIL"
		}
		sb.WriteString(fmt.Sprintf("  [%s] %-14s exit=%d  %s\n",
			status, p.Phase, p.ExitCode, p.Duration.Round(time.Millisecond)))
	}
	return sb.String()
}

// Run executes validate-pre.sh → execute.sh → validate.sh in scriptsDir.
// timeout is applied to each individual phase; pass 0 to use DefaultTimeout.
// Returns a non-nil error only for OS-level failures (script missing, permission
// denied, context error). A script exiting with non-zero is captured in
// Result.FailedPhase, not as a Go error.
func Run(ticketID, scriptsDir string, timeout time.Duration) (*Result, error) {
	if timeout <= 0 {
		timeout = DefaultTimeout
	}

	phases := []struct {
		name   string
		script string
	}{
		{PhaseValidatePre, "validate-pre.sh"},
		{PhaseExecute, "execute.sh"},
		{PhaseValidate, "validate.sh"},
	}

	result := &Result{TicketID: ticketID}

	for _, p := range phases {
		scriptPath := filepath.Join(scriptsDir, p.script)
		if _, err := os.Stat(scriptPath); err != nil {
			return result, fmt.Errorf("script no encontrado %q: %w", p.script, err)
		}

		ctx, cancel := context.WithTimeout(context.Background(), timeout)
		phaseResult, err := runPhase(ctx, p.name, scriptPath)
		cancel()

		result.Phases = append(result.Phases, phaseResult)

		if err != nil {
			// OS-level error (timeout, permission denied, etc.)
			result.FailedPhase = p.name
			return result, fmt.Errorf("fase %s: %w", p.name, err)
		}
		if !phaseResult.OK() {
			result.FailedPhase = p.name
			return result, nil // script failure — captured in result, not a Go error
		}
	}

	result.Success = true
	return result, nil
}

func runPhase(ctx context.Context, phase, scriptPath string) (PhaseResult, error) {
	start := time.Now()
	res := PhaseResult{
		Phase:  phase,
		Script: scriptPath,
	}

	var stdout, stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, "bash", scriptPath)
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	// Put the command in its own process group so that Cancel() kills bash and
	// all its children (e.g. a "sleep 30" spawned by the script). Without this,
	// orphaned children keep stdout/stderr pipes open, blocking cmd.Wait().
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return nil
		}
		// Negative PID kills the entire process group.
		return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
	}

	runErr := cmd.Run()
	res.Duration = time.Since(start)
	res.Stdout = stdout.String()
	res.Stderr = stderr.String()

	if runErr == nil {
		return res, nil
	}

	// Check context first — deadline exceeded takes precedence over exit code.
	if ctx.Err() != nil {
		res.ExitCode = -1
		return res, fmt.Errorf("timeout después de %s: %w",
			res.Duration.Round(time.Second), ctx.Err())
	}

	// Script exited with non-zero code — phase failure, not an OS error.
	var exitErr *exec.ExitError
	if errors.As(runErr, &exitErr) {
		res.ExitCode = exitErr.ExitCode()
		return res, nil
	}

	return res, runErr
}
