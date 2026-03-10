#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [terraform-args...]

Commands:
  init        Initialise Terraform (download providers)
  plan        Show what Terraform will create / change
  apply       Apply changes to the cluster
  destroy     Tear down all JupyterHub resources and the Kind cluster
  validate    Check syntax and configuration
  fmt         Format .tf files
  port-forward  Forward the proxy service to localhost:8080
  clean       Remove all Terraform-generated files (.terraform/, lock file, state files)

Any extra arguments are forwarded to the underlying command.

Examples:
  ./run.sh init
  ./run.sh plan
  ./run.sh apply -auto-approve
  ./run.sh destroy
  ./run.sh port-forward
  ./run.sh clean
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
  init)
    terraform -chdir="$TF_DIR" init "$@"
    ;;
  plan)
    terraform -chdir="$TF_DIR" plan "$@"
    ;;
  apply)
    terraform -chdir="$TF_DIR" apply "$@"
    echo
    echo "✅ JupyterHub is deployed!"
    PORT=$(terraform -chdir="$TF_DIR" output -raw proxy_host_port 2>/dev/null || echo "8080")
    echo "   Access it at: http://localhost:$PORT"
    ;;
  destroy)
    terraform -chdir="$TF_DIR" destroy "$@"
    ;;
  validate)
    terraform -chdir="$TF_DIR" init -backend=false -input=false > /dev/null 2>&1 || true
    terraform -chdir="$TF_DIR" validate "$@"
    ;;
  fmt)
    terraform -chdir="$TF_DIR" fmt "$@"
    ;;
  port-forward)
    NS=$(terraform -chdir="$TF_DIR" output -raw namespace 2>/dev/null || echo "jupyterhub")
    SVC=$(terraform -chdir="$TF_DIR" output -raw proxy_service_name 2>/dev/null || echo "jupyterhub-proxy-public")
    echo "Forwarding $SVC to http://localhost:8080 ..."
    kubectl port-forward -n "$NS" "svc/$SVC" 8080:80 "$@"
    ;;
  clean)
    echo "The following Terraform-generated files will be removed from $TF_DIR:"
    echo "  .terraform/           (provider plugins and modules)"
    echo "  .terraform.lock.hcl   (dependency lock file)"
    echo "  terraform.tfstate     (local state)"
    echo "  terraform.tfstate.backup"
    echo "  crash.log             (Terraform panic logs)"
    echo
    read -r -p "Continue? [y/N] " CONFIRM
    if [[ "${CONFIRM,,}" != "y" ]]; then
      echo "Aborted."
      exit 0
    fi
    rm -rf \
      "$TF_DIR/.terraform" \
      "$TF_DIR/.terraform.lock.hcl" \
      "$TF_DIR/terraform.tfstate" \
      "$TF_DIR/terraform.tfstate.backup" \
      "$TF_DIR/crash.log"
    echo "Done. Run './run.sh init' before the next apply."
    ;;
  *)
    echo "Error: unknown command '$COMMAND'"
    echo
    usage
    exit 1
    ;;
esac
