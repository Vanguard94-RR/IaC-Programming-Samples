// gnp-agent — Agente IA para ejecución autónoma de tickets GCP (GNP Seguros)
//
// Uso:
//
//	gnp-agent                         # Lee ticket desde stdin (terminar con Ctrl+D)
//	gnp-agent -ticket ticket.txt      # Lee ticket desde archivo
//	gnp-agent -dry-run                # Parsea y genera scripts sin ejecutar
//	gnp-agent -status                 # Muestra estado de tickets de la sesión
package main

import (
	"bufio"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"gnp-agent/internal/executor"
	"gnp-agent/internal/gate"
	"gnp-agent/internal/generator"
	"gnp-agent/internal/governance"
	"gnp-agent/internal/parser"
	"gnp-agent/internal/state"
)

// Paths de configuración del entorno GNP
const (
	ticketsDir    = "/home/admin/Documents/GNP/Tickets"
	stateDir      = "/home/admin/Documents/GNP/Repos/IaC-Programming-Samples/IA-Agent-GCP-GO-GNP/state"
	gitlabToken   = "/home/admin/Documents/GNP/PersonalGitLabToken"
	iamXLSXPath   = "/home/admin/Documents/GNP/Proyecto-Permisos-IAM/Plantilla de Permisos IAM.xlsx"
	dlkXLSXPath   = "/home/admin/Documents/GNP/Proyecto-Permisos-IAM/Plantilla Permisos DLK V3.0.xlsx"
	sessionMDPath = "/home/admin/Documents/GNP/Tickets/SESSION_PROGRESS.md"
)

