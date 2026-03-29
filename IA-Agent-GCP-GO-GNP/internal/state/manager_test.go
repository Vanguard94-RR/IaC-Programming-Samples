package state

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestManagerRoundTrip(t *testing.T) {
	dir := t.TempDir()
	m, err := New(dir)
	if err != nil {
		t.Fatal(err)
	}

	err = m.Save("CTASK0001", "gnp-test-qa", "iam_project",
		StateCompleted, DLKGateNA, "", nil)
	if err != nil {
		t.Fatal(err)
	}

	err = m.Save("CTASK0002", "gnp-dlk-uat", "iam_project",
		StateBlocked, DLKGateBlocked, "DLK gate: roles/bigquery.admin bloqueado", nil)
	if err != nil {
		t.Fatal(err)
	}

	err = m.Save("CTASK0003", "gnp-stela-pro", "pubsub_create",
		StateStandby, DLKGateNA, "Nombre de topic pendiente de confirmar",
		[]string{"topic_name"})
	if err != nil {
		t.Fatal(err)
	}

	// Recargar desde disco
	m2, err := New(dir)
	if err != nil {
		t.Fatal(err)
	}

	if r := m2.Get("CTASK0001"); r == nil || r.State != StateCompleted {
		t.Error("CTASK0001 no persistió correctamente")
	}
	if r := m2.Get("CTASK0002"); r == nil || r.State != StateBlocked {
		t.Error("CTASK0002 no persistió correctamente")
	}
	if r := m2.Get("CTASK0003"); r == nil || len(r.AmbiguousFields) == 0 {
		t.Error("CTASK0003 campos ambiguos no persistieron")
	}
}

func TestSessionProgress(t *testing.T) {
	dir := t.TempDir()
	m, _ := New(dir)

	m.Save("CTASK0010", "gnp-test-qa", "iam_project", StateCompleted, DLKGateNA, "", nil)
	m.Save("CTASK0011", "gnp-dlk-uat", "secret_manager_iam", StateBlocked, DLKGateBlocked, "Requiere aprobación DLK", nil)

	outPath := filepath.Join(dir, "SESSION_PROGRESS.md")
	if err := m.WriteSessionProgress(outPath); err != nil {
		t.Fatal(err)
	}

	data, err := os.ReadFile(outPath)
	if err != nil {
		t.Fatal(err)
	}
	content := string(data)
	if len(content) == 0 {
		t.Error("SESSION_PROGRESS.md vacío")
	}
	if !containsStr(content, "CTASK0010") || !containsStr(content, "CTASK0011") {
		t.Error("SESSION_PROGRESS.md no contiene los ticket IDs")
	}
}

func TestMarkIAMSheetUpdated(t *testing.T) {
	dir := t.TempDir()
	m, _ := New(dir)
	m.Save("CTASK0020", "gnp-pro", "iam_project", StateCompleted, DLKGateNA, "", nil)

	if err := m.MarkIAMSheetUpdated("CTASK0020"); err != nil {
		t.Fatal(err)
	}
	if r := m.Get("CTASK0020"); !r.IAMSheetUpdate {
		t.Error("IAMSheetUpdate no marcado")
	}
}

// FIX BUG-12: usar strings.Contains en lugar de reimplementación manual.
func containsStr(s, sub string) bool {
	return strings.Contains(s, sub)
}
