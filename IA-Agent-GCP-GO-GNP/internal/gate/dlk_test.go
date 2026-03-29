package gate

import (
	"testing"

	"gnp-agent/internal/parser"
	"gnp-agent/internal/state"
)

func TestIsDLKProject(t *testing.T) {
	cases := []struct {
		projectID string
		want      bool
	}{
		{"gnp-dlk-qa", true},
		{"gnp-datalake-pro", true},
		{"gnp-datapond-uat", true},
		{"gnp-customer-data-qa", true},
		{"gnp-wsbancasegurogmm-qa", false},
		{"gnp-contabilidad-qa", false},
		{"gnp-gke-pro", false},
		{"", false},
	}
	for _, c := range cases {
		got := IsDLKProject(c.projectID)
		if got != c.want {
			t.Errorf("IsDLKProject(%q) = %v, want %v", c.projectID, got, c.want)
		}
	}
}

func TestCheckNonDLKProject(t *testing.T) {
	ticket := &parser.TicketRequest{
		ProjectID:    "gnp-wsbancasegurogmm-qa",
		ProjectRoles: []string{"roles/bigquery.admin"}, // high-risk role, but non-DLK project
	}
	result := Check(ticket)
	if result.Status != state.DLKGateNA {
		t.Errorf("non-DLK project: expected NA, got %q", result.Status)
	}
}

func TestCheckDLKProjectAllowedRoles(t *testing.T) {
	ticket := &parser.TicketRequest{
		ProjectID:   "gnp-dlk-qa",
		SecretRoles: []string{"roles/secretmanager.secretAccessor"},
		ProjectRoles: []string{"roles/bigquery.dataViewer"},
	}
	result := Check(ticket)
	if result.Status != state.DLKGatePassed {
		t.Errorf("allowed roles: expected PASSED, got %q (reason: %s)", result.Status, result.Reason)
	}
	if len(result.BlockedRoles) != 0 {
		t.Errorf("expected no blocked roles, got %v", result.BlockedRoles)
	}
}

func TestCheckDLKProjectBlockedRole(t *testing.T) {
	ticket := &parser.TicketRequest{
		ProjectID:    "gnp-datalake-pro",
		ProjectRoles: []string{"roles/bigquery.admin", "roles/bigquery.dataViewer"},
	}
	result := Check(ticket)
	if result.Status != state.DLKGateBlocked {
		t.Errorf("blocked role: expected BLOCKED, got %q", result.Status)
	}
	if len(result.BlockedRoles) != 1 {
		t.Errorf("expected 1 blocked role, got %v", result.BlockedRoles)
	}
	if result.BlockedRoles[0] != "roles/bigquery.admin" {
		t.Errorf("unexpected blocked role: %q", result.BlockedRoles[0])
	}
}

func TestCheckDLKProjectMultipleBlockedRoles(t *testing.T) {
	ticket := &parser.TicketRequest{
		ProjectID:    "gnp-datapond-uat",
		ProjectRoles: []string{"roles/owner", "roles/editor"},
	}
	result := Check(ticket)
	if result.Status != state.DLKGateBlocked {
		t.Errorf("expected BLOCKED, got %q", result.Status)
	}
	if len(result.BlockedRoles) != 2 {
		t.Errorf("expected 2 blocked roles, got %v", result.BlockedRoles)
	}
}

func TestCheckDLKProjectEmptyRoles(t *testing.T) {
	// DLK project but no roles — shouldn't happen in practice but should pass gate
	ticket := &parser.TicketRequest{
		ProjectID: "gnp-dlk-qa",
		TaskType:  parser.TaskPubSubCreate,
		Topics:    []string{"my-topic"},
	}
	result := Check(ticket)
	if result.Status != state.DLKGatePassed {
		t.Errorf("no roles: expected PASSED, got %q", result.Status)
	}
}

func TestCheckDLKStorageAdmin(t *testing.T) {
	ticket := &parser.TicketRequest{
		ProjectID:   "gnp-customer-data-pro",
		BucketRoles: []string{"roles/storage.admin"},
		Buckets:     []string{"my-bucket"},
	}
	result := Check(ticket)
	if result.Status != state.DLKGateBlocked {
		t.Errorf("storage.admin on data project: expected BLOCKED, got %q", result.Status)
	}
}
