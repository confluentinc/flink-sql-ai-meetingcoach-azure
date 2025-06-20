#!/bin/bash

# ====================================================================
# AUTOMATED CREDENTIAL COLLECTION FOR FLINK ML DEMO
# ====================================================================
# This script automates the collection of required credentials for the
# Flink ML Demo and populates the .env file.
#
# PREREQUISITES:
# 1. You must be logged into the Azure CLI: 'az login'
# 2. You must be logged into the Confluent CLI: 'confluent login'
# 3. You must have the proper permissions in both Azure and Confluent Cloud
# ====================================================================

set -e  # Exit on any error

# Configuration
ENV_FILE=".env"
ENV_TEMPLATE=".env.template"
BACKUP_FILE=".env.backup.$(date +%Y%m%d_%H%M%S)"

# Logging functions
info() { echo "✅ [INFO] $1"; }
warn() { echo "⚠️  [WARN] $1"; }
error() { echo "❌ [ERROR] $1"; }
success() { echo "🎉 [SUCCESS] $1"; }

# Check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "$1 command not found. Please install $1 and try again."
        return 1
    fi
    return 0
}

# Prompt user for yes/no input
prompt_user() {
    local prompt_message="$1"
    local default_choice="$2"
    local choice
    local suffix="[Y/n]"

    if [[ "$default_choice" == "n" ]]; then
        suffix="[y/N]"
    fi

    while true; do
        read -r -p "$prompt_message $suffix: " choice
        choice=${choice:-${default_choice:-y}}
        case "$choice" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer yes (y) or no (n)." ;;
        esac
    done
}

# Update .env file with key-value pair
update_env_file() {
    local key="$1"
    local value="$2"

    if [[ -z "$key" || -z "$value" ]]; then
        warn "Skipping empty key or value: $key=$value"
        return 1
    fi

    # Backup .env file on first change
    if [[ -f "$ENV_FILE" && ! -f "$BACKUP_FILE" ]]; then
        cp "$ENV_FILE" "$BACKUP_FILE"
        info "Backed up existing .env file to $BACKUP_FILE"
    fi

    # Create .env from template if it doesn't exist
    if [[ ! -f "$ENV_FILE" ]]; then
        if [[ -f "$ENV_TEMPLATE" ]]; then
            cp "$ENV_TEMPLATE" "$ENV_FILE"
            info "Created .env file from template"
        else
            error ".env.template not found. Cannot create .env file."
            return 1
        fi
    fi

    # Update or add the key-value pair
    if grep -q "^${key}=" "$ENV_FILE"; then
        # Key exists, replace it
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sed -i '' "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
        else
            # Linux
            sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
        fi
        info "Updated $key in .env file"
    else
        # Key doesn't exist, add it
        echo "${key}=${value}" >> "$ENV_FILE"
        info "Added $key to .env file"
    fi
}

# Validate prerequisites
validate_prerequisites() {
    info "Validating prerequisites..."

    # Check for required commands
    check_command "az" || return 1
    check_command "confluent" || return 1
    check_command "jq" || return 1

    # Check Azure CLI login
    info "Checking Azure CLI login status..."
    if ! az account show &> /dev/null; then
        error "Azure CLI is not logged in. Please run 'az login' first."
        return 1
    fi
    local azure_account=$(az account show --query name -o tsv 2>/dev/null)
    success "Azure CLI logged in to: $azure_account"

    # Check Confluent CLI login
    info "Checking Confluent CLI login status..."
    if ! confluent organization list -o json &> /dev/null; then
        error "Confluent CLI is not logged in. Please run 'confluent login' first."
        return 1
    fi
    success "Confluent CLI is logged in"

    return 0
}

