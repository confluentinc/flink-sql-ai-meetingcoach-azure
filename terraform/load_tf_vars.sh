
#!/bin/bash

# ====================================================================
# TERRAFORM VARIABLE LOADER - FOR CLEAN DEPLOYMENTS
# ====================================================================
# This script loads the minimal .env file and sets Terraform variables

set -e  # Exit on any error

ENV_FILE="../.env"

# Check if .env file exists
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Error: $ENV_FILE not found!"
    echo "📝 Please copy .env.template to .env and fill in your credentials"
    echo "   cp ../.env.template ../.env"
    exit 1
fi

echo "🔄 Loading minimal environment variables from $ENV_FILE..."

# Extract MongoDB credentials first (to avoid sourcing issues with special chars)
MONGODB_USERNAME_FROM_ENV=$(grep "^MONGODB_USERNAME=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
MONGODB_PASSWORD_FROM_ENV=$(grep "^MONGODB_PASSWORD=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'")

# Source the .env file (skip MongoDB lines to avoid special character issues)
set -a  # Automatically export all variables
source <(grep -v "^MONGODB_USERNAME=" "$ENV_FILE" | grep -v "^MONGODB_PASSWORD=")
set +a  # Stop auto-exporting

# ====================================================================
# Map .env variables to Terraform format
# ====================================================================

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

# Optional configuration (use defaults if not set)
export TF_VAR_deployment_prefix="${DEPLOYMENT_PREFIX:-flink-ml-demo-$(date +%Y%m%d)}"
export TF_VAR_azure_location="${AZURE_REGION:-eastus}"
export TF_VAR_confluent_region="${AZURE_REGION:-eastus}"

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
    echo "📝 Please update your .env file with real credentials"
    exit 1
fi

echo "✅ All required environment variables loaded successfully!"
echo "🚀 Deployment prefix: $TF_VAR_deployment_prefix"
echo "🌍 Azure region: $TF_VAR_azure_location"
echo ""
echo "🎯 You can now run: terraform plan"
echo "                   terraform apply"
