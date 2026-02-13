#!/usr/bin/env python3
"""
Workload Identity Manager
Configure GCP Workload Identity between GCP Service Accounts and Kubernetes Service Accounts.

Usage:
    python workload-identity.py setup --project PROJECT --gcp-sa SA --ksa KSA --namespace NS
    python workload-identity.py verify --project PROJECT --gcp-sa SA --ksa KSA --namespace NS
    python workload-identity.py cleanup --project PROJECT --gcp-sa SA --ksa KSA --namespace NS
    python workload-identity.py list --project PROJECT
"""

import argparse
import subprocess
import sys
import json
import os
from dataclasses import dataclass
from datetime import datetime
from typing import Optional, Tuple, List
import csv

# ============================================================================
# Data Classes
# ============================================================================

@dataclass
class WorkloadIdentityBinding:
    """Represents a Workload Identity binding configuration"""
    project_id: str
    gcp_sa_name: str
    ksa_name: str
    namespace: str
    target_namespace: Optional[str] = None
    
    @property
    def gcp_sa_email(self) -> str:
        """Returns full GCP SA email"""
        if "@" in self.gcp_sa_name:
            return self.gcp_sa_name
        return f"{self.gcp_sa_name}@{self.project_id}.iam.gserviceaccount.com"
    
    @property
    def effective_namespace(self) -> str:
        """Returns target namespace or source namespace"""
        return self.target_namespace or self.namespace
    
    @property
    def member_identity(self) -> str:
        """Returns the Workload Identity member string"""
        return f"serviceAccount:{self.project_id}.svc.id.goog[{self.effective_namespace}/{self.ksa_name}]"


@dataclass
class ClusterContext:
    """Represents current Kubernetes cluster context"""
    name: str
    cluster: str
    project: Optional[str] = None
    location: Optional[str] = None


@dataclass
class OperationResult:
    """Result of a Workload Identity operation"""
    success: bool
    message: str
    details: Optional[dict] = None


# ============================================================================
# Logging
# ============================================================================

class Logger:
    """Simple logger with file output"""
    
    def __init__(self, log_file: Optional[str] = None):
        self.log_file = log_file
        if log_file:
            os.makedirs(os.path.dirname(log_file), exist_ok=True)
    
    def _write(self, message: str):
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        entry = f"[{timestamp}] {message}"
        print(entry)
        if self.log_file:
            with open(self.log_file, "a") as f:
                f.write(entry + "\n")
    
    def info(self, message: str):
        self._write(message)
    
    def success(self, message: str):
        self._write(f"✓ {message}")
    
    def error(self, message: str):
        self._write(f"✗ {message}")
    
    def warning(self, message: str):
        self._write(f"⚠ {message}")
    
    def header(self, message: str):
        self._write("=" * 60)
        self._write(message)
        self._write("=" * 60)


# ============================================================================
# Command Executor
# ============================================================================

class CommandExecutor:
    """Execute shell commands with proper error handling"""
    
    def __init__(self, logger: Logger, dry_run: bool = False):
        self.logger = logger
        self.dry_run = dry_run
    
    def run(self, cmd: List[str], description: str, 
            check: bool = True, capture: bool = True) -> Tuple[bool, str]:
        """Execute command and return (success, output)"""
        
        if self.dry_run:
            self.logger.info(f"[DRY-RUN] {description}")
            self.logger.info(f"  Would execute: {' '.join(cmd)}")
            return True, "[dry-run output]"
        
        try:
            result = subprocess.run(
                cmd,
                capture_output=capture,
                text=True,
                check=False
            )
            
            if result.returncode != 0:
                if check:
                    self.logger.error(f"{description}: {result.stderr.strip()}")
                    return False, result.stderr
                return False, result.stderr
            
            return True, result.stdout.strip() if result.stdout else ""
            
        except Exception as e:
            self.logger.error(f"{description}: {str(e)}")
            return False, str(e)
    
    def run_json(self, cmd: List[str], description: str) -> Tuple[bool, Optional[dict]]:
        """Execute command and parse JSON output"""
        success, output = self.run(cmd, description)
        if not success:
            return False, None
        try:
            return True, json.loads(output) if output else {}
        except json.JSONDecodeError:
            return False, None


# ============================================================================
# GCP Operations
# ============================================================================

