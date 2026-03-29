package state

import "time"

// TicketState representa el estado de ciclo de vida de un ticket.
type TicketState string

const (
	StatePending   TicketState = "PENDING"
	StateValidated TicketState = "VALIDATED"
	StateExecuting TicketState = "EXECUTING"
	StateCompleted TicketState = "COMPLETED"
	StateStandby   TicketState = "STANDBY"
	StateBlocked   TicketState = "BLOCKED"
)

// DLKGateStatus registra el resultado del gate DLK.
type DLKGateStatus string

const (
	DLKGateNA       DLKGateStatus = "N/A"
	DLKGatePassed   DLKGateStatus = "PASSED"
	DLKGateBlocked  DLKGateStatus = "BLOCKED"
)

// TicketRecord es la entrada persistida en state/tickets.json por cada ticket.
type TicketRecord struct {
	TicketID       string        `json:"ticket_id"`
	ProjectID      string        `json:"project_id"`
	TaskType       string        `json:"task_type"`
	State          TicketState   `json:"state"`
	DLKGate        DLKGateStatus `json:"dlk_gate"`
	IAMSheetUpdate bool          `json:"iam_sheet_update"`
	Reason         string        `json:"reason,omitempty"`
	AmbiguousFields []string     `json:"ambiguous_fields,omitempty"`
	CreatedAt      time.Time     `json:"created_at"`
	UpdatedAt      time.Time     `json:"updated_at"`
	CompletedAt    *time.Time    `json:"completed_at,omitempty"`
}

// SessionSummary resume el estado de todos los tickets de la sesión activa.
type SessionSummary struct {
	Date      time.Time       `json:"date"`
	Completed []TicketRecord  `json:"completed"`
	Standby   []TicketRecord  `json:"standby"`
	Blocked   []TicketRecord  `json:"blocked"`
}