func main() {
	// Flags
	ticketFile   := flag.String("ticket", "", "archivo de texto con el ticket (default: stdin)")
	dryRun       := flag.Bool("dry-run", false, "parsear y generar scripts sin ejecutar")
	showStatus   := flag.Bool("status", false, "mostrar estado de tickets de la sesión")
	skipDLK      := flag.Bool("skip-dlk", false, "omitir DLK gate (solo para pruebas)")
	phaseTimeout := flag.Duration("phase-timeout", executor.DefaultTimeout, "timeout por fase de ejecución")
	flag.Parse()

	// Resolver ANTHROPIC_API_KEY
	if os.Getenv("ANTHROPIC_API_KEY") == "" {
		for _, candidate := range []string{
			os.Getenv("HOME") + "/.config/gnp-agent/api_key",
			os.Getenv("HOME") + "/.anthropic_api_key",
		} {
			if data, err := os.ReadFile(candidate); err == nil {
				key := strings.TrimSpace(string(data))
				if key != "" {
					os.Setenv("ANTHROPIC_API_KEY", key)
					break
				}
			}
		}
	}

	// Inicializar state manager
	mgr, err := state.New(stateDir)
	if err != nil {
		fatalf("Error iniciando state manager: %v", err)
	}

	// Modo status
	if *showStatus {
		printSessionStatus(mgr)
		return
	}

	// Leer texto del ticket
	rawText, err := readInput(*ticketFile)
	if err != nil {
		fatalf("Error leyendo ticket: %v", err)
	}
	if strings.TrimSpace(rawText) == "" {
		fatalf("Ticket vacío — proporciona texto por stdin o con -ticket archivo.txt")
	}

	// ─── FASE 1: PARSE ───────────────────────────────────────────────────────
	printSection("PARSING TICKET")
	start := time.Now()

	ticket, err := parser.Parse(rawText)
	if err != nil {
		fatalf("Error parseando ticket: %v", err)
	}

	fmt.Printf("  TicketID  : %s\n", ticket.TicketID)
	fmt.Printf("  Proyecto  : %s\n", ticket.ProjectID)
	fmt.Printf("  Tipo      : %s\n", ticket.TaskType)
	fmt.Printf("  Principals: %d\n", len(ticket.Principals))
	for _, p := range ticket.Principals {
		fmt.Printf("              %s\n", p.MemberStr())
	}
	if len(ticket.AllRoles()) > 0 {
		fmt.Printf("  Roles     : %s\n", strings.Join(ticket.AllRoles(), ", "))
	}
	fmt.Printf("  Entornos  : %s\n", strings.Join(ticket.Environments, ", "))
	fmt.Printf("  Parse time: %s\n", time.Since(start).Round(time.Millisecond))

	// ─── STANDBY inmediato si hay campos ambiguos ─────────────────────────────
	if ticket.HasAmbiguous() {
		printStandbyBox(ticket)
		if err := mgr.Save(ticket.TicketID, ticket.ProjectID, string(ticket.TaskType),
			state.StateStandby, state.DLKGateNA,
			"Campos ambiguos: "+strings.Join(ticket.Ambiguous, ", "),
			ticket.Ambiguous); err != nil {
			fmt.Fprintf(os.Stderr, "WARN: no se pudo guardar estado: %v\n", err)
		}
		if err := mgr.WriteSessionProgress(sessionMDPath); err != nil {
			fmt.Fprintf(os.Stderr, "WARN: no se pudo escribir SESSION_PROGRESS.md: %v\n", err)
		}
		return
	}

	// ─── FASE 2: DLK GATE ─────────────────────────────────────────────────────
	printSection("DLK GATE")
	var dlkStatus state.DLKGateStatus

	if *skipDLK {
		fmt.Printf("  ⚠  DLK gate omitido por -skip-dlk\n")
		dlkStatus = state.DLKGatePassed
	} else {
		dlkResult := gate.Check(ticket)
		dlkStatus = dlkResult.Status
		switch dlkResult.Status {
		case state.DLKGateNA:
			fmt.Printf("  ✓ N/A — proyecto no DLK\n")
		case state.DLKGatePassed:
			fmt.Printf("  ✓ PASSED — %s\n", dlkResult.Reason)
		case state.DLKGateBlocked:
			fmt.Printf("  ✗ BLOQUEADO — %s\n", dlkResult.Reason)
			if err := mgr.Save(ticket.TicketID, ticket.ProjectID, string(ticket.TaskType),
				state.StateBlocked, dlkStatus, dlkResult.Reason, nil); err != nil {
				fmt.Fprintf(os.Stderr, "WARN: no se pudo guardar estado: %v\n", err)
			}
			if err := mgr.WriteSessionProgress(sessionMDPath); err != nil {
				fmt.Fprintf(os.Stderr, "WARN: no se pudo escribir SESSION_PROGRESS.md: %v\n", err)
			}
			printFinalBox(ticket, "BLOCKED", dlkStatus, false)
			return
		}
	}

	// ─── FASE 3: GENERATE SCRIPTS ─────────────────────────────────────────────
	printSection("SCRIPT GENERATION")
	scriptsDir := fmt.Sprintf("%s/%s/scripts", ticketsDir, ticket.TicketID)
	fmt.Printf("  Destino  : %s\n", scriptsDir)
	fmt.Printf("  Template : %s\n", ticket.TaskType)

	genErr := generator.Generate(ticket, scriptsDir)
	if genErr != nil {
		if errors.Is(genErr, generator.ErrUnsupportedTask) {
			fmt.Printf("  ⚠  %v\n", genErr)
			fmt.Printf("  Archivos NO generados — task_type no soportado aún\n")
		} else {
			fatalf("Error generando scripts: %v", genErr)
		}
	} else {
		fmt.Printf("  Archivos: config.env, validate-pre.sh, execute.sh, validate.sh\n")
		fmt.Printf("  OK — scripts generados en %s\n", scriptsDir)
	}

	if *dryRun {
		fmt.Println()
		fmt.Println("  [DRY-RUN] Detenido antes de ejecutar.")
		dryState := state.StatePending
		if genErr == nil {
			dryState = state.StateValidated
		}
		if err := mgr.Save(ticket.TicketID, ticket.ProjectID, string(ticket.TaskType),
			dryState, dlkStatus, "dry-run", nil); err != nil {
			fmt.Fprintf(os.Stderr, "WARN: no se pudo guardar estado: %v\n", err)
		}
		printFinalBox(ticket, "DRY-RUN", dlkStatus, false)
		return
	}

	// Si los scripts no existen (task type no soportado), guardar PENDING y salir
	if genErr != nil {
		if err := mgr.Save(ticket.TicketID, ticket.ProjectID, string(ticket.TaskType),
			state.StatePending, dlkStatus, "task_type sin template", nil); err != nil {
			fmt.Fprintf(os.Stderr, "WARN: no se pudo guardar estado: %v\n", err)
		}
		if err := mgr.WriteSessionProgress(sessionMDPath); err != nil {
			fmt.Fprintf(os.Stderr, "WARN: no se pudo escribir SESSION_PROGRESS.md: %v\n", err)
		}
		printFinalBox(ticket, "PENDING", dlkStatus, false)
		return
	}

	// ─── FASE 4: EXECUTE ──────────────────────────────────────────────────────
	printSection("EXECUTION")

	// Marcar EXECUTING antes de correr los scripts
	if err := mgr.Save(ticket.TicketID, ticket.ProjectID, string(ticket.TaskType),
		state.StateExecuting, dlkStatus, "en ejecución", nil); err != nil {
		fmt.Fprintf(os.Stderr, "WARN: no se pudo guardar estado: %v\n", err)
	}

	fmt.Printf("  Timeout por fase: %s\n", *phaseTimeout)
	execResult, execErr := executor.Run(ticket.TicketID, scriptsDir, *phaseTimeout)

	// Print phase-by-phase output
	for _, phase := range execResult.Phases {
		status := "OK  "
		if !phase.OK() {
			status = "FAIL"
		}
		fmt.Printf("  [%s] %-14s exit=%d  %s\n",
			status, phase.Phase, phase.ExitCode, phase.Duration.Round(time.Millisecond))
		if phase.Stdout != "" {
			for _, line := range strings.Split(strings.TrimRight(phase.Stdout, "\n"), "\n") {
				fmt.Printf("        %s\n", line)
			}
		}
		if phase.Stderr != "" && !phase.OK() {
			for _, line := range strings.Split(strings.TrimRight(phase.Stderr, "\n"), "\n") {
				fmt.Printf("        STDERR: %s\n", line)
			}
		}
	}

	if execErr != nil {
		// OS-level error (script missing mid-run, permission denied, etc.)
		fmt.Fprintf(os.Stderr, "\nERROR en ejecución: %v\n", execErr)
		if err := mgr.Save(ticket.TicketID, ticket.ProjectID, string(ticket.TaskType),
			state.StateBlocked, dlkStatus, "error de ejecución: "+execErr.Error(), nil); err != nil {
			fmt.Fprintf(os.Stderr, "WARN: no se pudo guardar estado: %v\n", err)
		}
		if err := mgr.WriteSessionProgress(sessionMDPath); err != nil {
			fmt.Fprintf(os.Stderr, "WARN: no se pudo escribir SESSION_PROGRESS.md: %v\n", err)
		}
		printFinalBox(ticket, "BLOCKED", dlkStatus, false)
		return
	}

	if !execResult.Success {
		reason := fmt.Sprintf("fase '%s' falló (exit %d)",
			execResult.FailedPhase,
			execResult.Phases[len(execResult.Phases)-1].ExitCode)
		if err := mgr.Save(ticket.TicketID, ticket.ProjectID, string(ticket.TaskType),
			state.StateBlocked, dlkStatus, reason, nil); err != nil {
			fmt.Fprintf(os.Stderr, "WARN: no se pudo guardar estado: %v\n", err)
		}
		if err := mgr.WriteSessionProgress(sessionMDPath); err != nil {
			fmt.Fprintf(os.Stderr, "WARN: no se pudo escribir SESSION_PROGRESS.md: %v\n", err)
		}
		printFinalBox(ticket, "BLOCKED", dlkStatus, false)
		return
	}

	// ─── FASE 5: GOVERNANCE ───────────────────────────────────────────────────
	printSection("GOVERNANCE")
	iamSheetUpdated := false

	updated, govErr := governance.Update(ticket, iamXLSXPath)
	if govErr != nil {
		fmt.Fprintf(os.Stderr, "  WARN: no se pudo actualizar Plantilla IAM: %v\n", govErr)
	} else if updated {
		iamSheetUpdated = true
		fmt.Printf("  ✓ Plantilla de Permisos IAM actualizada\n")
		if err := mgr.MarkIAMSheetUpdated(ticket.TicketID); err != nil {
			fmt.Fprintf(os.Stderr, "  WARN: no se pudo marcar IAM sheet: %v\n", err)
		}
	} else {
		fmt.Printf("  N/A — %s no requiere actualización de plantilla IAM\n", ticket.TaskType)
	}

	// Ticket completado
	if err := mgr.Save(ticket.TicketID, ticket.ProjectID, string(ticket.TaskType),
		state.StateCompleted, dlkStatus, "completado", nil); err != nil {
		fmt.Fprintf(os.Stderr, "WARN: no se pudo guardar estado: %v\n", err)
	}
	if err := mgr.WriteSessionProgress(sessionMDPath); err != nil {
		fmt.Fprintf(os.Stderr, "WARN: no se pudo escribir SESSION_PROGRESS.md: %v\n", err)
	}
	printFinalBox(ticket, "COMPLETED", dlkStatus, iamSheetUpdated)
}

