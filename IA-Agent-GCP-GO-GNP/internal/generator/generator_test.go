package generator

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"gnp-agent/internal/parser"
)

// assertFile verifies the named file exists in dir and contains all expected substrings.
func assertFile(t *testing.T, dir, name string, contains ...string) {
	t.Helper()
	path := filepath.Join(dir, name)
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("assertFile: %s not found: %v", name, err)
	}
	content := string(data)
	for _, want := range contains {
		if !strings.Contains(content, want) {
			t.Errorf("%s: expected to contain %q\ngot:\n%s", name, want, content)
		}
	}
}

func TestGenerateIAMProject(t *testing.T) {
	ticket := &parser.TicketRequest{
		TicketID:     "CTASK0359612",
		ProjectID:    "gnp-admonproveedoressalud-qa",
		TaskType:     parser.TaskIAMProject,
		Principals:   []parser.Principal{{Type: "serviceAccount", Email: "simuladorgmm@gnp-admonproveedoressalud-qa.iam.gserviceaccount.com"}},
		ProjectRoles: []string{"roles/secretmanager.secretAccessor"},
		Environments: []string{"qa"},
	}

	outDir := t.TempDir()
	if err := Generate(ticket, outDir); err != nil {
		t.Fatalf("Generate() error: %v", err)
	}

	assertFile(t, outDir, "config.env",
		"CTASK0359612",
		"gnp-admonproveedoressalud-qa",
		`PROJECT_ROLES=("roles/secretmanager.secretAccessor")`,
		`PRINCIPALS=("serviceAccount:simuladorgmm@gnp-admonproveedoressalud-qa.iam.gserviceaccount.com")`,
	)
	assertFile(t, outDir, "validate-pre.sh",
		"#!/usr/bin/env bash",
		"gcloud auth list",
		"gcloud projects describe",
	)
	assertFile(t, outDir, "execute.sh",
		"add-iam-policy-binding",
		"--condition=None",
		"PROJECT_ROLES",
		"CTASK0359612",
	)
	assertFile(t, outDir, "validate.sh",
		"get-iam-policy",
		"PROJECT_ROLES",
	)

	// execute.sh must be executable
	info, err := os.Stat(filepath.Join(outDir, "execute.sh"))
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode()&0111 == 0 {
		t.Error("execute.sh is not executable")
	}
}

func TestGenerateSecretManagerIAM(t *testing.T) {
	ticket := &parser.TicketRequest{
		TicketID:     "CTASK0359698",
		ProjectID:    "gnp-wsbancasegurogmm-qa",
		TaskType:     parser.TaskSecretManagerIAM,
		Principals:   []parser.Principal{{Type: "serviceAccount", Email: "gae-ws-bancaseguro@gnp-wsbancasegurogmm-qa.iam.gserviceaccount.com"}},
		SecretRoles:  []string{"roles/secretmanager.secretAccessor"},
		Secrets:      []string{"key_banca", "secret_banca"},
		Environments: []string{"qa"},
	}

	outDir := t.TempDir()
	if err := Generate(ticket, outDir); err != nil {
		t.Fatalf("Generate() error: %v", err)
	}

	assertFile(t, outDir, "config.env",
		`SECRET_ROLES=("roles/secretmanager.secretAccessor")`,
		`SECRETS=("key_banca" "secret_banca")`,
	)
	assertFile(t, outDir, "execute.sh",
		"secrets add-iam-policy-binding",
		"${SECRETS[@]}",
		"CTASK0359698",
	)
	assertFile(t, outDir, "validate-pre.sh",
		"gcloud secrets describe",
	)
	assertFile(t, outDir, "validate.sh",
		"secrets get-iam-policy",
	)
}

