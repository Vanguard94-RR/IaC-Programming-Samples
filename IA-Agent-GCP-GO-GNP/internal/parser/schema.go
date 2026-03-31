package parser

// TaskType identifica el tipo de operación GCP que debe realizarse.
type TaskType string

const (
	TaskIAMProject          TaskType = "iam_project"
	TaskIAMBucket           TaskType = "iam_bucket"
	TaskIAMPubSub           TaskType = "iam_pubsub"
	TaskIAMBigQuery         TaskType = "iam_bigquery"
	TaskSecretManagerIAM    TaskType = "secret_manager_iam"
	TaskSecretManagerCreate TaskType = "secret_manager_create"
	TaskGKESecret           TaskType = "gke_secret"
	TaskPubSubCreate        TaskType = "pubsub_create"
	TaskSACreation          TaskType = "sa_creation"
	TaskCloudScheduler      TaskType = "cloud_scheduler"
	TaskEnableAPIs          TaskType = "enable_apis"
	TaskGitLabBucketUpload  TaskType = "gitlab_bucket_upload"
	TaskMixed               TaskType = "mixed"
	TaskUnknown             TaskType = "unknown"
)

// Principal representa un miembro GCP: serviceAccount, group o user.
type Principal struct {
	Type  string `json:"type"`  // "serviceAccount" | "group" | "user"
	Email string `json:"email"`
}

// SubscriptionConfig contiene la configuración de una suscripción Pub/Sub.
type SubscriptionConfig struct {
	Name             string `json:"name"`
	Topic            string `json:"topic"`
	AckDeadline      int    `json:"ack_deadline_seconds"`
	RetentionDays    int    `json:"retention_days"`
	ExpirationPolicy string `json:"expiration_policy"` // "never" | duration ISO
	DeliveryType     string `json:"delivery_type"`     // "pull" | "push"
	PushEndpoint     string `json:"push_endpoint,omitempty"`
}

// SchedulerConfig contiene la configuración de un job de Cloud Scheduler.
type SchedulerConfig struct {
	Name        string `json:"name"`
	Region      string `json:"region"`      // FIX BUG-04: requerido por gcloud scheduler
	Schedule    string `json:"schedule"`
	Timezone    string `json:"timezone"`
	TargetType  string `json:"target_type"`           // "http" | "pubsub"
	TargetURL   string `json:"target_url,omitempty"`
	TargetTopic string `json:"target_topic,omitempty"`
	HTTPMethod  string `json:"http_method,omitempty"`
	Body        string `json:"body,omitempty"`
	APIKey      string `json:"api_key,omitempty"`
	MaxRetries  int    `json:"max_retries,omitempty"`
}

// SecretEntry es un par nombre-valor para crear secretos en Secret Manager.
// FIX BUG-14: permite representar múltiples secretos en un solo ticket.
type SecretEntry struct {
	Name  string `json:"name"`
	Value string `json:"value"`
}

// KubeSecretEntry es un par clave-valor para un secreto de Kubernetes.
type KubeSecretEntry struct {
	Key   string `json:"key"`
	Value string `json:"value"`
}

// IsIAMTask returns true for task types that perform IAM role assignments
// and therefore require updating the Plantilla de Permisos IAM.xlsx.
func IsIAMTask(t TaskType) bool {
	switch t {
	case TaskIAMProject, TaskIAMBucket, TaskIAMPubSub, TaskIAMBigQuery, TaskSecretManagerIAM:
		return true
	}
	return false
}

// TicketRequest es la representación estructurada de un ticket parseado.
type TicketRequest struct {
	TicketID  string    `json:"ticket_id"`
	ProjectID string    `json:"project_id"`
	TaskType  TaskType  `json:"task_type"`
	RawText   string    `json:"raw_text,omitempty"`

	// Principals sobre los que aplica la operación
	Principals []Principal `json:"principals"`

	// Roles por scope
	ProjectRoles  []string `json:"project_roles,omitempty"`
	BucketRoles   []string `json:"bucket_roles,omitempty"`
	PubSubRoles   []string `json:"pubsub_roles,omitempty"`
	BigQueryRoles []string `json:"bigquery_roles,omitempty"`
	SecretRoles   []string `json:"secret_roles,omitempty"`

	// Recursos objetivo
	Secrets       []string             `json:"secrets,omitempty"`
	Buckets       []string             `json:"buckets,omitempty"`
	Topics        []string             `json:"topics,omitempty"`
	Subscriptions []SubscriptionConfig `json:"subscriptions,omitempty"`
	Datasets      []string             `json:"datasets,omitempty"`
	APIs          []string             `json:"apis,omitempty"`

	// GKE
	Cluster        string            `json:"cluster,omitempty"`
	Namespace      string            `json:"namespace,omitempty"`
	KubeSecretName string            `json:"kube_secret_name,omitempty"`
	KubeSecretData []KubeSecretEntry `json:"kube_secret_data,omitempty"`

	// Secret Manager — creación (FIX BUG-14: slice para múltiples secretos)
	SecretsToCreate []SecretEntry `json:"secrets_to_create,omitempty"`

	// Cloud Scheduler
	SchedulerJob *SchedulerConfig `json:"scheduler_job,omitempty"`

	// GitLab → Bucket
	GitLabRepo   string `json:"gitlab_repo,omitempty"`
	GitLabBranch string `json:"gitlab_branch,omitempty"`
	GitLabPath   string `json:"gitlab_path,omitempty"`

	// Region: requerido para Cloud Scheduler, Cloud Functions, etc.
	// FIX BUG-04: campo explícito en lugar de depender de cada sub-config.
	Region string `json:"region,omitempty"`

	// Entornos detectados del project_id
	Environments []string `json:"environments"`

	// Campos pendientes de confirmación — dispara estado STANDBY
	Ambiguous []string `json:"ambiguous,omitempty"`
}
