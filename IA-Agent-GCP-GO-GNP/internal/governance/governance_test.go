package governance

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/xuri/excelize/v2"
	"gnp-agent/internal/parser"
)

const realXLSXPath = "/home/admin/Documents/GNP/Proyecto-Permisos-IAM/Plantilla de Permisos IAM.xlsx"

// copyXLSX copies the real xlsx to a temp directory and returns the temp path.
func copyXLSX(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(realXLSXPath)
	if err != nil {
		t.Skipf("xlsx no encontrado (%v) — skipping governance integration test", err)
	}
	tmp := filepath.Join(t.TempDir(), "Plantilla de Permisos IAM.xlsx")
	if err := os.WriteFile(tmp, data, 0644); err != nil {
		t.Fatalf("copiar xlsx: %v", err)
	}
	return tmp
}

func TestUpdateNonIAMTask(t *testing.T) {
	ticket := &parser.TicketRequest{
		TicketID:  "CTASK9003",
		ProjectID: "gnp-test-qa",
		TaskType:  parser.TaskEnableAPIs,
		APIs:      []string{"pubsub.googleapis.com"},
	}
	updated, err := Update(ticket, realXLSXPath)
	if err != nil {
		t.Fatalf("Update() error: %v", err)
	}
	if updated {
		t.Error("expected updated=false for non-IAM task, got true")
	}
}

func TestUpdateNoRoles(t *testing.T) {
	ticket := &parser.TicketRequest{
		TicketID:  "CTASK0001",
		ProjectID: "gnp-test-qa",
		TaskType:  parser.TaskIAMProject,
		// No ProjectRoles → AllRoles() empty
	}
	updated, err := Update(ticket, realXLSXPath)
	if err != nil {
		t.Fatalf("Update() error: %v", err)
	}
	if updated {
		t.Error("expected updated=false with no roles, got true")
	}
}

func TestUpdateIAMProjectNewRole(t *testing.T) {
	xlsxPath := copyXLSX(t)

	ticket := &parser.TicketRequest{
		TicketID:     "CTASK_TEST_S5",
		ProjectID:    "gnp-test-qa",
		TaskType:     parser.TaskIAMProject,
		Principals:   []parser.Principal{{Type: "serviceAccount", Email: "test-sa@gnp-test-qa.iam.gserviceaccount.com"}},
		ProjectRoles: []string{"roles/test.roleS5Sprint"},
		Environments: []string{"qa"},
	}

	updated, err := Update(ticket, xlsxPath)
	if err != nil {
		t.Fatalf("Update() error: %v", err)
	}
	if !updated {
		t.Fatal("expected updated=true for IAM task, got false")
	}

	// Verify the role row was written with "x" in SA-QA column
	f, err := excelize.OpenFile(xlsxPath)
	if err != nil {
		t.Fatalf("reabrir xlsx: %v", err)
	}
	defer f.Close()

	rows, err := f.GetRows(sheetName)
	if err != nil {
		t.Fatalf("GetRows: %v", err)
	}

	found := false
	for i := dataStartRow - 1; i < len(rows); i++ {
		if len(rows[i]) > 0 && rows[i][0] == "roles/test.roleS5Sprint" {
			found = true
			// colSAQA is column 2 → index 1
			if len(rows[i]) < colSAQA || rows[i][colSAQA-1] != markValue {
				t.Errorf("SA-QA cell = %q, want %q", safeGet(rows[i], colSAQA-1), markValue)
			}
			break
		}
	}
	if !found {
		t.Error("new role row not found in xlsx after Update()")
	}
}

func TestUpdateIAMGroupUAT(t *testing.T) {
	xlsxPath := copyXLSX(t)

	ticket := &parser.TicketRequest{
		TicketID:     "CTASK_TEST_S5_GRP",
		ProjectID:    "gnp-test-uat",
		TaskType:     parser.TaskIAMBucket,
		Principals:   []parser.Principal{{Type: "group", Email: "team@gnp.com.mx"}},
		BucketRoles:  []string{"roles/storage.objectViewer"},
		Buckets:      []string{"gnp-bucket-uat"},
		Environments: []string{"uat"},
	}

	updated, err := Update(ticket, xlsxPath)
	if err != nil {
		t.Fatalf("Update() error: %v", err)
	}
	if !updated {
		t.Fatal("expected updated=true")
	}

	f, err := excelize.OpenFile(xlsxPath)
	if err != nil {
		t.Fatalf("reabrir xlsx: %v", err)
	}
	defer f.Close()

	rows, err := f.GetRows(sheetName)
	if err != nil {
		t.Fatalf("GetRows: %v", err)
	}

	for i := dataStartRow - 1; i < len(rows); i++ {
		if len(rows[i]) > 0 && rows[i][0] == "roles/storage.objectViewer" {
			// colGRPUAT = 6 → index 5
			got := safeGet(rows[i], colGRPUAT-1)
			if got != markValue {
				t.Errorf("GRP-UAT cell = %q, want %q", got, markValue)
			}
			return
		}
	}
	t.Error("role row not found in xlsx after Update()")
}

func TestTimestampUpdated(t *testing.T) {
	xlsxPath := copyXLSX(t)

	ticket := &parser.TicketRequest{
		TicketID:     "CTASK_TS",
		ProjectID:    "gnp-ts-qa",
		TaskType:     parser.TaskIAMProject,
		Principals:   []parser.Principal{{Type: "serviceAccount", Email: "ts@proj.iam.gserviceaccount.com"}},
		ProjectRoles: []string{"roles/viewer"},
		Environments: []string{"qa"},
	}

	_, err := Update(ticket, xlsxPath)
	if err != nil {
		t.Fatalf("Update() error: %v", err)
	}

	f, err := excelize.OpenFile(xlsxPath)
	if err != nil {
		t.Fatalf("reabrir xlsx: %v", err)
	}
	defer f.Close()

	tsCell, _ := excelize.CoordinatesToCellName(timestampCol, timestampRow)
	val, err := f.GetCellValue(sheetName, tsCell)
	if err != nil {
		t.Fatalf("GetCellValue timestamp: %v", err)
	}
	if !strings.HasPrefix(val, "Última actualización:") {
		t.Errorf("timestamp cell = %q — expected to start with 'Última actualización:'", val)
	}
}

func TestEnvToCol(t *testing.T) {
	cases := []struct {
		ptype string
		env   string
		want  int
	}{
		{"serviceAccount", "qa", colSAQA},
		{"serviceAccount", "uat", colSAUAT},
		{"serviceAccount", "pro", colSAPRO},
		{"serviceAccount", "prd", colSAPRO},
		{"group", "qa", colGRPQA},
		{"group", "uat", colGRPUAT},
		{"group", "pro", colGRPPRO},
		{"serviceAccount", "unknown", 0},
		{"group", "dev1", colGRPQA},
	}
	for _, c := range cases {
		got := envToCol(c.ptype, c.env)
		if got != c.want {
			t.Errorf("envToCol(%q, %q) = %d, want %d", c.ptype, c.env, got, c.want)
		}
	}
}

func safeGet(row []string, idx int) string {
	if idx < len(row) {
		return row[idx]
	}
	return ""
}