func TestGenerateIAMBucket(t *testing.T) {
	ticket := &parser.TicketRequest{
		TicketID:     "CTASK0001",
		ProjectID:    "gnp-storage-qa",
		TaskType:     parser.TaskIAMBucket,
		Principals:   []parser.Principal{{Type: "serviceAccount", Email: "sa@gnp-storage-qa.iam.gserviceaccount.com"}},
		BucketRoles:  []string{"roles/storage.objectViewer"},
		Buckets:      []string{"gnp-bucket-qa"},
		Environments: []string{"qa"},
	}

	outDir := t.TempDir()
	if err := Generate(ticket, outDir); err != nil {
		t.Fatalf("Generate() error: %v", err)
	}

	assertFile(t, outDir, "config.env",
		`BUCKET_ROLES=("roles/storage.objectViewer")`,
		`BUCKETS=("gnp-bucket-qa")`,
	)
	assertFile(t, outDir, "execute.sh",
		"storage buckets add-iam-policy-binding",
		"gs://${BUCKET}",
	)
}

func TestGenerateGKESecret(t *testing.T) {
	ticket := &parser.TicketRequest{
		TicketID:       "CTASK0002",
		ProjectID:      "gnp-gke-qa",
		TaskType:       parser.TaskGKESecret,
		Cluster:        "gnp-cluster-qa",
		Namespace:      "app-namespace",
		KubeSecretName: "app-secrets",
		KubeSecretData: []parser.KubeSecretEntry{
			{Key: "DB_PASSWORD", Value: "s3cr3t"},
			{Key: "API_KEY", Value: "abc123"},
		},
		Environments: []string{"qa"},
	}

	outDir := t.TempDir()
	if err := Generate(ticket, outDir); err != nil {
		t.Fatalf("Generate() error: %v", err)
	}

	assertFile(t, outDir, "config.env",
		`CLUSTER="gnp-cluster-qa"`,
		`NAMESPACE="app-namespace"`,
		`KUBE_SECRET_NAME="app-secrets"`,
	)
	assertFile(t, outDir, "execute.sh",
		"container clusters list",
		"get-credentials",
		"kubectl create secret generic",
		"--from-literal=DB_PASSWORD=s3cr3t",
		"--from-literal=API_KEY=abc123",
		"--dry-run=client -o yaml | kubectl apply",
	)
	assertFile(t, outDir, "validate-pre.sh",
		"container clusters list",
		"kubectl",
	)
	assertFile(t, outDir, "validate.sh",
		"kubectl get secret",
	)
}

func TestGeneratePubSubCreate(t *testing.T) {
	ticket := &parser.TicketRequest{
		TicketID:  "CTASK0357498",
		ProjectID: "gnp-contabilidad-qa",
		TaskType:  parser.TaskPubSubCreate,
		Topics:    []string{"movimientos-refacturador-cierre", "movimientos-gl-control-corte"},
		Subscriptions: []parser.SubscriptionConfig{
			{
				Name:             "movimientos-refacturador-cierre.convertidorcontable-ingestion",
				Topic:            "movimientos-refacturador-cierre",
				AckDeadline:      30,
				RetentionDays:    7,
				ExpirationPolicy: "never",
				DeliveryType:     "pull",
			},
		},
		Environments: []string{"qa"},
	}

	outDir := t.TempDir()
	if err := Generate(ticket, outDir); err != nil {
		t.Fatalf("Generate() error: %v", err)
	}

	assertFile(t, outDir, "config.env",
		`TOPICS=("movimientos-refacturador-cierre" "movimientos-gl-control-corte")`,
	)
	assertFile(t, outDir, "execute.sh",
		"pubsub topics create",
		"pubsub subscriptions create",
		"movimientos-refacturador-cierre.convertidorcontable-ingestion",
		"--ack-deadline=30",
		"--message-retention-duration=7d",
		"--expiration-period=never",
	)
	assertFile(t, outDir, "validate.sh",
		"pubsub topics describe",
		"pubsub subscriptions describe",
		"movimientos-refacturador-cierre.convertidorcontable-ingestion",
	)
}

