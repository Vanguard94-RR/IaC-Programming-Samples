// Package governance updates the Plantilla de Permisos IAM.xlsx after a
// successful IAM ticket execution.
//
// Sheet layout (Hoja 1):
//
//	Row 1 : Title
//	Row 2 : "Última actualización: YYYY-MM-DD HH:MM:SS"
//	Row 3 : Empty
//	Row 4 : Headers — ROL | SA-QA | SA-UAT | SA-PRO | GRP-QA | GRP-UAT | GRP-PRO | …
//	Row 5+: One row per role, boolean presence per environment/principal-type.
//
// Note: The xlsx file contains <row r="1048576"...> which causes excelize to
// reconstruct the entire 1M-row range on save. cleanXLSX strips this before
// opening, then saves normally to a temp file and atomically renames it.
package governance

import (
	"archive/zip"
	"bytes"
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"
	"time"

	"github.com/xuri/excelize/v2"
	"gnp-agent/internal/parser"
)

const (
	colRole   = 1 // A
	colSAQA   = 2 // B — SERVICE ACCOUNTS - QA
	colSAUAT  = 3 // C — SERVICE ACCOUNTS - UAT
	colSAPRO  = 4 // D — SERVICE ACCOUNTS - PRO
	colGRPQA  = 5 // E — GROUP ACCOUNTS - QA
	colGRPUAT = 6 // F — GROUP ACCOUNTS - UAT
	colGRPPRO = 7 // G — GROUP ACCOUNTS - PRO

	dataStartRow = 5
	timestampRow = 2
	timestampCol = 1
	sheetName    = "Hoja 1"
	markValue    = "x"
)

// emptyStyleRowRe matches style-only rows with no cell data.
// The xlsx file contains 1856 such rows (e.g. <row r="1046721" ht="12.75"
// customHeight="1" s="3"></row>) that force excelize to allocate a sparse map
// spanning up to row 1048576 on save, causing an effectively infinite loop.
// All empty rows in this file share the single attribute pattern below.
var emptyStyleRowRe = regexp.MustCompile(`<row r="\d+" ht="12\.75" customHeight="1" s="3"></row>`)

// Update writes IAM role assignment data to the xlsx at xlsxPath.
// Returns (true, nil) on a successful write, (false, nil) if the ticket is not
// an IAM task (no update needed), or (false, err) on failure.
func Update(ticket *parser.TicketRequest, xlsxPath string) (bool, error) {
	if !parser.IsIAMTask(ticket.TaskType) {
		return false, nil
	}

	roles := ticket.AllRoles()
	if len(roles) == 0 {
		return false, nil
	}

	// Pre-clean: strip the max-row sentinel so excelize can save in finite time.
	cleanPath, cleanup, err := cleanXLSX(xlsxPath)
	if err != nil {
		return false, fmt.Errorf("preparar xlsx: %w", err)
	}
	defer cleanup()

	f, err := excelize.OpenFile(cleanPath)
	if err != nil {
		return false, fmt.Errorf("abrir xlsx: %w", err)
	}

	for _, role := range roles {
		row, err := findOrCreateRoleRow(f, role)
		if err != nil {
			f.Close()
			return false, err
		}
		for _, p := range ticket.Principals {
			for _, env := range ticket.Environments {
				col := envToCol(p.Type, env)
				if col == 0 {
					continue
				}
				cell, _ := excelize.CoordinatesToCellName(col, row)
				if err := f.SetCellStr(sheetName, cell, markValue); err != nil {
					f.Close()
					return false, fmt.Errorf("escribir celda %s: %w", cell, err)
				}
			}
		}
	}

	// Update timestamp
	ts := time.Now().Format("2006-01-02 15:04:05")
	tsCell, _ := excelize.CoordinatesToCellName(timestampCol, timestampRow)
	if err := f.SetCellStr(sheetName, tsCell, "Última actualización: "+ts); err != nil {
		f.Close()
		return false, fmt.Errorf("actualizar timestamp: %w", err)
	}

	// Atomic save: write to temp (.xlsx extension required by excelize) then rename.
	tmp := xlsxPath + ".new.xlsx"
	if err := f.SaveAs(tmp); err != nil {
		f.Close()
		return false, fmt.Errorf("guardar xlsx: %w", err)
	}
	f.Close()

	if err := os.Rename(tmp, xlsxPath); err != nil {
		os.Remove(tmp)
		return false, fmt.Errorf("renombrar xlsx: %w", err)
	}

	return true, nil
}