// ─── Helpers de I/O ──────────────────────────────────────────────────────────

func readInput(filePath string) (string, error) {
	if filePath != "" {
		data, err := os.ReadFile(filePath)
		if err != nil {
			return "", fmt.Errorf("leer archivo %s: %w", filePath, err)
		}
		return string(data), nil
	}

	fmt.Fprintln(os.Stderr, "Pega el texto del ticket y presiona Ctrl+D cuando termines:")
	var sb strings.Builder
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 1<<20), 1<<20) // 1MB max
	for scanner.Scan() {
		sb.WriteString(scanner.Text())
		sb.WriteByte('\n')
	}
	if err := scanner.Err(); err != nil && err != io.EOF {
		return "", err
	}
	return sb.String(), nil
}

func printSection(title string) {
	fmt.Printf("\n─── %s %s\n", title, strings.Repeat("─", max(0, 44-len(title))))
}

func printStandbyBox(t *parser.TicketRequest) {
	sep := strings.Repeat("=", 44)
	fmt.Printf("\n%s\n", sep)
	fmt.Printf("%s — %s\n", t.TicketID, t.TaskType)
	fmt.Printf("Project: %s\n", t.ProjectID)
	fmt.Println(sep)
	fmt.Printf("[STATUS] STANDBY — campos ambiguos detectados:\n")
	for _, a := range t.Ambiguous {
		fmt.Printf("  → %s\n", a)
	}
	fmt.Println(sep)
	fmt.Println("Status:   STANDBY")
	fmt.Println("DLK Gate: N/A")
	fmt.Println("IAM Sheet: N/A")
	fmt.Println(sep)
}

