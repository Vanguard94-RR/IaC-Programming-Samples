package generator

import (
	"bytes"
	"embed"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/template"

	"gnp-agent/internal/parser"
)

//go:embed templates
var templatesFS embed.FS

// TemplateData enriches TicketRequest with pre-computed fields safe for templates.
type TemplateData struct {
	*parser.TicketRequest
	// Members: principals in "type:email" format (e.g. "serviceAccount:sa@...")
	Members []string
	// KubeFromLiterals: "--from-literal=key=val" args pre-built for kubectl
	KubeFromLiterals []string
}

func newTemplateData(t *parser.TicketRequest) TemplateData {
	members := make([]string, len(t.Principals))
	for i, p := range t.Principals {
		members[i] = p.MemberStr()
	}
	kubeArgs := make([]string, len(t.KubeSecretData))
	for i, kv := range t.KubeSecretData {
		kubeArgs[i] = fmt.Sprintf("--from-literal=%s=%s", kv.Key, kv.Value)
	}
	return TemplateData{
		TicketRequest:    t,
		Members:          members,
		KubeFromLiterals: kubeArgs,
	}
}

// ErrUnsupportedTask is returned when no template exists for the task type.
// Compatible with errors.Is().
var ErrUnsupportedTask = errors.New("task_type sin template")

// Generate writes config.env, validate-pre.sh, execute.sh, and validate.sh
// into outDir for the given ticket. outDir is created if it does not exist.
// Returns ErrUnsupportedTask if the task type has no template yet.
func Generate(ticket *parser.TicketRequest, outDir string) error {
	// BUG-S2-06: validate required scalar fields before touching the filesystem
	if strings.TrimSpace(ticket.TicketID) == "" {
		return fmt.Errorf("TicketID es requerido")
	}
	if strings.TrimSpace(ticket.ProjectID) == "" {
		return fmt.Errorf("ProjectID es requerido")
	}

	// BUG-S2-04: task-type-specific required field validation
	if err := validateFields(ticket); err != nil {
		return err
	}

	if err := os.MkdirAll(outDir, 0755); err != nil {
		return fmt.Errorf("crear directorio scripts: %w", err)
	}

	taskStr := string(ticket.TaskType)
	execTmplPath := "templates/" + taskStr + "/execute.sh.tmpl"
	if _, err := templatesFS.Open(execTmplPath); err != nil {
		return fmt.Errorf("%w: %q (disponibles: iam_project, iam_bucket, iam_bigquery, secret_manager_iam, gke_secret, pubsub_create, cloud_scheduler, enable_apis, gitlab_bucket_upload)",
			ErrUnsupportedTask, taskStr)
	}

	data := newTemplateData(ticket)

	type fileSpec struct {
		tmpl string
		out  string
		mode os.FileMode
	}
	specs := []fileSpec{
		{"templates/common/config.env.tmpl", "config.env", 0644},
		{"templates/common/validate-pre.sh.tmpl", "validate-pre.sh", 0755},
		{execTmplPath, "execute.sh", 0755},
		{"templates/common/validate.sh.tmpl", "validate.sh", 0755},
	}

	for _, s := range specs {
		if err := renderFile(data, s.tmpl, filepath.Join(outDir, s.out), s.mode); err != nil {
			return fmt.Errorf("generar %s: %w", s.out, err)
		}
	}
	return nil
}