func TestGenerateUnsupportedTaskType(t *testing.T) {
	ticket := &parser.TicketRequest{
		TicketID:  "CTASK9999",
		ProjectID: "gnp-test-qa",
		TaskType:  parser.TaskSACreation, // no template yet
	}
	outDir := t.TempDir()
	err := Generate(ticket, outDir)
	if err == nil {
		t.Fatal("expected error for unsupported task type, got nil")
	}
	// BUG-S2-05 fix: ErrUnsupportedTask is now errors.New — compatible with errors.Is
	if !errors.Is(err, ErrUnsupportedTask) {
		t.Errorf("expected errors.Is(err, ErrUnsupportedTask), got: %v", err)
	}
}

func TestGenerateIAMBigQuery(t *testing.T) {
	ticket := &parser.TicketRequest{
		TicketID:      "CTASK9001",
		ProjectID:     "gnp-dlk-qa",
		TaskType:      parser.TaskIAMBigQuery,
		Principals:    []parser.Principal{{Type: "serviceAccount", Email: "sa@gnp-dlk-qa.iam.gserviceaccount.com"}},
		BigQueryRoles: []string{"roles/bigquery.dataViewer"},
		Datasets:      []string{"dataset_ventas", "dataset_siniestros"},
		Environments:  []string{"qa"},
	}
	outDir := t.TempDir()
	if err := Generate(ticket, outDir); err != nil {
		t.Fatalf("Generate() error: %v", err)
	}
	assertFile(t, outDir, "config.env",
		`BIGQUERY_ROLES=("roles/bigquery.dataViewer")`,
		`DATASETS=("dataset_ventas" "dataset_siniestros")`,
	)
	assertFile(t, outDir, "execute.sh",
		"bq get-iam-policy",
		"bq set-iam-policy",
		"${PROJECT_ID}:${dataset}",
		"${BIGQUERY_ROLES[@]}",
	)
	assertFile(t, outDir, "validate-pre.sh",
		"command -v bq",
		"bq show",
	)
	assertFile(t, outDir, "validate.sh",
		"bq get-iam-policy",
		"${PROJECT_ID}:${DATASET}",
	)
}

func TestGenerateCloudScheduler(t *testing.T) {
	ticket := &parser.TicketRequest{
		TicketID:  "CTASK9002",
		ProjectID: "gnp-contabilidad-qa",
		TaskType:  parser.TaskCloudScheduler,
		SchedulerJob: &parser.SchedulerConfig{
			Name:       "job-reporte-diario",
			Region:     "us-central1",
			Schedule:   "0 8 * * *",
			Timezone:   "America/Mexico_City",
			TargetType: "http",
			TargetURL:  "https://my-service.example.com/run",
			HTTPMethod: "POST",
		},
		Environments: []string{"qa"},
	}
	outDir := t.TempDir()
	if err := Generate(ticket, outDir); err != nil {
		t.Fatalf("Generate() error: %v", err)
	}
	assertFile(t, outDir, "execute.sh",
		"gcloud scheduler jobs",
		"job-reporte-diario",
		"0 8 * * *",
		"us-central1",
		"America/Mexico_City",
		"https://my-service.example.com/run",
	)
	assertFile(t, outDir, "validate.sh",
		"gcloud scheduler jobs describe",
		"job-reporte-diario",
	)
}

func TestGenerateCloudSchedulerRegionFallback(t *testing.T) {
	// BUG-S4-05: top-level Region used when SchedulerJob.Region is empty
	ticket := &parser.TicketRequest{
		TicketID:  "CTASK9002B",
		ProjectID: "gnp-contabilidad-qa",
		TaskType:  parser.TaskCloudScheduler,
		Region:    "us-east1",
		SchedulerJob: &parser.SchedulerConfig{
			Name:       "job-fallback",
			Schedule:   "0 9 * * *",
			Timezone:   "UTC",
			TargetType: "http",
			TargetURL:  "https://example.com/run",
		},
		Environments: []string{"qa"},
	}
	outDir := t.TempDir()
	if err := Generate(ticket, outDir); err != nil {
		t.Fatalf("Generate() error: %v", err)
	}
	assertFile(t, outDir, "execute.sh", "us-east1")
	assertFile(t, outDir, "validate.sh", "us-east1")
}

