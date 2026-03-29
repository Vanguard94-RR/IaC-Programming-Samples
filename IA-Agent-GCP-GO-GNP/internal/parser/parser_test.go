package parser

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestParseExamples verifica los 3 ejemplos canónicos del documento de diseño.
// Requiere ANTHROPIC_API_KEY en el entorno.
func TestParseExamples(t *testing.T) {
	if os.Getenv("ANTHROPIC_API_KEY") == "" {
		t.Skip("ANTHROPIC_API_KEY no definida, saltando test de integración")
	}

	tests := []struct {
		name              string
		input             string
		wantTicketID      string
		wantProjectID     string
		wantTaskType      TaskType
		wantPrincipalType string
		wantEnv           string
	}{
		{
			name: "secret_manager_iam",
			input: `Siguiente tarea
CTASK0359698
Artefacto: Permisos a secretos
TipoTarea: Manual
Owner: InfraTeam
TECNOLOGÍA: Google Cloud
Proyecto: gnp-wsbancasegurogmm-qa
Indicaciones:
Solicitud se le pide agregar los permisos para ver los secretos gae-ws-bancaseguro@gnp-wsbancasegurogmm-qa.iam.gserviceaccount.com
Secret Manager
Name.- key_banca
Name.- secret_banca`,
			wantTicketID:      "CTASK0359698",
			wantProjectID:     "gnp-wsbancasegurogmm-qa",
			wantTaskType:      TaskSecretManagerIAM,
			wantPrincipalType: "serviceAccount",
			wantEnv:           "qa",
		},
		{
			name: "iam_project_permisos_individuales",
			input: `siguiente tarea
CTASK0359612
Artefacto: Permisos cuenta de servicio
TipoTarea: Manual
Owner: InfraTeam
Tecnología: Google Cloud
ID proyecto GCP: gnp-admonproveedoressalud-qa
Indicaciones:
Se solicita de su apoyo para agregar los siguientes permisos a la cuenta de servicio simuladorgmm-secret-manager@gnp-admonproveedoressalud-qa.iam.gserviceaccount.com
Permisos:
secretmanager.secrets.get
secretmanager.secrets.access
secretmanager.versions.access
Rol Secret Manager Secret Accesor`,
			wantTicketID:      "CTASK0359612",
			wantProjectID:     "gnp-admonproveedoressalud-qa",
			wantTaskType:      TaskSecretManagerIAM,
			wantPrincipalType: "serviceAccount",
			wantEnv:           "qa",
		},
		{
			name: "pubsub_create",
			input: `Siguiente Tarea
CTASK0357498
Tarea Infraestructura
Pub/Sub: Creación de Temas y Suscripciones
Proyecto: gnp-contabilidad-qa
Se solicita el apoyo para crear los siguientes Temas y Suscripciones con las siguientes configuraciones.
Tipo de envío : Pull
Tiempo de retención de mensajes: 7 días
Período de vencimiento: Nunca vence
Plazo de confirmación: 30 seg
1.- Tema: projects/gnp-contabilidad-qa/topics/movimientos-refacturador-cierre
Suscripción: projects/gnp-contabilidad-qa/subscriptions/movimientos-refacturador-cierre.convertidorcontable-ingestion
2.- Tema: projects/gnp-contabilidad-qa/topics/movimientos-gl-control-corte
Suscripción: projects/gnp-contabilidad-qa/subscriptions/movimientos-gl-control-corte.convertidorcontable-ingestion`,
			wantTicketID:  "CTASK0357498",
			wantProjectID: "gnp-contabilidad-qa",
			wantTaskType:  TaskPubSubCreate,
			wantEnv:       "qa",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result, err := Parse(tc.input)
			if err != nil {
				t.Fatalf("Parse() error: %v", err)
			}

			if result.TicketID != tc.wantTicketID {
				t.Errorf("TicketID: got %q, want %q", result.TicketID, tc.wantTicketID)
			}
			if result.ProjectID != tc.wantProjectID {
				t.Errorf("ProjectID: got %q, want %q", result.ProjectID, tc.wantProjectID)
			}
			if result.TaskType != tc.wantTaskType {
				t.Errorf("TaskType: got %q, want %q", result.TaskType, tc.wantTaskType)
			}
			if tc.wantPrincipalType != "" {
				if len(result.Principals) == 0 {
					t.Error("Principals vacío")
				} else if result.Principals[0].Type != tc.wantPrincipalType {
					t.Errorf("Principal.Type: got %q, want %q",
						result.Principals[0].Type, tc.wantPrincipalType)
				}
			}
			if tc.wantEnv != "" {
				found := false
				for _, e := range result.Environments {
					if e == tc.wantEnv {
						found = true
						break
					}
				}
				if !found {
					t.Errorf("Environments %v no contiene %q", result.Environments, tc.wantEnv)
				}
			}

			// Roles deben tener prefijo "roles/"
			for _, r := range result.AllRoles() {
				if !strings.HasPrefix(r, "roles/") {
					t.Errorf("Rol sin prefijo 'roles/': %q", r)
				}
			}
		})
	}
}