// validateFields enforces required fields per task type.
// BUG-S2-04: catches incomplete tickets before generating unusable scripts.
func validateFields(t *parser.TicketRequest) error {
	switch t.TaskType {
	case parser.TaskGKESecret:
		if t.Cluster == "" {
			return fmt.Errorf("gke_secret: Cluster es requerido")
		}
		if t.Namespace == "" {
			return fmt.Errorf("gke_secret: Namespace es requerido")
		}
		if t.KubeSecretName == "" {
			return fmt.Errorf("gke_secret: KubeSecretName es requerido")
		}
		if len(t.KubeSecretData) == 0 {
			return fmt.Errorf("gke_secret: KubeSecretData debe tener al menos una entrada")
		}
	case parser.TaskIAMBucket:
		if len(t.BucketRoles) == 0 {
			return fmt.Errorf("iam_bucket: BucketRoles es requerido")
		}
		if len(t.Buckets) == 0 {
			return fmt.Errorf("iam_bucket: Buckets es requerido")
		}
	case parser.TaskPubSubCreate:
		if len(t.Topics) == 0 {
			return fmt.Errorf("pubsub_create: Topics debe tener al menos un elemento")
		}
	case parser.TaskIAMProject:
		if len(t.ProjectRoles) == 0 {
			return fmt.Errorf("iam_project: ProjectRoles es requerido")
		}
	case parser.TaskSecretManagerIAM:
		if len(t.SecretRoles) == 0 {
			return fmt.Errorf("secret_manager_iam: SecretRoles es requerido")
		}
		if len(t.Secrets) == 0 {
			return fmt.Errorf("secret_manager_iam: Secrets es requerido")
		}
	case parser.TaskIAMBigQuery:
		if len(t.BigQueryRoles) == 0 {
			return fmt.Errorf("iam_bigquery: BigQueryRoles es requerido")
		}
		if len(t.Datasets) == 0 {
			return fmt.Errorf("iam_bigquery: Datasets es requerido")
		}
	case parser.TaskCloudScheduler:
		if t.SchedulerJob == nil {
			return fmt.Errorf("cloud_scheduler: SchedulerJob es requerido")
		}
		if t.SchedulerJob.Name == "" {
			return fmt.Errorf("cloud_scheduler: SchedulerJob.Name es requerido")
		}
		if t.SchedulerJob.Schedule == "" {
			return fmt.Errorf("cloud_scheduler: SchedulerJob.Schedule es requerido")
		}
		if t.SchedulerJob.Timezone == "" {
			return fmt.Errorf("cloud_scheduler: SchedulerJob.Timezone es requerido")
		}
		if t.SchedulerJob.TargetType == "" {
			return fmt.Errorf("cloud_scheduler: SchedulerJob.TargetType es requerido (http|pubsub)")
		}
		region := t.SchedulerJob.Region
		if region == "" {
			region = t.Region
		}
		if region == "" {
			return fmt.Errorf("cloud_scheduler: Region es requerido (SchedulerJob.Region o Region)")
		}
	case parser.TaskEnableAPIs:
		if len(t.APIs) == 0 {
			return fmt.Errorf("enable_apis: APIs debe tener al menos un elemento")
		}
	case parser.TaskGitLabBucketUpload:
		if t.GitLabRepo == "" {
			return fmt.Errorf("gitlab_bucket_upload: GitLabRepo es requerido")
		}
		if t.GitLabPath == "" {
			return fmt.Errorf("gitlab_bucket_upload: GitLabPath es requerido")
		}
		if len(t.Buckets) == 0 {
			return fmt.Errorf("gitlab_bucket_upload: Buckets es requerido (bucket destino GCS)")
		}
	}
	return nil
}

func renderFile(data TemplateData, tmplPath, outPath string, mode os.FileMode) error {
	raw, err := templatesFS.ReadFile(tmplPath)
	if err != nil {
		return fmt.Errorf("leer template %s: %w", tmplPath, err)
	}

	tmpl, err := template.New(filepath.Base(tmplPath)).Funcs(funcMap()).Parse(string(raw))
	if err != nil {
		return fmt.Errorf("parsear template %s: %w", tmplPath, err)
	}

	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, data); err != nil {
		return fmt.Errorf("ejecutar template %s: %w", tmplPath, err)
	}

	// Atomic write: tmp → rename
	tmp := outPath + ".tmp"
	if err := os.WriteFile(tmp, buf.Bytes(), mode); err != nil {
		return err
	}
	if err := os.Rename(tmp, outPath); err != nil {
		os.Remove(tmp) // best-effort cleanup; ignore secondary error
		return err
	}
	return nil
}

func funcMap() template.FuncMap {
	return template.FuncMap{
		// bashArray converts []string → bash array literal: ("a" "b" "c")
		// BUG-S2-03: escape backslashes and double-quotes to prevent syntax errors.
		"bashArray": func(items []string) string {
			if len(items) == 0 {
				return "()"
			}
			var sb strings.Builder
			sb.WriteByte('(')
			for i, item := range items {
				if i > 0 {
					sb.WriteByte(' ')
				}
				escaped := strings.ReplaceAll(item, `\`, `\\`)
				escaped = strings.ReplaceAll(escaped, `"`, `\"`)
				sb.WriteByte('"')
				sb.WriteString(escaped)
				sb.WriteByte('"')
			}
			sb.WriteByte(')')
			return sb.String()
		},
		// retentionDuration converts days to gcloud duration string (e.g. "7d")
		"retentionDuration": func(days int) string {
			if days <= 0 {
				return "7d"
			}
			return fmt.Sprintf("%dd", days)
		},
	}
}
