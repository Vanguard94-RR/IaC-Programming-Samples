package parser

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

const (
	claudeAPIURL     = "https://api.anthropic.com/v1/messages"
	claudeModel      = "claude-sonnet-4-6"
	claudeAPIVersion = "2023-06-01"
	maxTokens        = 4096 // FIX BUG-02: 2048 insuficiente para tickets con YAML/múltiples recursos
	httpTimeout      = 90 * time.Second
)

// httpClient con timeout explícito — FIX BUG-07: DefaultClient no tiene timeout.
var httpClient = &http.Client{Timeout: httpTimeout}

// claudeRequest es el payload enviado a la API de Claude.
type claudeRequest struct {
	Model     string           `json:"model"`
	MaxTokens int              `json:"max_tokens"`
	System    string           `json:"system"`
	Messages  []claudeMessage  `json:"messages"`
}

type claudeMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// claudeResponse es la respuesta de la API de Claude.
type claudeResponse struct {
	Content []struct {
		Type string `json:"type"`
		Text string `json:"text"`
	} `json:"content"`
	Error *struct {
		Type    string `json:"type"`
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

// Parse toma el texto crudo de un ticket y devuelve un TicketRequest estructurado.
// Lee la API key desde la variable de entorno ANTHROPIC_API_KEY.
func Parse(rawText string) (*TicketRequest, error) {
	apiKey := os.Getenv("ANTHROPIC_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("ANTHROPIC_API_KEY no está definida")
	}

	payload := claudeRequest{
		Model:     claudeModel,
		MaxTokens: maxTokens,
		System:    systemPrompt,
		Messages: []claudeMessage{
			{Role: "user", Content: rawText},
		},
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequest("POST", claudeAPIURL, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("x-api-key", apiKey)
	req.Header.Set("anthropic-version", claudeAPIVersion)
	req.Header.Set("content-type", "application/json")

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("http request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("claude API HTTP %d: %s", resp.StatusCode, string(respBody))
	}

	var claudeResp claudeResponse
	if err := json.Unmarshal(respBody, &claudeResp); err != nil {
		return nil, fmt.Errorf("unmarshal claude response: %w", err)
	}

	if claudeResp.Error != nil {
		return nil, fmt.Errorf("claude error %s: %s",
			claudeResp.Error.Type, claudeResp.Error.Message)
	}

	if len(claudeResp.Content) == 0 {
		return nil, fmt.Errorf("claude devolvió respuesta vacía")
	}

	// FIX BUG-03: stripping robusto de bloques markdown.
	// Estrategia: extraer el contenido entre la primera '{' y la última '}'.
	// Esto es tolerante a cualquier decoración que Claude añada.
	jsonText := extractJSON(claudeResp.Content[0].Text)
	if jsonText == "" {
		return nil, fmt.Errorf("no se encontró JSON válido en la respuesta de Claude:\n%s",
			claudeResp.Content[0].Text)
	}

	var ticket TicketRequest
	if err := json.Unmarshal([]byte(jsonText), &ticket); err != nil {
		return nil, fmt.Errorf("unmarshal ticket JSON: %w\nRaw: %s", err, jsonText)
	}

	// Normalizar: guardar el texto original para referencia
	ticket.RawText = rawText

	// Validaciones post-parse
	if err := validate(&ticket); err != nil {
		return nil, fmt.Errorf("ticket inválido: %w", err)
	}

	return &ticket, nil
}

// knownTaskTypes es el conjunto de task_type válidos para validación rápida.
var knownTaskTypes = map[TaskType]bool{
	TaskIAMProject: true, TaskIAMBucket: true, TaskIAMPubSub: true,
	TaskIAMBigQuery: true, TaskSecretManagerIAM: true, TaskSecretManagerCreate: true,
	TaskGKESecret: true, TaskPubSubCreate: true, TaskSACreation: true,
	TaskCloudScheduler: true, TaskEnableAPIs: true, TaskGitLabBucketUpload: true,
	TaskMixed: true, TaskUnknown: true,
}

// validate aplica reglas de negocio sobre el ticket parseado.
func validate(t *TicketRequest) error {
	if t.TicketID == "" {
		return fmt.Errorf("ticket_id vacío")
	}

	// FIX BUG-05a: validar TaskType contra valores conocidos.
	if t.TaskType == "" {
		t.TaskType = TaskUnknown
	} else if !knownTaskTypes[t.TaskType] {
		return fmt.Errorf("task_type desconocido: %q — valores válidos: iam_project, secret_manager_iam, pubsub_create, gke_secret, ...", t.TaskType)
	}

	// FIX BUG-05b: ProjectID requerido para la mayoría de task types.
	noProjectRequired := map[TaskType]bool{TaskMixed: true, TaskUnknown: true}
	if t.ProjectID == "" && !noProjectRequired[t.TaskType] {
		t.Ambiguous = append(t.Ambiguous, "project_id: no se pudo determinar el proyecto GCP")
	}

	// Normalizar roles: asegurar prefijo "roles/"
	normalize := func(roles []string) []string {
		out := make([]string, 0, len(roles))
		for _, r := range roles {
			r = strings.TrimSpace(r)
			if r == "" {
				continue
			}
			if !strings.HasPrefix(r, "roles/") {
				r = "roles/" + r
			}
			out = append(out, r)
		}
		return out
	}

	t.ProjectRoles  = normalize(t.ProjectRoles)
	t.BucketRoles   = normalize(t.BucketRoles)
	t.PubSubRoles   = normalize(t.PubSubRoles)
	t.BigQueryRoles = normalize(t.BigQueryRoles)
	t.SecretRoles   = normalize(t.SecretRoles)

	return nil
}

// extractJSON extrae el objeto JSON de un string que puede contener
// bloques markdown, texto adicional, etc.
// FIX BUG-03: estrategia robusta basada en encontrar '{' y '}'.
func extractJSON(s string) string {
	start := strings.Index(s, "{")
	end := strings.LastIndex(s, "}")
	if start == -1 || end == -1 || end < start {
		return ""
	}
	return strings.TrimSpace(s[start : end+1])
}

// MemberStr devuelve el principal en formato gcloud: "serviceAccount:email"
func (p Principal) MemberStr() string {
	return fmt.Sprintf("%s:%s", p.Type, p.Email)
}

// HasAmbiguous indica si el ticket tiene campos pendientes de confirmar.
func (t *TicketRequest) HasAmbiguous() bool {
	return len(t.Ambiguous) > 0
}

// AllRoles devuelve todos los roles únicos de todos los scopes.
// FIX BUG-01: evita append encadenado que puede corromper slices originales
// por aliasing del array subyacente en Go.
func (t *TicketRequest) AllRoles() []string {
	seen := make(map[string]bool)
	var all []string
	// Construir lista segura copiando cada slice explícitamente
	sources := [][]string{
		t.ProjectRoles,
		t.BucketRoles,
		t.PubSubRoles,
		t.BigQueryRoles,
		t.SecretRoles,
	}
	for _, src := range sources {
		for _, r := range src {
			if !seen[r] {
				seen[r] = true
				all = append(all, r)
			}
		}
	}
	return all
}