func TestGenerateEnableAPIs(t *testing.T) {
	ticket := &parser.TicketRequest{
		TicketID:     "CTASK9003",
		ProjectID:    "gnp-contabilidad-qa",
		TaskType:     parser.TaskEnableAPIs,
		APIs:         []string{"pubsub.googleapis.com", "secretmanager.googleapis.com"},
		Environments: []string{"qa"},
	}
	outDir := t.TempDir()
	if err := Generate(ticket, outDir); err != nil {
		t.Fatalf("Generate() error: %v", err)
	}
	assertFile(t, outDir, "config.env",
		`APIS=("pubsub.googleapis.com" "secretmanager.googleapis.com")`,
	)
	assertFile(t, outDir, "execute.sh",
		"gcloud services enable",
		"${APIS[@]}",
	)
	assertFile(t, outDir, "validate.sh",
		"gcloud services list",
		`config.name=${API}`,
	)
}

func TestGenerateGitLabBucketUpload(t *testing.T) {
	ticket := &parser.TicketRequest{
		TicketID:     "CTASK9004",
		ProjectID:    "gnp-contabilidad-qa",
		TaskType:     parser.TaskGitLabBucketUpload,
		GitLabRepo:   "gnp/infra-config",
		GitLabBranch: "main",
		GitLabPath:   "configs/app.json",
		Buckets:      []string{"gnp-configs-qa"},
		Environments: []string{"qa"},
	}
	outDir := t.TempDir()
	if err := Generate(ticket, outDir); err != nil {
		t.Fatalf("Generate() error: %v", err)
	}
	assertFile(t, outDir, "config.env",
		`BUCKETS=("gnp-configs-qa")`,
	)
	assertFile(t, outDir, "execute.sh",
		"PRIVATE-TOKEN",
		"gnp/infra-config",
		"configs/app.json",
		"gcloud storage cp",
		"PersonalGitLabToken",
	)
	assertFile(t, outDir, "validate-pre.sh",
		"PersonalGitLabToken",
		"gs://${BUCKET}",
	)
	assertFile(t, outDir, "validate.sh",
		"app.json",
		"gs://${BUCKET}",
	)
}