# Collect Azure credentials
collect_azure_credentials() {
    info "Collecting Azure credentials..."

    # Get current Azure account details
    local subscription_id=$(az account show --query id -o tsv 2>/dev/null)
    local tenant_id=$(az account show --query tenantId -o tsv 2>/dev/null)

    if [[ -n "$subscription_id" ]]; then
        update_env_file "AZURE_SUBSCRIPTION_ID" "$subscription_id"
    fi

    if [[ -n "$tenant_id" ]]; then
        update_env_file "AZURE_TENANT_ID" "$tenant_id"
    fi

    # Check if service principal credentials are already set
    local current_client_id=$(grep "^AZURE_CLIENT_ID=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2)
    local current_client_secret=$(grep "^AZURE_CLIENT_SECRET=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2)

    if [[ -n "$current_client_id" && "$current_client_id" != "your-service-principal-client-id" &&
          -n "$current_client_secret" && "$current_client_secret" != "your-service-principal-client-secret" ]]; then
        info "Azure service principal credentials are already configured"
    else
        echo ""
        info "Azure Service Principal Setup Required"
        echo "A service principal is needed for Terraform to manage Azure resources."
        echo ""

        if prompt_user "Would you like to create a new Azure service principal automatically?" "y"; then
            create_azure_service_principal
        else
            warn "Skipping service principal creation."
            warn "You'll need to create one manually and update AZURE_CLIENT_ID and AZURE_CLIENT_SECRET in .env"
            warn "Run: az ad sp create-for-rbac --name 'flink-ml-demo-sp' --role contributor --scopes /subscriptions/$subscription_id"
        fi
    fi

    # Set default region
    update_env_file "AZURE_REGION" "eastus"

    success "Azure credentials collected"
}

# Create Azure Service Principal
create_azure_service_principal() {
    info "Creating Azure service principal for Terraform..."

    local sp_name="flink-ml-demo-sp-$(date +%Y%m%d%H%M%S)"
    local subscription_id=$(az account show --query id -o tsv 2>/dev/null)

    if [[ -z "$subscription_id" ]]; then
        error "Could not get Azure subscription ID"
        return 1
    fi

    info "Creating service principal: $sp_name"

    # Create service principal with contributor role
    local sp_output
    if sp_output=$(az ad sp create-for-rbac \
        --name "$sp_name" \
        --role contributor \
        --scopes "/subscriptions/$subscription_id" \
        --output json 2>/dev/null); then

        local client_id=$(echo "$sp_output" | jq -r '.appId // empty')
        local client_secret=$(echo "$sp_output" | jq -r '.password // empty')
        local sp_tenant_id=$(echo "$sp_output" | jq -r '.tenant // empty')

        if [[ -n "$client_id" && -n "$client_secret" ]]; then
            update_env_file "AZURE_CLIENT_ID" "$client_id"
            update_env_file "AZURE_CLIENT_SECRET" "$client_secret"

            success "Service principal created successfully!"
            info "  App ID (Client ID): $client_id"
            info "  Service Principal Name: $sp_name"

            # Verify tenant ID matches
            if [[ -n "$sp_tenant_id" && "$sp_tenant_id" != "$(az account show --query tenantId -o tsv)" ]]; then
                warn "Service principal tenant ID ($sp_tenant_id) differs from current tenant"
            fi
        else
            error "Failed to extract credentials from service principal creation"
            warn "You may need to create one manually"
            return 1
        fi
    else
        error "Failed to create Azure service principal"
        warn "This might be due to insufficient permissions or the service principal name already exists"
        warn "You can create one manually with: az ad sp create-for-rbac --name '$sp_name' --role contributor --scopes /subscriptions/$subscription_id"
        return 1
    fi
}

# Collect Confluent Cloud credentials
collect_confluent_credentials() {
    info "Collecting Confluent Cloud credentials..."

    # Check if user already has cloud API credentials set
    local current_api_key=$(grep "^CONFLUENT_CLOUD_API_KEY=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2)
    local current_api_secret=$(grep "^CONFLUENT_CLOUD_API_SECRET=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2)

    if [[ -n "$current_api_key" && "$current_api_key" != "your-confluent-cloud-api-key" &&
          -n "$current_api_secret" && "$current_api_secret" != "your-confluent-cloud-api-secret" ]]; then
        info "Confluent Cloud API credentials are already configured"
    else
        echo ""
        info "Confluent Cloud API Key Setup Required"
        echo "Cloud-level API keys with OrganizationAdmin permissions are needed for Terraform."
        echo ""

        if prompt_user "Would you like to create Confluent Cloud API keys automatically?" "y"; then
            create_confluent_api_keys
        else
            warn "Skipping Confluent API key creation."
            warn "You'll need to create them manually at: https://confluent.cloud/settings/api-keys"
            warn "Make sure to assign OrganizationAdmin role for full Terraform functionality"
        fi
    fi

    success "Confluent Cloud credential check completed"
}

# Create Confluent Cloud API Keys
create_confluent_api_keys() {
    info "Creating Confluent Cloud API keys for Terraform..."

    # First, get or create a service account for the API keys
    local sa_name="terraform-flink-ml-demo-$(date +%Y%m%d%H%M%S)"
    local sa_description="Service Account for Flink ML Demo Terraform automation"

    info "Creating service account: $sa_name"

    # Create service account
    local sa_output
    if sa_output=$(confluent iam service-account create "$sa_name" \
        --description "$sa_description" \
        --output json 2>/dev/null); then

        local sa_id=$(echo "$sa_output" | jq -r '.id // empty')

        if [[ -n "$sa_id" ]]; then
            info "Service account created: $sa_id"

            # Grant OrganizationAdmin role to the service account
            info "Granting OrganizationAdmin role to service account..."
            if confluent iam rbac role-binding create \
                --role OrganizationAdmin \
                --principal "User:$sa_id" \
                --output json &>/dev/null; then

                success "OrganizationAdmin role granted to service account"

                # Create cloud-level API key for the service account
                info "Creating cloud-level API key..."
                local api_key_output
                if api_key_output=$(confluent api-key create \
                    --service-account "$sa_id" \
                    --resource cloud \
                    --description "Terraform API Key for Flink ML Demo" \
                    --output json 2>/dev/null); then

                    local api_key=$(echo "$api_key_output" | jq -r '.api_key // empty')
                    local api_secret=$(echo "$api_key_output" | jq -r '.api_secret // empty')

                    if [[ -n "$api_key" && -n "$api_secret" ]]; then
                        update_env_file "CONFLUENT_CLOUD_API_KEY" "$api_key"
                        update_env_file "CONFLUENT_CLOUD_API_SECRET" "$api_secret"

                        success "Confluent Cloud API keys created successfully!"
                        info "  API Key: $api_key"
                        info "  Service Account: $sa_name ($sa_id)"

                        warn "IMPORTANT: API credentials have been saved to $ENV_FILE."
                        warn "This is the last time the API secret will be displayed. It cannot be retrieved from Confluent later."
                    else
                        error "Failed to extract API key credentials from creation output"
                        return 1
                    fi
                else
                    error "Failed to create API key for service account $sa_id"
                    return 1
                fi
            else
                error "Failed to grant OrganizationAdmin role to service account $sa_id"
                warn "You may need to grant this role manually in the Confluent Cloud console"
                return 1
            fi
        else
            error "Failed to extract service account ID from creation output"
            return 1
        fi
    else
        error "Failed to create Confluent service account"
        warn "You may need to create API keys manually at: https://confluent.cloud/settings/api-keys"
        return 1
    fi
}

# Collect MongoDB Atlas information
collect_mongodb_credentials() {
    info "Collecting MongoDB Atlas information..."

    # Check if MongoDB credentials are set
    if grep -q "^MONGODBATLAS_PUBLIC_KEY=your-" "$ENV_FILE" 2>/dev/null; then
        warn "MongoDB Atlas credentials need to be set manually"
        warn "Please create API keys at: MongoDB Atlas > Access Manager > API Keys"
        warn "And update the following in .env:"
        warn "  - MONGODBATLAS_PUBLIC_KEY"
        warn "  - MONGODBATLAS_PRIVATE_KEY"
        warn "  - MONGODBATLAS_ORG_ID"
        warn "  - MONGODBATLAS_PROJECT_ID"
        warn "  - MONGODB_CONNECTION_STRING"
        warn "  - MONGODB_USERNAME"
        warn "  - MONGODB_PASSWORD"
    else
        info "MongoDB Atlas credentials appear to be set"
    fi

    success "MongoDB Atlas credential check completed"
}

# Set deployment configuration
set_deployment_config() {
    info "Setting deployment configuration..."

    # Generate a unique deployment prefix if not set
    local current_prefix=$(grep "^DEPLOYMENT_PREFIX=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2)
    if [[ -z "$current_prefix" || "$current_prefix" == "my-unique-prefix" ]]; then
        local unique_prefix="flink-ml-demo-$(date +%Y%m%d)"
        update_env_file "DEPLOYMENT_PREFIX" "$unique_prefix"
    fi

    success "Deployment configuration set"
}

# Validate .env file completeness
validate_env_file() {
    info "Validating .env file completeness..."

    local required_vars=(
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
        "MONGODB_USERNAME"
        "MONGODB_PASSWORD"
    )

    local missing_vars=()
    local placeholder_vars=()

    # Source the .env file to check variables
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        source "$ENV_FILE" 2>/dev/null || true
        set +a
    fi

    for var in "${required_vars[@]}"; do
        local value="${!var:-}"
        if [[ -z "$value" ]]; then
            missing_vars+=("$var")
        elif [[ "$value" == your-* ]] || [[ "$value" == "change-me-in-production" ]]; then
            placeholder_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -eq 0 && ${#placeholder_vars[@]} -eq 0 ]]; then
        success "All required variables are set with real values!"
        return 0
    else
        warn "Environment file validation found issues:"

        if [[ ${#missing_vars[@]} -gt 0 ]]; then
            error "Missing variables:"
            printf '  - %s\n' "${missing_vars[@]}"
        fi

        if [[ ${#placeholder_vars[@]} -gt 0 ]]; then
            error "Variables still have placeholder values:"
            printf '  - %s\n' "${placeholder_vars[@]}"
        fi

        echo ""
        warn "Please update these variables in $ENV_FILE before proceeding"
        return 1
    fi
}

# Provide next steps
show_next_steps() {
    echo ""
    info "=== NEXT STEPS ==="
    echo ""
    echo "1. 📝 Review and complete the .env file:"
    echo "   - Check that all placeholder values are replaced with real credentials"
    echo "   - Ensure MongoDB Atlas resources are created and credentials are correct"
    echo ""
    echo "2. 🚀 Run Terraform deployment:"
    echo "   cd terraform"
    echo "   source ./load_tf_vars.sh"
    echo "   terraform plan"
    echo "   terraform apply"
    echo ""
    echo "3. 📋 Generate personalized commands:"
    echo "   cd terraform"
    echo "   ./generate_personalized_commands.sh"
    echo ""
    if [[ -f "$BACKUP_FILE" ]]; then
        echo "📁 Your original .env file was backed up to: $BACKUP_FILE"
    fi
}

# Main execution
main() {
    echo ""
    info "Starting automated credential collection for Flink ML Demo..."
    echo ""

    # Validate prerequisites
    if ! validate_prerequisites; then
        error "Prerequisites validation failed. Please fix the issues above and try again."
        exit 1
    fi

    # Collect credentials from various sources
    collect_azure_credentials
    collect_confluent_credentials
    collect_mongodb_credentials
    set_deployment_config

    echo ""
    info "Credential collection completed!"
    echo ""

    # Validate the final .env file
    if validate_env_file; then
        success "Your .env file is ready for Terraform deployment!"
    else
        warn "Your .env file needs manual completion before proceeding"
    fi

    show_next_steps
}

# Handle script interruption
trap 'error "Script interrupted. Check $ENV_FILE for partial updates."; exit 1' INT TERM

# Run main function
main "$@"