class GCPOperations:
    """GCP-related operations"""
    
    def __init__(self, executor: CommandExecutor, logger: Logger):
        self.executor = executor
        self.logger = logger
    
    def verify_service_account(self, binding: WorkloadIdentityBinding) -> bool:
        """Verify GCP Service Account exists"""
        success, _ = self.executor.run(
            ["gcloud", "iam", "service-accounts", "describe", 
             binding.gcp_sa_email, "--project", binding.project_id,
             "--format=json"],
            f"Verify GCP SA: {binding.gcp_sa_email}"
        )
        return success
    
    def add_iam_binding(self, binding: WorkloadIdentityBinding) -> bool:
        """Add IAM binding for Workload Identity"""
        success, _ = self.executor.run(
            ["gcloud", "iam", "service-accounts", "add-iam-policy-binding",
             binding.gcp_sa_email,
             "--project", binding.project_id,
             "--role", "roles/iam.workloadIdentityUser",
             "--member", binding.member_identity],
            f"Add IAM binding: {binding.ksa_name} → {binding.gcp_sa_email}"
        )
        return success
    
    def remove_iam_binding(self, binding: WorkloadIdentityBinding, 
                           namespace_override: Optional[str] = None) -> bool:
        """Remove IAM binding for Workload Identity"""
        ns = namespace_override or binding.effective_namespace
        member = f"serviceAccount:{binding.project_id}.svc.id.goog[{ns}/{binding.ksa_name}]"
        
        success, _ = self.executor.run(
            ["gcloud", "iam", "service-accounts", "remove-iam-policy-binding",
             binding.gcp_sa_email,
             "--project", binding.project_id,
             "--role", "roles/iam.workloadIdentityUser",
             "--member", member],
            f"Remove IAM binding from {ns}",
            check=False
        )
        return success
    
    def get_iam_policy(self, binding: WorkloadIdentityBinding) -> Tuple[bool, Optional[dict]]:
        """Get IAM policy for service account"""
        return self.executor.run_json(
            ["gcloud", "iam", "service-accounts", "get-iam-policy",
             binding.gcp_sa_email, "--project", binding.project_id,
             "--format=json"],
            f"Get IAM policy: {binding.gcp_sa_email}"
        )
    
    def list_service_accounts(self, project_id: str) -> Tuple[bool, List[dict]]:
        """List service accounts in project"""
        success, data = self.executor.run_json(
            ["gcloud", "iam", "service-accounts", "list",
             "--project", project_id, "--format=json"],
            f"List service accounts in {project_id}"
        )
        return success, data if success and data else []


# ============================================================================
# Kubernetes Operations
# ============================================================================