// BUG-S4-02/S4-03: validateFields must reject incomplete Sprint 4 tickets.
func TestGenerateValidatesSprintFourFields(t *testing.T) {
	cases := []struct {
		name    string
		ticket  *parser.TicketRequest
		wantMsg string
	}{
		{
			"iam_bigquery no roles",
			&parser.TicketRequest{TicketID: "T1", ProjectID: "p1", TaskType: parser.TaskIAMBigQuery,
				Datasets: []string{"ds1"}},
			"BigQueryRoles",
		},
		{
			"iam_bigquery no datasets",
			&parser.TicketRequest{TicketID: "T1", ProjectID: "p1", TaskType: parser.TaskIAMBigQuery,
				BigQueryRoles: []string{"roles/bigquery.dataViewer"}},
			"Datasets",
		},
		{
			"cloud_scheduler nil job",
			&parser.TicketRequest{TicketID: "T1", ProjectID: "p1", TaskType: parser.TaskCloudScheduler},
			"SchedulerJob",
		},
		{
			"cloud_scheduler no schedule",
			&parser.TicketRequest{TicketID: "T1", ProjectID: "p1", TaskType: parser.TaskCloudScheduler,
				SchedulerJob: &parser.SchedulerConfig{Name: "j1", Region: "us-central1", Timezone: "UTC", TargetType: "http"}},
			"Schedule",
		},
		{
			"cloud_scheduler no region",
			&parser.TicketRequest{TicketID: "T1", ProjectID: "p1", TaskType: parser.TaskCloudScheduler,
				SchedulerJob: &parser.SchedulerConfig{Name: "j1", Schedule: "* * * * *", Timezone: "UTC", TargetType: "http"}},
			"Region",
		},
		{
			"enable_apis empty",
			&parser.TicketRequest{TicketID: "T1", ProjectID: "p1", TaskType: parser.TaskEnableAPIs},
			"APIs",
		},
		{
			"gitlab_bucket_upload no repo",
			&parser.TicketRequest{TicketID: "T1", ProjectID: "p1", TaskType: parser.TaskGitLabBucketUpload,
				GitLabPath: "file.txt", Buckets: []string{"b1"}},
			"GitLabRepo",
		},
		{
			"gitlab_bucket_upload no path",
			&parser.TicketRequest{TicketID: "T1", ProjectID: "p1", TaskType: parser.TaskGitLabBucketUpload,
				GitLabRepo: "org/repo", Buckets: []string{"b1"}},
			"GitLabPath",
		},
		{
			"gitlab_bucket_upload no bucket",
			&parser.TicketRequest{TicketID: "T1", ProjectID: "p1", TaskType: parser.TaskGitLabBucketUpload,
				GitLabRepo: "org/repo", GitLabPath: "file.txt"},
			"Buckets",
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			err := Generate(c.ticket, t.TempDir())
			if err == nil {
				t.Fatal("esperaba error, no hubo ninguno")
			}
			if !strings.Contains(err.Error(), c.wantMsg) {
				t.Errorf("error %q no contiene %q", err.Error(), c.wantMsg)
			}
		})
	}
}

// BUG-S2-06: Generate must reject tickets with empty TicketID or ProjectID.
func TestGenerateRequiresTicketAndProject(t *testing.T) {
	cases := []struct {
		name    string
		ticket  *parser.TicketRequest
		wantMsg string
	}{
		{
			"empty TicketID",
			&parser.TicketRequest{TicketID: "", ProjectID: "gnp-test-qa", TaskType: parser.TaskIAMProject, ProjectRoles: []string{"roles/viewer"}},
			"TicketID",
		},
		{
			"empty ProjectID",
			&parser.TicketRequest{TicketID: "CTASK0001", ProjectID: "", TaskType: parser.TaskIAMProject, ProjectRoles: []string{"roles/viewer"}},
			"ProjectID",
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			err := Generate(c.ticket, t.TempDir())
			if err == nil {
				t.Fatal("expected error, got nil")
			}
			if !strings.Contains(err.Error(), c.wantMsg) {
				t.Errorf("expected error containing %q, got: %v", c.wantMsg, err)
			}
		})
	}
}

