#!/usr/bin/env python3

import subprocess
import sys
import os
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_FILE = os.path.join(SCRIPT_DIR, "..", "logs", "workload_identity.log")

# Ensure logs directory exists
os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)

def log_message(message):
    """Log message with timestamp"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_entry = f"[{timestamp}] {message}"
    print(log_entry)
    with open(LOG_FILE, "a") as f:
        f.write(log_entry + "\n")

def run_command(cmd, description, check=True):
    """Execute command and return (success, output)"""
    log_message(f"→ {description}")
    log_message(f"  Command: {' '.join(cmd)}")
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        
        if result.stdout:
            log_message(f"  Output: {result.stdout.strip()}")
        
        if result.returncode != 0:
            if check:
                log_message(f"  ✗ Error: {result.stderr.strip()}")
                return False, result.stderr
            else:
                log_message(f"  (Note) {result.stderr.strip()}")
                return False, result.stderr
        
        log_message(f"  ✓ Done")
        return True, result.stdout
    except Exception as e:
        log_message(f"  ✗ Exception: {str(e)}")
        return False, str(e)

def setup_workload_identity(project_id, gcp_sa_name, ksa_name, namespace, new_namespace=None):
    """
    Setup Workload Identity between GCP SA and Kubernetes SA
    
    Args:
        project_id: GCP Project ID
        gcp_sa_name: GCP Service Account email (or name)
        ksa_name: Kubernetes Service Account name
        namespace: Source namespace (for cleanup if needed)
        new_namespace: Target namespace (if None, uses source namespace)
    """
    
    if new_namespace is None:
        new_namespace = namespace
    
    # Handle SA name - convert to email if needed
    if "@" not in gcp_sa_name:
        gcp_sa = f"{gcp_sa_name}@{project_id}.iam.gserviceaccount.com"
    else:
        gcp_sa = gcp_sa_name
    
    log_message("")
    log_message("=" * 80)
    log_message(f"Setting up Workload Identity")
    log_message("=" * 80)
    log_message(f"Project: {project_id}")
    log_message(f"GCP Service Account: {gcp_sa}")
    log_message(f"Kubernetes Service Account: {ksa_name}")
    log_message(f"Source Namespace: {namespace}")
    log_message(f"Target Namespace: {new_namespace}")
    
    try:
        # Verify GCP SA exists
        log_message("")
        log_message("Verifying GCP Service Account...")
        success, _ = run_command(
            ["gcloud", "iam", "service-accounts", "describe", gcp_sa, "--project", project_id],
            f"Verify GCP SA {gcp_sa}",
            check=True
        )
        if not success:
            log_message(f"✗ GCP SA not found: {gcp_sa}")
            return False
        
        # If source namespace differs from target, clean up source
        if namespace != new_namespace:
            log_message("")
            log_message(f"Cleaning up source namespace ({namespace})...")
            
            # Remove IAM binding from source namespace
            run_command(
                ["gcloud", "iam", "service-accounts", "remove-iam-policy-binding", gcp_sa,
                 "--project", project_id,
                 "--role", "roles/iam.workloadIdentityUser",
                 "--member", f"serviceAccount:{project_id}.svc.id.goog[{namespace}/{ksa_name}]"],
                f"Remove IAM binding from {namespace}",
                check=False
            )
            
            # Delete KSA from source namespace
            run_command(
                ["kubectl", "delete", "serviceaccount", ksa_name, "-n", namespace],
                f"Delete KSA from {namespace}",
                check=False
            )
        
        # Create target namespace if it doesn't exist
        log_message("")
        log_message(f"Setting up target namespace ({new_namespace})...")
        
        result = subprocess.run(
            ["kubectl", "get", "namespace", new_namespace],
            capture_output=True, text=True
        )
        
        if result.returncode != 0:
            success, _ = run_command(
                ["kubectl", "create", "namespace", new_namespace],
                f"Create namespace {new_namespace}",
                check=True
            )
            if not success:
                return False
        else:
            log_message(f"(info) Namespace {new_namespace} already exists")
        
        # Create KSA
        log_message("")
        log_message(f"Creating Kubernetes Service Account...")
        success, _ = run_command(
            ["kubectl", "create", "serviceaccount", ksa_name, "-n", new_namespace],
            f"Create KSA {ksa_name}",
            check=True
        )
        if not success:
            # KSA might already exist, continue
            log_message("(info) KSA may already exist, continuing...")
        
        # Add IAM binding
        log_message("")
        log_message(f"Adding IAM binding...")
        success, _ = run_command(
            ["gcloud", "iam", "service-accounts", "add-iam-policy-binding", gcp_sa,
             "--project", project_id,
             "--role", "roles/iam.workloadIdentityUser",
             "--member", f"serviceAccount:{project_id}.svc.id.goog[{new_namespace}/{ksa_name}]"],
            "Add IAM workloadIdentityUser binding",
            check=True
        )
        if not success:
            return False
        
        # Annotate KSA
        log_message("")
        log_message(f"Annotating KSA...")
        success, _ = run_command(
            ["kubectl", "annotate", "serviceaccount", ksa_name,
             "--namespace", new_namespace,
             f"iam.gke.io/gcp-service-account={gcp_sa}",
             "--overwrite"],
            "Annotate KSA with GCP SA",
            check=True
        )
        if not success:
            return False
        
        # Verify
        log_message("")
        log_message("=" * 80)
        log_message("Verification")
        log_message("=" * 80)
        
        run_command(
            ["kubectl", "describe", "serviceaccount", ksa_name, "-n", new_namespace],
            "Describe KSA",
            check=False
        )
        
        log_message("")
        run_command(
            ["gcloud", "iam", "service-accounts", "get-iam-policy", gcp_sa, "--project", project_id],
            "Get IAM policy",
            check=False
        )
        
        log_message("")
        log_message("=" * 80)
        log_message("✓ Workload Identity setup completed successfully")
        log_message("=" * 80)
        
        return True
        
    except Exception as e:
        log_message(f"✗ Unexpected error: {str(e)}")
        return False

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: workload_identity.py <project_id> <gcp_sa> <ksa_name> <namespace> [new_namespace]")
        print("")
        print("Examples:")
        print("  workload_identity.py gnp-reveca-qa sa-backend-qa ka-backend-qa default apps")
        print("  workload_identity.py gnp-reveca-qa sa-backend-qa@gnp-reveca-qa.iam.gserviceaccount.com ka-backend-qa default apps")
        sys.exit(1)
    
    project_id = sys.argv[1]
    gcp_sa = sys.argv[2]
    ksa_name = sys.argv[3]
    namespace = sys.argv[4]
    new_namespace = sys.argv[5] if len(sys.argv) > 5 else namespace
    
    success = setup_workload_identity(project_id, gcp_sa, ksa_name, namespace, new_namespace)
    sys.exit(0 if success else 1)