// TestParseCorpus carga tickets históricos reales usando el archivo de texto
// del ticket original (no config.env que es bash).
// FIX BUG-15: el corpus test enviaba config.env (bash) al parser en lugar
// del texto original del ticket. Ahora lee ticket.txt si existe, o usa
// config.env como fallback marcando el test como corpus-bash.
func TestParseCorpus(t *testing.T) {
	if os.Getenv("ANTHROPIC_API_KEY") == "" {
		t.Skip("ANTHROPIC_API_KEY no definida")
	}
	ticketsDir := "/home/admin/Documents/GNP/Tickets"
	if _, err := os.Stat(ticketsDir); err != nil {
		t.Skipf("directorio de tickets no encontrado: %s", ticketsDir)
	}

	// Construir corpus: buscar ticket.txt en cada directorio de ticket.
	// Si no existe ticket.txt, el ticket no tiene texto original guardado.
	entries, err := os.ReadDir(ticketsDir)
	if err != nil {
		t.Fatalf("leer directorio tickets: %v", err)
	}

	type corpusCase struct {
		ticketID string
		text     string
	}
	var cases []corpusCase

	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		ticketID := e.Name()
		// Buscar ticket.txt en el directorio del ticket
		for _, candidate := range []string{
			filepath.Join(ticketsDir, ticketID, "ticket.txt"),
			filepath.Join(ticketsDir, ticketID, "ticket.md"),
		} {
			if data, err := os.ReadFile(candidate); err == nil {
				cases = append(cases, corpusCase{ticketID, string(data)})
				break
			}
		}
	}

	if len(cases) == 0 {
		t.Skip("no se encontraron archivos ticket.txt en el corpus — ejecutar con tickets que tengan texto original")
	}

	limit := 20
	if len(cases) < limit {
		limit = len(cases)
	}

	passed, failed := 0, 0
	for _, tc := range cases[:limit] {
		result, err := Parse(tc.text)
		if err != nil {
			t.Logf("FAIL %s: %v", tc.ticketID, err)
			failed++
			continue
		}
		if result.ProjectID == "" {
			t.Logf("WARN %s: project_id vacío", tc.ticketID)
		}
		passed++
	}

	t.Logf("Corpus: %d/%d parseados correctamente", passed, limit)
	if limit > 0 && float64(failed)/float64(limit) > 0.10 {
		t.Errorf("Tasa de fallo > 10%%: %d fallos en %d tickets", failed, limit)
	}
}

// TestValidateNormalizesRoles verifica que validate() normaliza roles sin prefijo.
func TestValidateNormalizesRoles(t *testing.T) {
	ticket := &TicketRequest{
		TicketID:     "TEST001",
		TaskType:     TaskIAMProject,
		ProjectRoles: []string{"storage.admin", "roles/pubsub.editor", "  roles/bigquery.dataViewer "},
	}
	if err := validate(ticket); err != nil {
		t.Fatal(err)
	}
	for _, r := range ticket.ProjectRoles {
		if !strings.HasPrefix(r, "roles/") {
			t.Errorf("rol no normalizado: %q", r)
		}
	}
}

// TestMemberStr verifica el formato de los miembros GCP.
func TestMemberStr(t *testing.T) {
	cases := []struct {
		p    Principal
		want string
	}{
		{Principal{"serviceAccount", "sa@project.iam.gserviceaccount.com"}, "serviceAccount:sa@project.iam.gserviceaccount.com"},
		{Principal{"group", "team@gnp.com.mx"}, "group:team@gnp.com.mx"},
	}
	for _, c := range cases {
		if got := c.p.MemberStr(); got != c.want {
			t.Errorf("MemberStr() = %q, want %q", got, c.want)
		}
	}
}

// TestSchemaSerializable verifica que TicketRequest es JSON round-trippable.
func TestSchemaSerializable(t *testing.T) {
	original := &TicketRequest{
		TicketID:     "CTASK0001",
		ProjectID:    "gnp-test-qa",
		TaskType:     TaskSecretManagerIAM,
		Principals:   []Principal{{"serviceAccount", "sa@gnp-test-qa.iam.gserviceaccount.com"}},
		SecretRoles:  []string{"roles/secretmanager.secretAccessor"},
		Secrets:      []string{"key_banca", "secret_banca"},
		Environments: []string{"qa"},
	}

	data, err := json.Marshal(original)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}

	var restored TicketRequest
	if err := json.Unmarshal(data, &restored); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}

	if restored.TicketID != original.TicketID {
		t.Errorf("TicketID round-trip fail")
	}
	if len(restored.Secrets) != len(original.Secrets) {
		t.Errorf("Secrets round-trip fail")
	}
}