// cleanXLSX creates a cleaned copy of the xlsx with the max-row sentinel removed.
// Returns the path to the cleaned copy and a cleanup function to delete it.
func cleanXLSX(src string) (string, func(), error) {
	r, err := zip.OpenReader(src)
	if err != nil {
		return "", nil, fmt.Errorf("abrir zip: %w", err)
	}
	defer r.Close()

	tmp, err := os.CreateTemp("", "gnp-iam-clean-*.xlsx")
	if err != nil {
		return "", nil, fmt.Errorf("crear temp: %w", err)
	}
	tmpName := tmp.Name()
	cleanup := func() { os.Remove(tmpName) }

	w := zip.NewWriter(tmp)
	for _, zf := range r.File {
		fh := zf.FileHeader
		fw, err := w.CreateHeader(&fh)
		if err != nil {
			tmp.Close()
			cleanup()
			return "", nil, fmt.Errorf("crear entrada zip %s: %w", zf.Name, err)
		}

		rc, err := zf.Open()
		if err != nil {
			tmp.Close()
			cleanup()
			return "", nil, fmt.Errorf("leer entrada zip %s: %w", zf.Name, err)
		}
		data, err := io.ReadAll(rc)
		rc.Close()
		if err != nil {
			tmp.Close()
			cleanup()
			return "", nil, fmt.Errorf("leer contenido %s: %w", zf.Name, err)
		}

		if strings.HasSuffix(zf.Name, "/sheet1.xml") {
			data = emptyStyleRowRe.ReplaceAll(data, []byte{})
		}

		if _, err := io.Copy(fw, bytes.NewReader(data)); err != nil {
			tmp.Close()
			cleanup()
			return "", nil, fmt.Errorf("copiar entrada %s: %w", zf.Name, err)
		}
	}

	if err := w.Close(); err != nil {
		tmp.Close()
		cleanup()
		return "", nil, fmt.Errorf("cerrar zip: %w", err)
	}
	if err := tmp.Close(); err != nil {
		cleanup()
		return "", nil, fmt.Errorf("cerrar temp: %w", err)
	}

	return tmpName, cleanup, nil
}

// findOrCreateRoleRow returns the row number for the given role, creating a new
// row at the end of the data section if the role is not found.
func findOrCreateRoleRow(f *excelize.File, role string) (int, error) {
	rows, err := f.GetRows(sheetName)
	if err != nil {
		return 0, fmt.Errorf("leer filas: %w", err)
	}

	for i := dataStartRow - 1; i < len(rows); i++ {
		if len(rows[i]) > 0 && rows[i][0] == role {
			return i + 1, nil
		}
	}

	newRow := len(rows) + 1
	if newRow < dataStartRow {
		newRow = dataStartRow
	}
	cell, _ := excelize.CoordinatesToCellName(colRole, newRow)
	if err := f.SetCellStr(sheetName, cell, role); err != nil {
		return 0, fmt.Errorf("crear fila para rol %q: %w", role, err)
	}
	return newRow, nil
}

// envToCol maps (principalType, environment) to the xlsx column index.
// Returns 0 for unsupported combinations (caller should skip).
func envToCol(principalType, env string) int {
	isGroup := strings.EqualFold(principalType, "group")
	switch strings.ToLower(env) {
	case "qa", "dev", "dev1":
		if isGroup {
			return colGRPQA
		}
		return colSAQA
	case "uat", "stg", "staging":
		if isGroup {
			return colGRPUAT
		}
		return colSAUAT
	case "pro", "prd", "prod", "production":
		if isGroup {
			return colGRPPRO
		}
		return colSAPRO
	}
	return 0
}