// BUG-S2-04: Generate must reject tickets with missing task-type-required fields.
func TestGenerateValidatesRequiredFields(t *testing.T) {
	cases := []struct {
		name    string
		ticket  *parser.TicketRequest
		wantMsg string
	}{
		{
			"gke_secret missing Cluster",
			&parser.TicketRequest{
				TicketID: "T1", ProjectID: "proj", TaskType: parser.TaskGKESecret,
				Namespace: "ns", KubeSecretName: "sec",
				KubeSecretData: []parser.KubeSecretEntry{{Key: "k", Value: "v"}},
			},
			"Cluster",
		},
		{
			"gke_secret empty KubeSecretData",
			&parser.TicketRequest{
				TicketID: "T2", ProjectID: "proj", TaskType: parser.TaskGKESecret,
				Cluster: "c", Namespace: "ns", KubeSecretName: "sec",
			},
			"KubeSecretData",
		},
		{
			"iam_bucket missing Buckets",
			&parser.TicketRequest{
				TicketID: "T3", ProjectID: "proj", TaskType: parser.TaskIAMBucket,
				BucketRoles: []string{"roles/storage.objectViewer"},
			},
			"Buckets",
		},
		{
			"iam_bucket missing BucketRoles",
			&parser.TicketRequest{
				TicketID: "T4", ProjectID: "proj", TaskType: parser.TaskIAMBucket,
				Buckets: []string{"my-bucket"},
			},
			"BucketRoles",
		},
		{
			"pubsub_create empty topics",
			&parser.TicketRequest{
				TicketID: "T5", ProjectID: "proj", TaskType: parser.TaskPubSubCreate,
			},
			"Topics",
		},
		{
			"iam_project empty roles",
			&parser.TicketRequest{
				TicketID: "T6", ProjectID: "proj", TaskType: parser.TaskIAMProject,
			},
			"ProjectRoles",
		},
		{
			"secret_manager_iam empty secrets",
			&parser.TicketRequest{
				TicketID: "T7", ProjectID: "proj", TaskType: parser.TaskSecretManagerIAM,
				SecretRoles: []string{"roles/secretmanager.secretAccessor"},
			},
			"Secrets",
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			err := Generate(c.ticket, t.TempDir())
			if err == nil {
				t.Fatal("expected validation error, got nil")
			}
			if !strings.Contains(err.Error(), c.wantMsg) {
				t.Errorf("expected error containing %q, got: %v", c.wantMsg, err)
			}
		})
	}
}

func TestNewTemplateDataMembers(t *testing.T) {
	ticket := &parser.TicketRequest{
		Principals: []parser.Principal{
			{Type: "serviceAccount", Email: "sa@proj.iam.gserviceaccount.com"},
			{Type: "group", Email: "team@gnp.com.mx"},
		},
	}
	data := newTemplateData(ticket)
	if len(data.Members) != 2 {
		t.Fatalf("expected 2 members, got %d", len(data.Members))
	}
	if data.Members[0] != "serviceAccount:sa@proj.iam.gserviceaccount.com" {
		t.Errorf("unexpected member[0]: %q", data.Members[0])
	}
	if data.Members[1] != "group:team@gnp.com.mx" {
		t.Errorf("unexpected member[1]: %q", data.Members[1])
	}
}

func TestNewTemplateDataKubeArgs(t *testing.T) {
	ticket := &parser.TicketRequest{
		KubeSecretData: []parser.KubeSecretEntry{
			{Key: "DB_PASS", Value: "secret123"},
		},
	}
	data := newTemplateData(ticket)
	if len(data.KubeFromLiterals) != 1 {
		t.Fatalf("expected 1 kube arg, got %d", len(data.KubeFromLiterals))
	}
	if data.KubeFromLiterals[0] != "--from-literal=DB_PASS=secret123" {
		t.Errorf("unexpected kube arg: %q", data.KubeFromLiterals[0])
	}
}

func TestBashArrayFuncMap(t *testing.T) {
	fm := funcMap()
	bashArrayFn := fm["bashArray"].(func([]string) string)

	cases := []struct {
		input []string
		want  string
	}{
		{nil, "()"},
		{[]string{}, "()"},
		{[]string{"a"}, `("a")`},
		{[]string{"a", "b"}, `("a" "b")`},
		{[]string{"roles/storage.objectViewer"}, `("roles/storage.objectViewer")`},
	}
	for _, c := range cases {
		got := bashArrayFn(c.input)
		if got != c.want {
			t.Errorf("bashArray(%v) = %q, want %q", c.input, got, c.want)
		}
	}
}

func TestRetentionDurationFuncMap(t *testing.T) {
	fm := funcMap()
	fn := fm["retentionDuration"].(func(int) string)

	if fn(7) != "7d" {
		t.Errorf("retentionDuration(7) = %q, want %q", fn(7), "7d")
	}
	if fn(0) != "7d" {
		t.Errorf("retentionDuration(0) = %q, want default %q", fn(0), "7d")
	}
	if fn(30) != "30d" {
		t.Errorf("retentionDuration(30) = %q, want %q", fn(30), "30d")
	}
}
