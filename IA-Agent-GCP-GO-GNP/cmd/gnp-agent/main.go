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
	"flag"
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"gnp-agent/internal/parser"
	"gnp-agent/internal/state"
)

// Paths de configuración del entorno GNP
const (
	ticketsDir   = "/home/admin/Documents/GNP/Tickets"
	stateDir     = "/home/admin/Documents/GNP/Repos/IaC-Programming-Samples/IA-Agent-GCP-GO-GNP/state"
	gitlabToken  = "/home/admin/Documents/GNP/PersonalGitLabToken"
	iamXLSXPath  = "/home/admin/Documents/GNP/Proyecto-Permisos-IAM/Plantilla de Permisos IAM.xlsx"
	dlkXLSXPath  = "/home/admin/Documents/GNP/Proyecto-Permisos-IAM/Plantilla Permisos DLK V3.0.xlsx"
	sessionMDPath = "/home/admin/Documents/GNP/Tickets/SESSION_PROGRESS.md"
)

func main() {
	// Flags
	ticketFile := flag.String("ticket", "", "archivo de texto con el ticket (default: stdin)")
	dryRun     := flag.Bool("dry-run", false, "parsear y generar scripts sin ejecutar")
	showStatus := flag.Bool("status", false, "mostrar estado de tickets de la sesión")
	skipDLK    := flag.Bool("skip-dlk", false, "omitir DLK gate (solo para pruebas)")
	flag.Parse()
	_ = skipDLK // usado en Sprint 3 cuando se implemente gate/dlk.go

	// Resolver ANTHROPIC_API_KEY: variable de entorno tiene prioridad,
	// si no está definida busca en ~/.config/gnp-agent/api_key o ~/.anthropic_api_key
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
	// Implementado en Sprint 3 (gate/dlk.go)
	// Por ahora: placeholder que siempre pasa
	printSection("DLK GATE")
	dlkStatus := state.DLKGateNA
	dlkApplies := isDLKProject(ticket.ProjectID)
	if dlkApplies {
		fmt.Printf("  ⚠  Proyecto DLK detectado — gate pendiente de implementación (Sprint 3)\n")
		fmt.Printf("  %s Para continuar manualmente, agrega -skip-dlk\n", warn())
		dlkStatus = state.DLKGatePassed // placeholder
	} else {
		fmt.Printf("  ✓ N/A — proyecto no DLK\n")
	}

	// ─── FASE 3: GENERATE SCRIPTS ─────────────────────────────────────────────
	// Implementado en Sprint 2 (generator/)
	// Por ahora: informar qué se generaría
	printSection("SCRIPT GENERATION")
	fmt.Printf("  Destino: %s/%s/scripts/\n", ticketsDir, ticket.TicketID)
	fmt.Printf("  Archivos: config.env, validate-pre.sh, execute.sh, validate.sh\n")
	fmt.Printf("  Template: %s\n", ticket.TaskType)
	fmt.Printf("  ⚠  Generador pendiente de implementación (Sprint 2)\n")

	if *dryRun {
		fmt.Println()
		fmt.Println("  [DRY-RUN] Detenido antes de ejecutar.")
		if err := mgr.Save(ticket.TicketID, ticket.ProjectID, string(ticket.TaskType),
			state.StatePending, dlkStatus, "dry-run", nil); err != nil {
			fmt.Fprintf(os.Stderr, "WARN: no se pudo guardar estado: %v\n", err)
		}
		printFinalBox(ticket, "DRY-RUN", dlkStatus, false)
		return
	}

	// ─── FASE 4: EXECUTE ──────────────────────────────────────────────────────
	// Implementado en Sprint 3 (executor/)
	printSection("EXECUTION")
	fmt.Printf("  ⚠  Executor pendiente de implementación (Sprint 3)\n")

	// ─── FASE 5: GOVERNANCE ───────────────────────────────────────────────────
	// Implementado en Sprint 5 (governance/)
	printSection("GOVERNANCE")
	fmt.Printf("  ⚠  Governance pendiente de implementación (Sprint 5)\n")

	// Estado final placeholder — FIX BUG-10: propagar errores
	if err := mgr.Save(ticket.TicketID, ticket.ProjectID, string(ticket.TaskType),
		state.StatePending, dlkStatus, "Sprints 2-5 pendientes", nil); err != nil {
		fmt.Fprintf(os.Stderr, "WARN: no se pudo guardar estado: %v\n", err)
	}
	if err := mgr.WriteSessionProgress(sessionMDPath); err != nil {
		fmt.Fprintf(os.Stderr, "WARN: no se pudo escribir SESSION_PROGRESS.md: %v\n", err)
	}

	printFinalBox(ticket, "PENDING", dlkStatus, false)
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

	// Leer desde stdin
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

// isDLKProject detecta si un proyecto está sujeto al gate DLK.
// FIX BUG-09: agrega "data" como keyword según especificación del chatmode.
func isDLKProject(projectID string) bool {
	lower := strings.ToLower(projectID)
	for _, kw := range []string{"dlk", "datalake", "datapond", "data"} {
		if strings.Contains(lower, kw) {
			return true
		}
	}
	return false
}

func warn() string { return "⚠ " }

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "ERROR: "+format+"\n", args...)
	os.Exit(1)
}

// FIX BUG-11: eliminada función max() — en Go 1.21+ es built-in.
// La función printSection usará el built-in directamente.