func printFinalBox(t *parser.TicketRequest, status string, dlk state.DLKGateStatus, iamSheet bool) {
	sep := strings.Repeat("=", 44)
	iamStr := "N/A"
	if iamSheet {
		iamStr = "ACTUALIZADA"
	}
	fmt.Printf("\n%s\n", sep)
	fmt.Printf("%s — %s\n", t.TicketID, t.TaskType)
	fmt.Printf("Project: %s\n", t.ProjectID)
	fmt.Println(sep)
	fmt.Printf("Status:    %s\n", status)
	fmt.Printf("DLK Gate:  %s\n", dlk)
	fmt.Printf("IAM Sheet: %s\n", iamStr)
	fmt.Println(sep)
}

func printSessionStatus(mgr *state.Manager) {
	summary := mgr.Summary()
	fmt.Printf("\n=== SESSION STATUS — %s ===\n", summary.Date.Format("2006-01-02 15:04"))
	fmt.Printf("✅ Completados : %d\n", len(summary.Completed))
	fmt.Printf("⏸  Standby    : %d\n", len(summary.Standby))
	fmt.Printf("🚫 Bloqueados  : %d\n\n", len(summary.Blocked))

	if len(summary.Standby) > 0 {
		fmt.Println("STANDBY:")
		for _, r := range summary.Standby {
			fmt.Printf("  %s — %s\n", r.TicketID, r.Reason)
		}
	}
	if len(summary.Blocked) > 0 {
		fmt.Println("BLOQUEADOS:")
		for _, r := range summary.Blocked {
			fmt.Printf("  %s — %s\n", r.TicketID, r.Reason)
		}
	}
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "ERROR: "+format+"\n", args...)
	os.Exit(1)
}