class K8sOperations:
    """Kubernetes-related operations"""
    
    def __init__(self, executor: CommandExecutor, logger: Logger):
        self.executor = executor
        self.logger = logger
    
    def get_current_context(self) -> Optional[ClusterContext]:
        """Get current kubectl context"""
        success, output = self.executor.run(
            ["kubectl", "config", "current-context"],
            "Get current context"
        )
        if not success:
            return None
        
        context_name = output.strip()
        
        # Try to extract GKE info from context name
        # Format: gke_PROJECT_LOCATION_CLUSTER
        parts = context_name.split("_")
        if len(parts) >= 4 and parts[0] == "gke":
            return ClusterContext(
                name=context_name,
                cluster=parts[3],
                project=parts[1],
                location=parts[2]
            )
        
        return ClusterContext(name=context_name, cluster=context_name)
    
    def namespace_exists(self, namespace: str) -> bool:
        """Check if namespace exists"""
        success, _ = self.executor.run(
            ["kubectl", "get", "namespace", namespace],
            f"Check namespace: {namespace}",
            check=False
        )
        return success
    
    def create_namespace(self, namespace: str) -> bool:
        """Create namespace if it doesn't exist"""
        if self.namespace_exists(namespace):
            self.logger.info(f"Namespace {namespace} already exists")
            return True
        
        success, _ = self.executor.run(
            ["kubectl", "create", "namespace", namespace],
            f"Create namespace: {namespace}"
        )
        return success
    
    def service_account_exists(self, name: str, namespace: str) -> bool:
        """Check if service account exists"""
        success, _ = self.executor.run(
            ["kubectl", "get", "serviceaccount", name, "-n", namespace],
            f"Check KSA: {name} in {namespace}",
            check=False
        )
        return success
    
    def create_service_account(self, name: str, namespace: str) -> bool:
        """Create Kubernetes service account"""
        if self.service_account_exists(name, namespace):
            self.logger.info(f"KSA {name} already exists in {namespace}")
            return True
        
        success, _ = self.executor.run(
            ["kubectl", "create", "serviceaccount", name, "-n", namespace],
            f"Create KSA: {name}"
        )
        return success
    
    def delete_service_account(self, name: str, namespace: str) -> bool:
        """Delete Kubernetes service account"""
        success, _ = self.executor.run(
            ["kubectl", "delete", "serviceaccount", name, "-n", namespace],
            f"Delete KSA: {name} from {namespace}",
            check=False
        )
        return success
    
    def annotate_service_account(self, name: str, namespace: str, 
                                  gcp_sa_email: str) -> bool:
        """Annotate KSA with GCP SA email"""
        success, _ = self.executor.run(
            ["kubectl", "annotate", "serviceaccount", name,
             "-n", namespace,
             f"iam.gke.io/gcp-service-account={gcp_sa_email}",
             "--overwrite"],
            f"Annotate KSA: {name}"
        )
        return success
    
    def get_service_account_annotation(self, name: str, namespace: str) -> Optional[str]:
        """Get GCP SA annotation from KSA"""
        success, output = self.executor.run(
            ["kubectl", "get", "serviceaccount", name, "-n", namespace,
             "-o", "jsonpath={.metadata.annotations.iam\\.gke\\.io/gcp-service-account}"],
            f"Get KSA annotation: {name}",
            check=False
        )
        return output if success and output else None
    
    def describe_service_account(self, name: str, namespace: str) -> Tuple[bool, str]:
        """Describe service account"""
        return self.executor.run(
            ["kubectl", "describe", "serviceaccount", name, "-n", namespace],
            f"Describe KSA: {name}"
        )
    
    def list_service_accounts(self, namespace: Optional[str] = None) -> Tuple[bool, str]:
        """List Kubernetes service accounts"""
        cmd = ["kubectl", "get", "serviceaccounts"]
        if namespace:
            cmd.extend(["-n", namespace])
        else:
            cmd.append("-A")
        cmd.extend(["-o", "wide"])
        
        return self.executor.run(cmd, "List Kubernetes service accounts")


# ============================================================================
# Workload Identity Manager
# ============================================================================

