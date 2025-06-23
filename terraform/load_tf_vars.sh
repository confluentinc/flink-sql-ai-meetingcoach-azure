#!/bin/bash

# ====================================================================
# UNIFIED TERRAFORM VARIABLE LOADER
# ====================================================================
# This script loads environment variables from .env or .env-regional files
# and sets appropriate Terraform variables for deployment

set -e  # Exit on any error

# Function to load variables from a specific file
load_env_file() {
    local env_file="$1"
    local description="$2"

    if [ ! -f "$env_file" ]; then
        echo "⚠️  Warning: $env_file file not found"
        return 1
    fi

    echo "📁 Loading from $env_file ($description)..."

    # Extract MongoDB credentials first (to avoid sourcing issues with special chars)
    MONGODB_USERNAME_FROM_ENV=$(grep "^MONGODB_USERNAME=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")
    MONGODB_PASSWORD_FROM_ENV=$(grep "^MONGODB_PASSWORD=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || echo "")

    # Source the .env file (skip MongoDB lines to avoid special character issues)
    set -a  # Automatically export all variables
    source <(grep -v "^MONGODB_USERNAME=" "$env_file" | grep -v "^MONGODB_PASSWORD=" | grep -v '^#' | grep -v '^$')
    set +a  # Stop auto-exporting

    echo "✅ Successfully loaded $description environment variables"
    return 0
}

# Check for environment file preference
ENV_FILE=""
DESCRIPTION=""
ENV_PATH_PREFIX=""

# Determine file path prefix (check if we're in terraform/ directory)
if [[ $(basename "$PWD") == "terraform" ]]; then
    ENV_PATH_PREFIX="../"
else
    ENV_PATH_PREFIX=""
fi

echo "🔄 Loading environment variables for Terraform..."

# Check for command line argument
if [ "$1" = "regional" ] || [ "$1" = "--regional" ]; then
    ENV_FILE="${ENV_PATH_PREFIX}.env-regional"
    DESCRIPTION="regional test"
elif [ "$1" = "main" ] || [ "$1" = "--main" ]; then
    ENV_FILE="${ENV_PATH_PREFIX}.env"
    DESCRIPTION="main"
elif [ -n "$1" ]; then
    echo "❌ Error: Unknown argument '$1'"
    echo "Usage: $0 [regional|main]"
    echo "  regional: Use .env-regional file"
    echo "  main:     Use .env file"
    echo "  (no arg): Auto-detect based on available files"
    exit 1
fi

# Auto-detect if no argument provided
if [ -z "$ENV_FILE" ]; then
    if [ -f "${ENV_PATH_PREFIX}.env-regional" ]; then
        ENV_FILE="${ENV_PATH_PREFIX}.env-regional"
        DESCRIPTION="regional test (auto-detected)"
    elif [ -f "${ENV_PATH_PREFIX}.env" ]; then
        ENV_FILE="${ENV_PATH_PREFIX}.env"
        DESCRIPTION="main (auto-detected)"
    else
        echo "❌ Error: Neither .env nor .env-regional file found"
        echo "Please create one of these files with your credentials"
        echo "Expected locations:"
        echo "  - ${ENV_PATH_PREFIX}.env"
        echo "  - ${ENV_PATH_PREFIX}.env-regional"
        exit 1
    fi
fi

# Load the environment file
if ! load_env_file "$ENV_FILE" "$DESCRIPTION"; then
    echo "❌ Error: Failed to load $ENV_FILE"
    exit 1
fi

# ====================================================================
# Map .env variables to Terraform format
# ====================================================================

echo "🔄 Converting to Terraform variables..."

# Required credentials
export TF_VAR_confluent_cloud_api_key="$CONFLUENT_CLOUD_API_KEY"
export TF_VAR_confluent_cloud_api_secret="$CONFLUENT_CLOUD_API_SECRET"

export TF_VAR_azure_subscription_id="$AZURE_SUBSCRIPTION_ID"
export TF_VAR_azure_tenant_id="$AZURE_TENANT_ID"
export TF_VAR_azure_client_id="$AZURE_CLIENT_ID"
export TF_VAR_azure_client_secret="$AZURE_CLIENT_SECRET"

export TF_VAR_mongodbatlas_public_key="$MONGODBATLAS_PUBLIC_KEY"
export TF_VAR_mongodbatlas_private_key="$MONGODBATLAS_PRIVATE_KEY"
export TF_VAR_mongodbatlas_org_id="$MONGODBATLAS_ORG_ID"
export TF_VAR_mongodbatlas_project_id="$MONGODBATLAS_PROJECT_ID"

# Configuration with defaults
export TF_VAR_deployment_prefix="${DEPLOYMENT_PREFIX:-flink-ml-demo-$(date +%Y%m%d)}"
export TF_VAR_azure_location="${AZURE_REGION:-eastus2}"
export TF_VAR_confluent_region="${AZURE_REGION:-eastus2}"

export TF_VAR_mongodb_username="${MONGODB_USERNAME_FROM_ENV:-demo-user}"
export TF_VAR_mongodb_password="${MONGODB_PASSWORD_FROM_ENV:-change-me-in-production}"
export TF_VAR_mongodb_connection_string="$MONGODB_CONNECTION_STRING"

# MongoDB Atlas resource configuration
export TF_VAR_mongodb_cluster_name="${MONGODB_CLUSTER_NAME:-aimeetingcoach}"
export TF_VAR_mongodb_database_name="${MONGODB_DATABASE_NAME:-knowledge_db}"
export TF_VAR_mongodb_collection_name="${MONGODB_COLLECTION_NAME:-knowledge_embeddings}"
export TF_VAR_mongodb_index_name="${MONGODB_INDEX_NAME:-vector_search_index}"
export TF_VAR_mongodb_embedding_column="${MONGODB_EMBEDDING_COLUMN:-embedding}"

# ====================================================================
# Validation
# ====================================================================

# Check required variables
REQUIRED_VARS=(
    "CONFLUENT_CLOUD_API_KEY"
    "CONFLUENT_CLOUD_API_SECRET"
    "AZURE_SUBSCRIPTION_ID"
    "AZURE_TENANT_ID"
    "AZURE_CLIENT_ID"
    "AZURE_CLIENT_SECRET"
    "MONGODBATLAS_PUBLIC_KEY"
    "MONGODBATLAS_PRIVATE_KEY"
    "MONGODBATLAS_ORG_ID"
    "MONGODBATLAS_PROJECT_ID"
    "MONGODB_CONNECTION_STRING"
)

MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
    eval "value=\$$var"
    if [ -z "$value" ] || [[ "$value" == your-* ]]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -ne 0 ]; then
    echo "❌ Error: Missing required environment variables:"
    printf '   - %s\n' "${MISSING_VARS[@]}"
    echo ""
    echo "📝 Please update your $ENV_FILE file with real credentials"
    exit 1
fi

echo "✅ All required environment variables loaded successfully!"
echo "🚀 Deployment prefix: $TF_VAR_deployment_prefix"
echo "🌍 Azure region: $TF_VAR_azure_location"
echo "📝 Using: $ENV_FILE"
echo ""
echo "🎯 You can now run:"
echo "   terraform plan"
echo "   terraform apply"
echo ""
echo "💡 Tip: Use 'source load_tf_vars.sh' to load variables in your current shell"
