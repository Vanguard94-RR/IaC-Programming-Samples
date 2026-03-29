package gate

import (
	"fmt"
	"strings"

	"gnp-agent/internal/parser"
	"gnp-agent/internal/state"
)

// blockedDLKRoles are roles that require explicit DLK team approval.
// Any ticket requesting these roles on a DLK project will be BLOCKED.
var blockedDLKRoles = map[string]bool{
	"roles/bigquery.admin":       true,
	"roles/bigquery.dataOwner":   true,
	"roles/bigquery.dataEditor":  true,
	"roles/storage.admin":        true,
	"roles/owner":                true,
	"roles/editor":               true,
	"roles/iam.securityAdmin":    true,
	"roles/resourcemanager.projectIamAdmin": true,
}

// DLKResult is the outcome of a DLK gate check.
type DLKResult struct {
	Status       state.DLKGateStatus
	Reason       string
	BlockedRoles []string
}

// Check evaluates the DLK gate for a ticket.
//   - Returns DLKGateNA  if the project is not a DLK project.
//   - Returns DLKGateBlocked if any requested role is in the blocked list.
//   - Returns DLKGatePassed otherwise.
func Check(ticket *parser.TicketRequest) DLKResult {
	if !IsDLKProject(ticket.ProjectID) {
		return DLKResult{Status: state.DLKGateNA}
	}

	var blocked []string
	for _, role := range ticket.AllRoles() {
		normalized := strings.ToLower(strings.TrimSpace(role))
		// Check both original and lowercased (roles are case-sensitive in GCP but
		// normalize for defensive matching).
		if blockedDLKRoles[role] || blockedDLKRoles[normalized] {
			blocked = append(blocked, role)
		}
	}

	if len(blocked) > 0 {
		return DLKResult{
			Status:       state.DLKGateBlocked,
			Reason:       fmt.Sprintf("roles requieren aprobación DLK: %s", strings.Join(blocked, ", ")),
			BlockedRoles: blocked,
		}
	}

	return DLKResult{
		Status: state.DLKGatePassed,
		Reason: "proyecto DLK — todos los roles permitidos",
	}
}

// IsDLKProject reports whether projectID belongs to the DLK data platform.
// Exported so main.go and other packages can use the same logic.
func IsDLKProject(projectID string) bool {
	lower := strings.ToLower(projectID)
	for _, kw := range []string{"dlk", "datalake", "datapond", "data"} {
		if strings.Contains(lower, kw) {
			return true
		}
	}
	return false
}