class WorkloadIdentityManager:
    """Main manager for Workload Identity operations"""
    
    def __init__(self, logger: Logger, dry_run: bool = False):
        self.logger = logger
        self.dry_run = dry_run
        self.executor = CommandExecutor(logger, dry_run)
        self.gcp = GCPOperations(self.executor, logger)
        self.k8s = K8sOperations(self.executor, logger)
    
    def setup(self, binding: WorkloadIdentityBinding) -> OperationResult:
        """Setup Workload Identity binding"""
        
        self.logger.header("Workload Identity Setup")
        self.logger.info(f"Project:     {binding.project_id}")
        self.logger.info(f"GCP SA:      {binding.gcp_sa_email}")
        self.logger.info(f"KSA:         {binding.ksa_name}")
        self.logger.info(f"Namespace:   {binding.namespace}")
        if binding.target_namespace and binding.target_namespace != binding.namespace:
            self.logger.info(f"Target NS:   {binding.target_namespace}")
        
        # Show cluster context
        context = self.k8s.get_current_context()
        if context:
            self.logger.info(f"Cluster:     {context.cluster}")
            if context.project:
                self.logger.info(f"GKE Project: {context.project}")
        
        self.logger.info("")
        
        # Verify GCP SA exists
        self.logger.info("Verifying GCP Service Account...")
        if not self.gcp.verify_service_account(binding):
            return OperationResult(False, f"GCP SA not found: {binding.gcp_sa_email}")
        self.logger.success("GCP SA verified")
        
        # Handle namespace migration
        if binding.target_namespace and binding.target_namespace != binding.namespace:
            self.logger.info("")
            self.logger.info(f"Migrating from {binding.namespace} to {binding.target_namespace}...")
            
            # Remove old binding
            self.gcp.remove_iam_binding(binding, binding.namespace)
            
            # Delete old KSA
            self.k8s.delete_service_account(binding.ksa_name, binding.namespace)
        
        # Create target namespace
        self.logger.info("")
        if not self.k8s.create_namespace(binding.effective_namespace):
            return OperationResult(False, f"Failed to create namespace: {binding.effective_namespace}")
        
        # Create KSA
        if not self.k8s.create_service_account(binding.ksa_name, binding.effective_namespace):
            return OperationResult(False, f"Failed to create KSA: {binding.ksa_name}")
        
        # Add IAM binding
        self.logger.info("")
        self.logger.info("Adding IAM binding...")
        if not self.gcp.add_iam_binding(binding):
            return OperationResult(False, "Failed to add IAM binding")
        self.logger.success("IAM binding added")
        
        # Annotate KSA
        self.logger.info("")
        self.logger.info("Annotating KSA...")
        if not self.k8s.annotate_service_account(
            binding.ksa_name, 
            binding.effective_namespace,
            binding.gcp_sa_email
        ):
            return OperationResult(False, "Failed to annotate KSA")
        self.logger.success("KSA annotated")
        
        self.logger.info("")
        self.logger.header("Setup Completed Successfully")
        
        return OperationResult(True, "Workload Identity configured successfully")
    
    def verify(self, binding: WorkloadIdentityBinding) -> OperationResult:
        """Verify Workload Identity configuration"""
        
        self.logger.header("Workload Identity Verification")
        self.logger.info(f"Project:   {binding.project_id}")
        self.logger.info(f"GCP SA:    {binding.gcp_sa_email}")
        self.logger.info(f"KSA:       {binding.ksa_name}")
        self.logger.info(f"Namespace: {binding.effective_namespace}")
        self.logger.info("")
        
        errors = []
        
        # Check KSA exists
        self.logger.info("Checking KSA...")
        if not self.k8s.service_account_exists(binding.ksa_name, binding.effective_namespace):
            errors.append(f"KSA not found: {binding.ksa_name} in {binding.effective_namespace}")
        else:
            self.logger.success(f"KSA exists: {binding.ksa_name}")
        
        # Check annotation
        self.logger.info("")
        self.logger.info("Checking annotation...")
        annotation = self.k8s.get_service_account_annotation(
            binding.ksa_name, 
            binding.effective_namespace
        )
        if annotation == binding.gcp_sa_email:
            self.logger.success(f"Annotation correct: {annotation}")
        elif annotation:
            errors.append(f"Annotation mismatch. Expected: {binding.gcp_sa_email}, Found: {annotation}")
        else:
            errors.append("KSA annotation missing")
        
        # Check IAM binding
        self.logger.info("")
        self.logger.info("Checking IAM binding...")
        success, policy = self.gcp.get_iam_policy(binding)
        if success and policy:
            bindings = policy.get("bindings", [])
            has_binding = False
            for b in bindings:
                if b.get("role") == "roles/iam.workloadIdentityUser":
                    if binding.member_identity in b.get("members", []):
                        has_binding = True
                        break
            
            if has_binding:
                self.logger.success("IAM binding exists")
            else:
                errors.append(f"IAM binding not found for {binding.member_identity}")
        else:
            errors.append("Could not retrieve IAM policy")
        
        self.logger.info("")
        if errors:
            self.logger.header("Verification Failed")
            for error in errors:
                self.logger.error(error)
            return OperationResult(False, "Verification failed", {"errors": errors})
        
        self.logger.header("Verification Passed")
        return OperationResult(True, "Workload Identity is properly configured")
    
    def cleanup(self, binding: WorkloadIdentityBinding) -> OperationResult:
        """Remove Workload Identity binding"""
        
        self.logger.header("Workload Identity Cleanup")
        self.logger.info(f"Project:   {binding.project_id}")
        self.logger.info(f"GCP SA:    {binding.gcp_sa_email}")
        self.logger.info(f"KSA:       {binding.ksa_name}")
        self.logger.info(f"Namespace: {binding.effective_namespace}")
        self.logger.info("")
        
        # Remove IAM binding
        self.logger.info("Removing IAM binding...")
        self.gcp.remove_iam_binding(binding)
        self.logger.success("IAM binding removed")
        
        # Delete KSA
        self.logger.info("")
        self.logger.info("Deleting KSA...")
        self.k8s.delete_service_account(binding.ksa_name, binding.effective_namespace)
        self.logger.success("KSA deleted")
        
        self.logger.info("")
        self.logger.header("Cleanup Completed")
        
        return OperationResult(True, "Workload Identity binding removed")
    
    def list_resources(self, project_id: str, namespace: Optional[str] = None):
        """List GCP and K8s service accounts"""
        
        self.logger.header("Service Accounts")
        
        # List GCP SAs
        self.logger.info("")
        self.logger.info("GCP Service Accounts:")
        success, accounts = self.gcp.list_service_accounts(project_id)
        if success and accounts:
            for sa in accounts:
                email = sa.get("email", "")
                name = sa.get("displayName", "")
                self.logger.info(f"  {email} ({name})")
        else:
            self.logger.warning("No GCP service accounts found or unable to list")
        
        # List K8s SAs
        self.logger.info("")
        self.logger.info("Kubernetes Service Accounts:")
        success, output = self.k8s.list_service_accounts(namespace)
        if success and output:
            for line in output.split("\n"):
                self.logger.info(f"  {line}")
    
    def batch_process(self, csv_file: str, action: str) -> List[OperationResult]:
        """Process multiple bindings from CSV file"""
        
        self.logger.header(f"Batch Processing: {action}")
        self.logger.info(f"File: {csv_file}")
        self.logger.info("")
        
        results = []
        
        try:
            with open(csv_file, "r") as f:
                reader = csv.DictReader(f)
                for row in reader:
                    binding = WorkloadIdentityBinding(
                        project_id=row.get("project", row.get("project_id", "")),
                        gcp_sa_name=row.get("gcp_sa", row.get("gcp_sa_name", "")),
                        ksa_name=row.get("ksa", row.get("ksa_name", "")),
                        namespace=row.get("namespace", ""),
                        target_namespace=row.get("target_namespace") or None
                    )
                    
                    if not all([binding.project_id, binding.gcp_sa_name, 
                                binding.ksa_name, binding.namespace]):
                        self.logger.warning(f"Skipping incomplete row: {row}")
                        continue
                    
                    self.logger.info(f"Processing: {binding.ksa_name} in {binding.effective_namespace}")
                    
                    if action == "setup":
                        result = self.setup(binding)
                    elif action == "verify":
                        result = self.verify(binding)
                    elif action == "cleanup":
                        result = self.cleanup(binding)
                    else:
                        result = OperationResult(False, f"Unknown action: {action}")
                    
                    results.append(result)
                    self.logger.info("")
            
            # Summary
            success_count = sum(1 for r in results if r.success)
            self.logger.header("Batch Summary")
            self.logger.info(f"Total: {len(results)}")
            self.logger.info(f"Success: {success_count}")
            self.logger.info(f"Failed: {len(results) - success_count}")
            
        except FileNotFoundError:
            self.logger.error(f"File not found: {csv_file}")
            results.append(OperationResult(False, f"File not found: {csv_file}"))
        except Exception as e:
            self.logger.error(f"Error processing file: {str(e)}")
            results.append(OperationResult(False, str(e)))
        
        return results


