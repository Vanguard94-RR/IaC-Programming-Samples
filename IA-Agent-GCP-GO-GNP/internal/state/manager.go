package state

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

const stateFileName = "tickets.json"

// Manager gestiona la persistencia del estado de tickets en un archivo JSON.
type Manager struct {
	stateDir string
	records  map[string]*TicketRecord
}

// New crea un Manager que persiste en stateDir/tickets.json.
// Si el archivo existe, carga el estado previo.
func New(stateDir string) (*Manager, error) {
	if err := os.MkdirAll(stateDir, 0755); err != nil {
		return nil, fmt.Errorf("crear directorio de estado: %w", err)
	}

	m := &Manager{
		stateDir: stateDir,
		records:  make(map[string]*TicketRecord),
	}

	stateFile := filepath.Join(stateDir, stateFileName)
	data, err := os.ReadFile(stateFile)
	if err != nil {
		if os.IsNotExist(err) {
			return m, nil // archivo nuevo, sin historial
		}
		return nil, fmt.Errorf("leer estado: %w", err)
	}

	var existing []*TicketRecord
	if err := json.Unmarshal(data, &existing); err != nil {
		return nil, fmt.Errorf("parsear estado existente: %w", err)
	}
	for _, r := range existing {
		m.records[r.TicketID] = r
	}

	return m, nil
}

// Save crea o actualiza el registro de un ticket.
func (m *Manager) Save(ticketID, projectID, taskType string,
	s TicketState, dlk DLKGateStatus, reason string, ambiguous []string) error {

	now := time.Now()
	rec, exists := m.records[ticketID]
	if !exists {
		rec = &TicketRecord{
			TicketID:  ticketID,
			ProjectID: projectID,
			TaskType:  taskType,
			CreatedAt: now,
		}
		m.records[ticketID] = rec
	}

	rec.State     = s
	rec.DLKGate   = dlk
	rec.Reason    = reason
	rec.UpdatedAt = now

	if len(ambiguous) > 0 {
		rec.AmbiguousFields = ambiguous
	}
	if s == StateCompleted {
		t := now
		rec.CompletedAt = &t
	}

	return m.flush()
}

// MarkIAMSheetUpdated señala que la plantilla IAM fue actualizada para este ticket.
func (m *Manager) MarkIAMSheetUpdated(ticketID string) error {
	rec, ok := m.records[ticketID]
	if !ok {
		return fmt.Errorf("ticket %s no encontrado en estado", ticketID)
	}
	rec.IAMSheetUpdate = true
	rec.UpdatedAt = time.Now()
	return m.flush()
}

// Get devuelve el registro de un ticket, o nil si no existe.
func (m *Manager) Get(ticketID string) *TicketRecord {
	return m.records[ticketID]
}

// Summary devuelve el resumen de la sesión actual: completados, standby, bloqueados.
func (m *Manager) Summary() SessionSummary {
	s := SessionSummary{Date: time.Now()}
	for _, r := range m.records {
		switch r.State {
		case StateCompleted:
			s.Completed = append(s.Completed, *r)
		case StateStandby:
			s.Standby = append(s.Standby, *r)
		case StateBlocked:
			s.Blocked = append(s.Blocked, *r)
		}
	}
	return s
}

// flush escribe el estado completo al archivo JSON de forma atómica.
// FIX BUG-06: escribe a un archivo temporal y luego rename para evitar
// corrupción del JSON en caso de crash durante la escritura.
func (m *Manager) flush() error {
	records := make([]*TicketRecord, 0, len(m.records))
	for _, r := range m.records {
		records = append(records, r)
	}

	data, err := json.MarshalIndent(records, "", "  ")
	if err != nil {
		return fmt.Errorf("serializar estado: %w", err)
	}

	stateFile := filepath.Join(m.stateDir, stateFileName)
	tmpFile := stateFile + ".tmp"

	if err := os.WriteFile(tmpFile, data, 0644); err != nil {
		return fmt.Errorf("escribir estado temporal: %w", err)
	}
	// os.Rename es atómico en el mismo filesystem (POSIX)
	if err := os.Rename(tmpFile, stateFile); err != nil {
		os.Remove(tmpFile) // limpiar si rename falla
		return fmt.Errorf("renombrar estado: %w", err)
	}
	return nil
}

// WritSessionProgress genera el SESSION_PROGRESS.md con el resumen de la sesión.
func (m *Manager) WriteSessionProgress(outputPath string) error {
	summary := m.Summary()

	var buf []byte
	buf = append(buf, []byte(fmt.Sprintf(
		"# Tareas y Tickets GCP — Session Progress Report\n**Date:** %s\n\n---\n\n",
		summary.Date.Format("January 2, 2006")))...)

	buf = append(buf, []byte(fmt.Sprintf("## ✅ Completed (%d)\n\n", len(summary.Completed)))...)
	for _, r := range summary.Completed {
		dlkStr := ""
		if r.DLKGate != DLKGateNA {
			dlkStr = fmt.Sprintf(" | DLK: %s", r.DLKGate)
		}
		buf = append(buf, []byte(fmt.Sprintf(
			"### %s — %s\n- **Project:** %s%s\n- **Status:** ✓ COMPLETED\n\n",
			r.TicketID, r.TaskType, r.ProjectID, dlkStr))...)
	}

	buf = append(buf, []byte(fmt.Sprintf("## ⏸️ Standby (%d)\n\n", len(summary.Standby)))...)
	for _, r := range summary.Standby {
		buf = append(buf, []byte(fmt.Sprintf(
			"### %s\n- **Project:** %s\n- **Reason:** %s\n\n",
			r.TicketID, r.ProjectID, r.Reason))...)
	}

	buf = append(buf, []byte(fmt.Sprintf("## 🚫 Blocked (%d)\n\n", len(summary.Blocked)))...)
	for _, r := range summary.Blocked {
		buf = append(buf, []byte(fmt.Sprintf(
			"### %s\n- **Project:** %s\n- **Reason:** %s\n\n",
			r.TicketID, r.ProjectID, r.Reason))...)
	}

	return os.WriteFile(outputPath, buf, 0644)
}