# ============================================================================
# CLI
# ============================================================================

def create_parser() -> argparse.ArgumentParser:
    """Create argument parser"""
    
    parser = argparse.ArgumentParser(
        description="Workload Identity Manager - Configure GCP Workload Identity",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s setup --project gnp-app-qa --gcp-sa sa-backend --ksa ka-backend --namespace apps
  %(prog)s setup --project gnp-app-qa --gcp-sa sa-backend --ksa ka-backend --namespace default --target-namespace apps
  %(prog)s verify --project gnp-app-qa --gcp-sa sa-backend --ksa ka-backend --namespace apps
  %(prog)s cleanup --project gnp-app-qa --gcp-sa sa-backend --ksa ka-backend --namespace apps
  %(prog)s list --project gnp-app-qa
  %(prog)s list --project gnp-app-qa --namespace apps
        """
    )
    
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be done without executing")
    parser.add_argument("--no-log", action="store_true",
                        help="Disable file logging")
    
    subparsers = parser.add_subparsers(dest="command", help="Commands")
    
    # Setup command
    setup_parser = subparsers.add_parser("setup", 
                                          help="Configure Workload Identity")
    setup_parser.add_argument("--project", "-p", required=True,
                               help="GCP Project ID")
    setup_parser.add_argument("--gcp-sa", "-g", required=True,
                               help="GCP Service Account (name or email)")
    setup_parser.add_argument("--ksa", "-k", required=True,
                               help="Kubernetes Service Account name")
    setup_parser.add_argument("--namespace", "-n", required=True,
                               help="Kubernetes namespace")
    setup_parser.add_argument("--target-namespace", "-t",
                               help="Target namespace (for migration)")
    
    # Verify command
    verify_parser = subparsers.add_parser("verify",
                                           help="Verify Workload Identity")
    verify_parser.add_argument("--project", "-p", required=True,
                                help="GCP Project ID")
    verify_parser.add_argument("--gcp-sa", "-g", required=True,
                                help="GCP Service Account (name or email)")
    verify_parser.add_argument("--ksa", "-k", required=True,
                                help="Kubernetes Service Account name")
    verify_parser.add_argument("--namespace", "-n", required=True,
                                help="Kubernetes namespace")
    
    # Cleanup command
    cleanup_parser = subparsers.add_parser("cleanup",
                                            help="Remove Workload Identity binding")
    cleanup_parser.add_argument("--project", "-p", required=True,
                                 help="GCP Project ID")
    cleanup_parser.add_argument("--gcp-sa", "-g", required=True,
                                 help="GCP Service Account (name or email)")
    cleanup_parser.add_argument("--ksa", "-k", required=True,
                                 help="Kubernetes Service Account name")
    cleanup_parser.add_argument("--namespace", "-n", required=True,
                                 help="Kubernetes namespace")
    
    # List command
    list_parser = subparsers.add_parser("list",
                                         help="List service accounts")
    list_parser.add_argument("--project", "-p", required=True,
                              help="GCP Project ID")
    list_parser.add_argument("--namespace", "-n",
                              help="Filter by namespace (optional)")
    
    # Batch command
    batch_parser = subparsers.add_parser("batch",
                                          help="Process multiple bindings from file")
    batch_parser.add_argument("--file", "-f", required=True,
                               help="CSV file with bindings (project,gcp_sa,ksa,namespace,target_namespace)")
    batch_parser.add_argument("--action", "-a", choices=["setup", "verify", "cleanup"],
                               default="setup", help="Action to perform (default: setup)")
    
    return parser


def main():
    """Main entry point"""
    
    parser = create_parser()
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    # Setup logger
    script_dir = os.path.dirname(os.path.abspath(__file__))
    log_file = None if args.no_log else os.path.join(script_dir, "logs", "workload_identity.log")
    logger = Logger(log_file)
    
    # Create manager
    manager = WorkloadIdentityManager(logger, args.dry_run)
    
    if args.dry_run:
        logger.warning("DRY-RUN MODE - No changes will be made")
        logger.info("")
    
    try:
        if args.command == "setup":
            binding = WorkloadIdentityBinding(
                project_id=args.project,
                gcp_sa_name=args.gcp_sa,
                ksa_name=args.ksa,
                namespace=args.namespace,
                target_namespace=args.target_namespace
            )
            result = manager.setup(binding)
            
        elif args.command == "verify":
            binding = WorkloadIdentityBinding(
                project_id=args.project,
                gcp_sa_name=args.gcp_sa,
                ksa_name=args.ksa,
                namespace=args.namespace
            )
            result = manager.verify(binding)
            
        elif args.command == "cleanup":
            binding = WorkloadIdentityBinding(
                project_id=args.project,
                gcp_sa_name=args.gcp_sa,
                ksa_name=args.ksa,
                namespace=args.namespace
            )
            result = manager.cleanup(binding)
            
        elif args.command == "list":
            manager.list_resources(args.project, args.namespace)
            sys.exit(0)
        
        elif args.command == "batch":
            results = manager.batch_process(args.file, args.action)
            all_success = all(r.success for r in results)
            sys.exit(0 if all_success else 1)
        
        sys.exit(0 if result.success else 1)
        
    except KeyboardInterrupt:
        logger.info("\nOperation cancelled")
        sys.exit(130)
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        sys.exit(1)


if __name__ == "__main__":
    main()
