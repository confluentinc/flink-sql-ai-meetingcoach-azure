#!/bin/bash

# --- Configuration ---
ENV_FILE="script_output.env"
BASE_NAME="meetingcoach"
DEFAULT_CLOUD="azure"
DEFAULT_REGION="eastus"
DEFAULT_FLINK_CFU=20

# --- Initial Checks ---
info() { echo "[INFO] $1"; }
warn() { echo "[WARN] $1"; }
error() { echo "[ERROR] $1"; }

# Check for Bash v4+
if ! declare -A test_array &>/dev/null; then error "Requires Bash v4.0+. Run using 'bash $0'"; exit 1; fi
info "Bash version check passed."


# Variable tracking setup
declare -A required_vars=(
    [confluent_cloud_api_key]=0 [confluent_cloud_api_secret]=0 [confluent_region]=0
    [kafka_api_key]=0 [kafka_api_secret]=0 [kafka_id]=0 [catalog_name]=0
    [database_name]=0 [schema_registry_url]=0 [schema_registry_rest_endpoint]=0
    [schema_registry_id]=0 [schema_registry_api_key]=0 [schema_registry_api_secret]=0
    [kafka_bootstrap_servers]=0 [environment_name]=0 [kafka_cluster_name]=0
    [flink_api_key]=0 [flink_api_secret]=0 [flink_rest_endpoint]=0 [organization_id]=0
    [environment_id]=0 [flink_compute_pool_id]=0 [flink_principal_id]=0 [flink_pool_name]=0
)
declare -a missing_vars=()

# --- Helper Functions --- (Keep existing: save_var, load_env, prompt_yes_no, check_jq, check_cli_login, select_item, select_or_create_sa, create_api_key)
# Functions are unchanged from previous version

save_var() {
    local key="$1" value="$2"
    if [[ -z "$key" ]]; then error "save_var internal error: requires key."; return 1; fi
    if [[ -z "$value" ]] && [[ "$key" != "flink_rest_endpoint" ]]; then
        if [[ "$key" == "kafka_cluster_name" ]] && [[ -n "$kafka_id" ]]; then warn "Kafka cluster name not yet available for $kafka_id. Will try updating later."
        else error "save_var internal error: requires non-empty value for '$key'."; missing_vars+=("$key"); required_vars[$key]=0; return 1; fi
    fi
    touch "$ENV_FILE"; local temp_file; temp_file=$(mktemp)
    if grep -q "^${key}=" "$ENV_FILE"; then grep -v "^${key}=" "$ENV_FILE" > "$temp_file" && mv "$temp_file" "$ENV_FILE"; else rm "$temp_file"; fi
    echo "${key}=${value}" >> "$ENV_FILE"; export "$key"="$value"
    if [[ -n "$value" ]]; then info "Saved: ${key}=${value}";
    elif [[ "$key" == "flink_rest_endpoint" ]]; then info "Saved: ${key}= (Endpoint pending Flink Pool provisioning)";
    elif [[ "$key" == "kafka_cluster_name" ]]; then info "Saved: ${key}= (Name pending Kafka Cluster provisioning)";
    fi
    required_vars[$key]=1
}

load_env() {
    if [[ -f "$ENV_FILE" ]]; then info "Loading existing variables from $ENV_FILE..."
        set -a; source "$ENV_FILE" 2>/dev/null || true; set +a
        for key in "${!required_vars[@]}"; do if [[ -n "${!key}" ]]; then required_vars[$key]=1; info " -> Loaded existing value for $key."; else required_vars[$key]=0; fi; done
    else info "Creating new environment file: $ENV_FILE"; touch "$ENV_FILE"; for key in "${!required_vars[@]}"; do required_vars[$key]=0; done; fi
}

prompt_yes_no() {
    local prompt_message="$1" default_choice="$2" choice suffix="[Y/n]"
    if [[ "$default_choice" == "n" ]]; then suffix="[y/N]"; fi
    while true; do read -r -p "$prompt_message $suffix: " choice; choice=${choice:-${default_choice:-y}}; case "$choice" in [Yy]* ) return 0;; [Nn]* ) return 1;; * ) echo "Please answer yes (y) or no (n).";; esac; done
}

check_jq() {
    info "Checking for 'jq' dependency..."; if command -v jq &> /dev/null; then info "'jq' is installed."; return 0; fi
    error "'jq' command not found."; if prompt_yes_no "Attempt to install 'jq' automatically?" "n"; then
        if command -v apt-get &> /dev/null; then sudo apt-get update && sudo apt-get install -y jq; elif command -v yum &> /dev/null; then sudo yum install -y jq; elif command -v brew &> /dev/null; then brew install jq
        else error "Could not determine package manager. Install 'jq' manually."; return 1; fi
        if command -v jq &> /dev/null; then info "'jq' installed successfully."; return 0; else error "Install failed. Install 'jq' manually."; return 1; fi
    else error "Install 'jq' manually and re-run."; return 1; fi
}

check_cli_login() {
    info "Checking Confluent CLI login status..."; if confluent organization list -o json > /dev/null 2>&1; then info "Confluent CLI appears logged in."; return 0; else
        local error_output; error_output=$(confluent organization list -o json 2>&1 > /dev/null); error "Confluent CLI login check failed."; error "Attempted command output: $error_output"; error "Run 'confluent login'."; return 1; fi
}

select_item() {
    local type="$1" list_cmd="$2" id_field="$3" name_field="$4" id_var="$5" name_var="$6" describe_cmd_template="$7"
    info "Fetching available ${type}s..."; local json_output stderr_output exit_code; stderr_output=$(mktemp)
    json_output=$(eval "$list_cmd" 2> "$stderr_output"); exit_code=$?; local stderr_content; stderr_content=$(<"$stderr_output"); rm "$stderr_output"
    if [[ $exit_code -ne 0 ]]; then error "Failed list ${type}s. Cmd: '$list_cmd'. Code: $exit_code."; error "Stderr: $stderr_content"; return 1; fi
    if ! echo "$json_output" | jq empty 2>/dev/null; then error "Failed parse JSON for ${type}s. Cmd: '$list_cmd'."; error "Output: $json_output"; error "Stderr: $stderr_content"; return 1; fi
    local count; count=$(echo "$json_output" | jq 'if type=="array" then length else 0 end')
    if [[ "$count" -eq 0 ]]; then info "No existing ${type}s found."; eval "$id_var=''"; eval "$name_var=''"; return 2;
    elif [[ "$count" -eq 1 ]]; then info "Found exactly one ${type}. Auto-selecting."; local id name
        id=$(echo "$json_output" | jq -r ".[0].${id_field} // empty"); name=$(echo "$json_output" | jq -r ".[0].${name_field} // empty")
        if [[ -z "$id" ]]; then error "Could not parse ID field '${id_field}' from single ${type}. JSON: $json_output"; return 1; fi
        if [[ -z "$name" || -n "$describe_cmd_template" ]]; then if [[ -n "$describe_cmd_template" ]]; then
                local describe_cmd=${describe_cmd_template/<ID>/$id}; info "Fetching details for ${type} $id..."
                local describe_json; describe_json=$(eval "$describe_cmd" 2>/dev/null)
                if [[ $? -eq 0 ]] && echo "$describe_json" | jq empty 2>/dev/null ; then local described_name; described_name=$(echo "$describe_json" | jq -r ".${name_field} // empty"); if [[ -n "$described_name" ]]; then name=$described_name; fi
                else warn "Could not describe ${type} $id to confirm name."; fi; fi; fi
        name=${name:-$id}; eval "$id_var='$id'"; eval "$name_var='$name'"; info " -> Selected ${type}: $name ($id)"; return 0
    else info "Found multiple ${type}s. Please select one:"; echo "$json_output" | jq -r '.[] | [(."'"$name_field"'" // .id // "Unknown Name"), (."'"$id_field"'")] | "\(.[0]) (\(.[1]))"' | cat -n; local selection index id name
        while true; do read -r -p "Enter number, name, or ID: " selection; if [[ -z "$selection" ]]; then continue; fi
            if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "$count" ]]; then index=$((selection - 1))
                id=$(echo "$json_output" | jq -r ".[${index}].${id_field} // empty"); name=$(echo "$json_output" | jq -r ".[${index}].${name_field} // \"$id\"")
                 if [[ -z "$id" ]]; then warn "Invalid index. Try again."; continue; fi; eval "$id_var='$id'"; eval "$name_var='$name'"; info " -> Selected by number: $name ($id)"; return 0
            else id=$(echo "$json_output" | jq -r ".[] | select(.${id_field} == \"$selection\") | .${id_field}" | head -n 1); if [[ -n "$id" ]]; then
                    name=$(echo "$json_output" | jq -r ".[] | select(.${id_field} == \"$id\") | .${name_field} // \"$id\"" | head -n 1); eval "$id_var='$id'"; eval "$name_var='$name'"; info " -> Selected by ID: $name ($id)"; return 0
                else id=$(echo "$json_output" | jq -r ".[] | select(.${name_field} == \"$selection\") | .${id_field}" | head -n 1); if [[ -n "$id" ]]; then
                        name=$(echo "$json_output" | jq -r ".[] | select(.${id_field} == \"$id\") | .${name_field} // \"$id\"" | head -n 1); eval "$id_var='$id'"; eval "$name_var='$name'"; info " -> Selected by Name: $name ($id)"; return 0
                    else warn "Invalid selection. Use number, ID, or exact name."; fi; fi; fi; done; fi
}

select_or_create_sa() {
    local purpose="$1" id_var="$2" name_var="$3"; local sa_id sa_name selected_sa_id selected_sa_name matched_sa_id matched_sa_name
    local suggested_sa_name="${BASE_NAME}_${purpose// /_}_sa"; local desc="SA for Terraform demo ($purpose)"
    info "Checking Service Accounts for '$purpose' (suggested name: '$suggested_sa_name')..."; local list_output stderr_output list_exit_code; stderr_output=$(mktemp)
    list_output=$(confluent iam service-account list -o json 2> "$stderr_output"); list_exit_code=$?; local list_stderr_content; list_stderr_content=$(<"$stderr_output"); rm "$stderr_output"
    if [[ $list_exit_code -ne 0 ]]; then error "Failed list SAs. Code: $list_exit_code"; error "Stderr: $list_stderr_content"; return 1; fi
    if ! echo "$list_output" | jq empty 2>/dev/null; then error "Failed parse JSON for SAs."; error "Output: $list_output"; error "Stderr: $list_stderr_content"; return 1; fi
    local sa_count; sa_count=$(echo "$list_output" | jq 'if type=="array" then length else 0 end')
    if [[ "$sa_count" -gt 0 ]]; then matched_sa_id=$(echo "$list_output" | jq -r ".[] | select(.display_name == \"$suggested_sa_name\") | .id" | head -n 1); if [[ -n "$matched_sa_id" ]] && [[ "$matched_sa_id" != "null" ]]; then matched_sa_name=$suggested_sa_name; fi; fi

    if [[ -n "$matched_sa_id" ]]; then if prompt_yes_no "Found SA '$matched_sa_name' ($matched_sa_id). Use this one?" "y"; then eval "$id_var='$matched_sa_id'"; eval "$name_var='$matched_sa_name'"; info "Using existing SA: $matched_sa_name ($matched_sa_id)"; return 0
        else if [[ "$sa_count" -gt 1 ]]; then if prompt_yes_no "Select a different existing SA instead?" "n"; then select_item "Service Account" "echo '$list_output'" "id" "display_name" selected_sa_id selected_sa_name; local select_rc=$?; if [[ $select_rc -eq 0 ]]; then eval "$id_var='$selected_sa_id'"; eval "$name_var='$selected_sa_name'"; info "Using selected SA: $selected_sa_name ($selected_sa_id)"; return 0; elif [[ $select_rc -eq 2 ]]; then info "No SA selected."; else error "Failed SA selection."; return 1; fi; else info "Declined selecting different SA."; fi; else info "No other existing SAs."; fi; fi
    elif [[ "$sa_count" -gt 0 ]]; then warn "No SA found matching suggested name '$suggested_sa_name'."
        if prompt_yes_no "Select a different existing SA?" "n"; then select_item "Service Account" "echo '$list_output'" "id" "display_name" selected_sa_id selected_sa_name; local select_rc=$?; if [[ $select_rc -eq 0 ]]; then eval "$id_var='$selected_sa_id'"; eval "$name_var='$selected_sa_name'"; info "Using selected SA: $selected_sa_name ($selected_sa_id)"; return 0; elif [[ $select_rc -eq 2 ]]; then info "No SA selected."; else error "Failed SA selection."; return 1; fi
        else info "Declined selecting existing SA."; fi
    else info "No existing SAs found."; fi

    if prompt_yes_no "Create new SA '$suggested_sa_name' for '$purpose'?" "y"; then info "Creating SA: $suggested_sa_name..."
        local create_output create_stderr_output create_exit_code; create_stderr_output=$(mktemp); create_output=$(confluent iam service-account create "$suggested_sa_name" --description "$desc" -o json 2> "$create_stderr_output"); create_exit_code=$?
        local create_stderr_content; create_stderr_content=$(<"$create_stderr_output"); rm "$create_stderr_output"
        if [[ $create_exit_code -ne 0 ]]; then error "Failed create SA '$suggested_sa_name'. Code: $create_exit_code"; error "Stderr: $create_stderr_content"
             if [[ "$create_stderr_content" == *"already exists"* || "$create_stderr_content" == *"already in use"* ]]; then warn "SA '$suggested_sa_name' already exists. Retrieving ID..."; local find_output find_stderr find_exit; find_stderr=$(mktemp); find_output=$(confluent iam service-account list -o json 2> "$find_stderr") ; find_exit=$? ; rm "$find_stderr"
                 if [[ $find_exit -eq 0 ]] && echo "$find_output" | jq empty 2>/dev/null; then sa_id=$(echo "$find_output" | jq -r ".[] | select(.display_name == \"$suggested_sa_name\") | .id" | head -n 1); if [[ -n "$sa_id" ]] && [[ "$sa_id" != "null" ]]; then info "Found existing SA ID: $suggested_sa_name ($sa_id)"; eval "$id_var='$sa_id'"; eval "$name_var='$suggested_sa_name'"; return 0; else error "Could not find ID for conflicting SA '$suggested_sa_name'."; return 1; fi; else error "Failed re-list SAs after conflict."; return 1; fi; else return 1; fi; fi
        sa_id=$(echo "$create_output" | jq -r '.id // empty'); sa_name=$(echo "$create_output" | jq -r '.display_name // empty')
        if [[ -z "$sa_id" ]]; then error "Failed parse ID from SA creation: $create_output"; return 1; fi
        eval "$id_var='$sa_id'"; eval "$name_var='${sa_name:-$suggested_sa_name}'"; info "Successfully created SA: ${!name_var} ($sa_id)"; return 0
    else error "Cannot proceed without SA for '$purpose'."; return 1; fi
}

create_api_key() {
    local purpose="$1" sa_id="$2" resource_id="$3" key_var="$4" secret_var="$5"; local desc="API Key for Terraform Demo ($purpose)"
    info "Creating API Key for '$purpose' (Resource: $resource_id, SA: $sa_id)..."; local output stderr_output exit_code; stderr_output=$(mktemp)
    output=$(confluent api-key create --service-account "$sa_id" --resource "$resource_id" --description "$desc" -o json 2> "$stderr_output"); exit_code=$?
    local stderr_content; stderr_content=$(<"$stderr_output"); rm "$stderr_output"
    if [[ $exit_code -ne 0 ]]; then error "Failed create API Key for '$purpose'. Code: $exit_code."; error "Cmd: confluent api-key create --service-account \"$sa_id\" --resource \"$resource_id\" ..."; error "Stderr: $stderr_content"; return 1; fi
    local api_key api_secret; api_key=$(echo "$output" | jq -r '.api_key // empty'); api_secret=$(echo "$output" | jq -r '.api_secret // empty')
    if [[ -z "$api_key" ]] || [[ -z "$api_secret" ]]; then error "Failed parse API Key/Secret from creation."; error "Output: $output"; error "Stderr: $stderr_content"; return 1; fi
    if ! save_var "$key_var" "$api_key"; then return 1; fi; if ! save_var "$secret_var" "$api_secret"; then return 1; fi
    info "Successfully created and saved API Key for '$purpose'."; return 0
}


# --- Main Script Logic ---

info "Starting Confluent Demo Credentials Script..."
if ! check_jq; then exit 1; fi; if ! check_cli_login; then exit 1; fi; load_env

# --- Variable Acquisition ---

# Get Organization ID
if [[ ${required_vars[organization_id]} -eq 0 ]] || [[ -z "${organization_id}" ]]; then info "Getting Organization ID..."
    org_output=$(confluent organization list -o json 2> >(tee /dev/stderr >&2)); exit_code=$?
    if [[ $exit_code -ne 0 ]]; then error "Failed list orgs."; missing_vars+=("organization_id"); elif ! echo "$org_output" | jq empty 2>/dev/null; then error "Failed parse JSON for orgs: $org_output"; missing_vars+=("organization_id"); else
        org_id=$(echo "$org_output" | jq -r '.[0].id // empty'); if [[ -n "$org_id" ]]; then save_var "organization_id" "$org_id"; else error "Could not parse Org ID: $org_output"; missing_vars+=("organization_id"); fi; fi
else info "Using existing Org ID: $organization_id"; export organization_id; fi

# Get Cloud Provider and Region
if [[ ${required_vars[confluent_region]} -eq 0 ]] || [[ -z "${confluent_region}" ]]; then info "Select Cloud/Region (Tested: $DEFAULT_CLOUD/$DEFAULT_REGION)..."
    read -p "Cloud Provider [$DEFAULT_CLOUD]: " selected_cloud; selected_cloud=${selected_cloud:-$DEFAULT_CLOUD}
    if [[ "$selected_cloud" != "azure" ]] && [[ "$selected_cloud" != "gcp" ]] && [[ "$selected_cloud" != "aws" ]]; then warn "Unsupported cloud '$selected_cloud'. Defaulting."; selected_cloud=$DEFAULT_CLOUD; fi
    read -p "Region [$DEFAULT_REGION]: " selected_region; selected_region=${selected_region:-$DEFAULT_REGION}
    if [[ "$selected_cloud" != "$DEFAULT_CLOUD" ]] || [[ "$selected_region" != "$DEFAULT_REGION" ]]; then warn "Selected $selected_cloud/$selected_region differs from tested default."; fi
    save_var "confluent_cloud" "$selected_cloud"; save_var "confluent_region" "$selected_region"
else info "Using existing Cloud/Region: $confluent_cloud/$confluent_region"; export confluent_cloud confluent_region; fi

# Get Environment ID and Name
BLOCKER_HIT=0
if [[ ${required_vars[environment_id]} -eq 0 ]] || [[ -z "${environment_id}" ]]; then info "Selecting/Creating Environment..."
    selected_env_id="" selected_env_name=""; suggested_env_name="${BASE_NAME}_env"; describe_template="confluent environment describe <ID> -o json"
    select_item "Environment" "confluent environment list -o json" "id" "display_name" selected_env_id selected_env_name "$describe_template"; select_rc=$?
    if [[ $select_rc -eq 1 ]]; then error "Cannot proceed without Environment."; missing_vars+=("environment_id" "environment_name"); BLOCKER_HIT=1
    elif [[ $select_rc -eq 2 ]]; then if prompt_yes_no "No envs found. Create '$suggested_env_name'?" "y"; then info "Creating Env: $suggested_env_name..."
             output=$(confluent environment create "$suggested_env_name" --provider "$confluent_cloud" --region "$confluent_region" -o json 2> >(tee /dev/stderr >&2)); exit_code=$?
             if [[ $exit_code -ne 0 ]]; then error "Failed create env '$suggested_env_name'."; missing_vars+=("environment_id" "environment_name"); BLOCKER_HIT=1; else
                 selected_env_id=$(echo "$output" | jq -r '.id // empty'); selected_env_name=$(echo "$output" | jq -r '.display_name // empty')
                 if [[ -z "$selected_env_id" ]]; then error "Failed parse ID from env create: $output"; missing_vars+=("environment_id" "environment_name"); BLOCKER_HIT=1; else
                     info "Created Env: ${selected_env_name:-$selected_env_id} ($selected_env_id)"; save_var "environment_id" "$selected_env_id"; save_var "environment_name" "${selected_env_name:-$selected_env_id}"; fi; fi
        else error "Cannot proceed without Env."; missing_vars+=("environment_id" "environment_name"); BLOCKER_HIT=1; fi
    elif [[ $select_rc -eq 0 ]]; then save_var "environment_id" "$selected_env_id"; save_var "environment_name" "$selected_env_name"; fi
else info "Using existing Environment: $environment_name ($environment_id)"; export environment_id environment_name; fi

# --- Dependent variables ---
if [[ "$BLOCKER_HIT" == "1" ]]; then warn "Skipping dependent resources due to env failure."
else
    # Ensure correct environment context is set
    if [[ -n "$environment_id" ]]; then info "Ensuring CLI context is set to environment '$environment_name' ($environment_id)..."
        if ! confluent environment use "$environment_id"; then error "Failed switch CLI context to $environment_id."; fi
    else error "Environment ID missing."; fi

    #     # --- Check/Update Stream Governance Package ---
    info "Checking environment Stream Governance package..."

    # Use environment list command to get governance package info
    env_list_details=$(confluent environment list -o json 2>/dev/null)
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        # Get the stream_governance_package directly using the correct key
        gov_package=$(echo "$env_list_details" | jq -r --arg EID "$environment_id" '.[] | select(.id == $EID) | .stream_governance_package // empty' | tr '[:upper:]' '[:lower:]')

        # If not found in list, try environment describe command
        if [[ -z "$gov_package" ]]; then
            info "Governance package not found in environment list, trying describe command..."
            env_describe_details=$(confluent environment describe "$environment_id" -o json 2>/dev/null)
            describe_exit_code=$?

            if [[ $describe_exit_code -eq 0 ]]; then
                gov_package=$(echo "$env_describe_details" | jq -r '.stream_governance_package // empty' | tr '[:upper:]' '[:lower:]')
            else
                warn "Failed to get environment details using describe command. Exit code: $describe_exit_code"
            fi
        fi

        info "DEBUG: Found governance package: '$gov_package'"

        if [[ "$gov_package" == "essentials" || "$gov_package" == "advanced" ]]; then
             info "Stream Governance package correctly set to '$gov_package'."
        else
             # Package is empty, null, or something else
             warn "Env '$environment_name' governance package is '$gov_package' (or empty/null)."
             if prompt_yes_no "Upgrade environment to 'ESSENTIALS' Stream Governance (needed for Schema Registry)?" "y"; then
                 info "Attempting to update environment '$environment_id' to ESSENTIALS..."
                 update_stderr=$(mktemp)
                 # The update command remains the same
                 if confluent environment update "$environment_id" --governance-package essentials 2> "$update_stderr"; then
                     info "Environment update to ESSENTIALS successful. Changes may take up to a minute to apply."
                     info "Pausing for 20 seconds..." # Keep sleep
                     sleep 20
                 else
                     error "Failed to update environment '$environment_id' to ESSENTIALS."
                     error "Stderr: $(<"$update_stderr")"
                     warn "Proceeding, but Schema Registry may not function as expected."
                 fi
                 rm "$update_stderr"
             else
                 warn "Skipping environment upgrade. Schema Registry functionality may be limited."
             fi
        fi
    else
        warn "Could not list environments to check governance package. Exit code: $exit_code"
    fi

    # --- SINGLE Service Account & API Key Setup (OrgAdmin Approach) ---
    org_admin_sa_id=""
    org_admin_sa_name=""
    temp_cloud_api_key=""
    temp_cloud_api_secret=""

    if [[ ${required_vars[confluent_cloud_api_key]} -eq 1 ]] && [[ -n "$confluent_cloud_api_key" ]]; then
        info "Using existing Cloud API Key. Assuming its SA has OrgAdmin role."
        warn "Attempting find Service Account for existing Cloud API Key ($confluent_cloud_api_key)..."
        api_key_list_json=$(confluent api-key list -o json); if [[ $? -ne 0 ]]; then warn "Failed list API keys."; missing_vars+=("flink_principal_id"); else
            owner_info=$(echo "$api_key_list_json" | jq -r --arg KEY "$confluent_cloud_api_key" '.[] | select(.key == $KEY) | .owner // empty')
            if [[ -n "$owner_info" ]]; then # Check if owner_info is JSON object like {"id": "sa-..."}
                 if echo "$owner_info" | jq -e 'type=="object" and .id' > /dev/null; then org_admin_sa_id=$(echo "$owner_info" | jq -r '.id')
                 # Check if owner_info is string like "User:sa-..."
                 elif echo "$owner_info" | jq -e 'type=="string" and test("^User:sa-")' > /dev/null; then org_admin_sa_id=$(echo "$owner_info" | jq -r 'sub("User:"; "")')
                 fi; fi
            if [[ -n "$org_admin_sa_id" ]]; then info "Found owner SA ID: $org_admin_sa_id"; org_admin_sa_name=$(confluent iam service-account list -o json | jq -r --arg ID "$org_admin_sa_id" '.[] | select(.id == $ID) | .display_name // empty' | head -n 1); org_admin_sa_name=${org_admin_sa_name:-$org_admin_sa_id}
            else warn "Could not determine SA ID from owner info: $owner_info"; missing_vars+=("flink_principal_id"); fi; fi
        temp_cloud_api_key=$confluent_cloud_api_key; temp_cloud_api_secret=$confluent_cloud_api_secret
    else
        info "Creating/Selecting single Service Account with OrgAdmin role..."; warn "!!! SECURITY WARNING: Using OrganizationAdmin for demo purposes only !!!"
        if select_or_create_sa "Org Admin Demo" org_admin_sa_id org_admin_sa_name; then info "Attempting grant OrganizationAdmin role to SA '$org_admin_sa_name' ($org_admin_sa_id)..."
            if [[ -z "$organization_id" ]]; then error "Org ID missing."; missing_vars+=("confluent_cloud_api_key" "confluent_cloud_api_secret")
            else rbac_stderr=$(mktemp)
                 if confluent iam rbac role-binding create --role OrganizationAdmin --principal "User:$org_admin_sa_id" 2> "$rbac_stderr"; then info "Granted OrganizationAdmin role to $org_admin_sa_id."
                 else rbac_content=$(<"$rbac_stderr"); if [[ "$rbac_content" == *"Role binding already exists"* ]]; then info "OrganizationAdmin role binding already exists for $org_admin_sa_id."
                      else error "Failed grant OrganizationAdmin role."; error "Stderr: $rbac_content"; warn "Proceeding, but key might lack permissions."; fi; fi; rm "$rbac_stderr"
                 if create_api_key "Org Admin Cloud Access" "$org_admin_sa_id" "cloud" "confluent_cloud_api_key" "confluent_cloud_api_secret"; then
                     temp_cloud_api_key=$confluent_cloud_api_key; temp_cloud_api_secret=$confluent_cloud_api_secret
                 else error "Failed create Cloud API Key."; fi
            fi
        else error "Failed select/create OrgAdmin SA."; missing_vars+=("confluent_cloud_api_key" "confluent_cloud_api_secret" "kafka_api_key" "kafka_api_secret" "schema_registry_api_key" "schema_registry_api_secret" "flink_api_key" "flink_api_secret" "flink_principal_id"); fi
    fi

    # Reuse Cloud Keys for Other Services
    if [[ -n "$temp_cloud_api_key" ]] && [[ -n "$temp_cloud_api_secret" ]]; then info "Reusing Cloud API Key for other services..."
        save_var "kafka_api_key" "$temp_cloud_api_key"; save_var "kafka_api_secret" "$temp_cloud_api_secret"
        save_var "schema_registry_api_key" "$temp_cloud_api_key"; save_var "schema_registry_api_secret" "$temp_cloud_api_secret"
        save_var "flink_api_key" "$temp_cloud_api_key"; save_var "flink_api_secret" "$temp_cloud_api_secret"
    elif [[ ${required_vars[confluent_cloud_api_key]} -eq 1 ]]; then warn "Could not reuse existing Cloud API Key."; missing_vars+=("kafka_api_key" "kafka_api_secret" "schema_registry_api_key" "schema_registry_api_secret" "flink_api_key" "flink_api_secret")
    else warn "Cloud API key failed."; missing_vars+=("kafka_api_key" "kafka_api_secret" "schema_registry_api_key" "schema_registry_api_secret" "flink_api_key" "flink_api_secret"); fi

    # Flink Principal ID
     if [[ ${required_vars[flink_principal_id]} -eq 0 ]] || [[ -z "${flink_principal_id}" ]]; then info "Setting Flink Principal ID..."
        if [[ -n "$org_admin_sa_id" ]]; then save_var "flink_principal_id" "$org_admin_sa_id"; info "Using OrgAdmin SA ($org_admin_sa_id) as Flink Principal ID."
        else error "Could not determine OrgAdmin SA ID. Cannot set Flink Principal."; missing_vars+=("flink_principal_id"); fi
     else info "Using existing Flink Principal ID: $flink_principal_id"; export flink_principal_id; fi

    # Kafka Cluster
    KAFKA_BLOCKER=0
    if [[ ${required_vars[kafka_id]} -eq 0 ]] || [[ -z "${kafka_id}" ]]; then info "Selecting/Creating Kafka Cluster in Env '$environment_id'..."
        selected_kafka_id="" selected_kafka_name="" selected_kafka_bootstrap=""; suggested_kafka_name="${BASE_NAME}_cluster"; describe_template="confluent kafka cluster describe <ID> -o json"
        select_item "Kafka Cluster" "confluent kafka cluster list -o json" "id" "display_name" selected_kafka_id selected_kafka_name "$describe_template"; select_rc=$?
        if [[ $select_rc -eq 1 ]]; then error "Failed list Kafka Clusters."; missing_vars+=("kafka_id" "kafka_cluster_name" "kafka_bootstrap_servers"); KAFKA_BLOCKER=1
        elif [[ $select_rc -eq 2 ]]; then if prompt_yes_no "No Kafka clusters found. Create BASIC '$suggested_kafka_name'?" "y"; then info "Creating Kafka Cluster: $suggested_kafka_name..."
                 save_var "kafka_cluster_name" "$suggested_kafka_name"
                 output=$(confluent kafka cluster create "$suggested_kafka_name" --type basic --cloud "$confluent_cloud" --region "$confluent_region" -o json 2> >(tee /dev/stderr >&2)); exit_code=$?
                 if [[ $exit_code -ne 0 ]]; then error "Failed initiate Kafka create '$suggested_kafka_name'."; missing_vars+=("kafka_id" "kafka_bootstrap_servers"); KAFKA_BLOCKER=1; else
                     selected_kafka_id=$(echo "$output" | jq -r '.id // empty'); if [[ -z "$selected_kafka_id" ]]; then error "Failed parse ID from Kafka create: $output"; missing_vars+=("kafka_id" "kafka_bootstrap_servers"); KAFKA_BLOCKER=1; else
                        info "Kafka create initiated: $selected_kafka_id. Fetching details..."; sleep 5
                        describe_output=$(confluent kafka cluster describe "$selected_kafka_id" -o json 2> >(tee /dev/stderr >&2)); described_kafka_name=$(echo "$describe_output" | jq -r '.display_name // empty'); selected_kafka_bootstrap=$(echo "$describe_output" | jq -r '.endpoint // empty' | sed 's|SASL_SSL://||')
                        if [[ -z "$selected_kafka_bootstrap" ]]; then warn "Failed parse Bootstrap URL from Kafka describe: $describe_output"; fi
                        info "Created Kafka Cluster: ${described_kafka_name:-$suggested_kafka_name} ($selected_kafka_id)"; warn "Kafka Cluster provisioning takes time. Ensure 'UP'."
                        save_var "kafka_id" "$selected_kafka_id"; if [[ -n "$described_kafka_name" ]]; then save_var "kafka_cluster_name" "$described_kafka_name"; fi
                        if [[ -n "$selected_kafka_bootstrap" ]]; then save_var "kafka_bootstrap_servers" "SASL_SSL://$selected_kafka_bootstrap"; else missing_vars+=("kafka_bootstrap_servers"); fi
                     fi; fi
            else error "Cannot proceed without Kafka Cluster."; missing_vars+=("kafka_id" "kafka_cluster_name" "kafka_bootstrap_servers"); KAFKA_BLOCKER=1; fi
        elif [[ $select_rc -eq 0 ]]; then info "Fetching details for selected Kafka cluster $selected_kafka_name ($selected_kafka_id)..."
            output=$(confluent kafka cluster describe "$selected_kafka_id" -o json 2> >(tee /dev/stderr >&2)); exit_code=$?
            if [[ $exit_code -ne 0 ]]; then error "Failed describe Kafka '$selected_kafka_id'."; missing_vars+=("kafka_id" "kafka_cluster_name" "kafka_bootstrap_servers"); KAFKA_BLOCKER=1; else
                selected_kafka_bootstrap=$(echo "$output" | jq -r '.endpoint // empty' | sed 's|SASL_SSL://||')

                # Try multiple keys to find display name in different response formats
                selected_kafka_name=$(echo "$output" | jq -r '.name // .display_name // empty')

                # If still no name, try to extract from other fields
                if [[ -z "$selected_kafka_name" ]]; then
                    # Try to get from spec section
                    selected_kafka_name=$(echo "$output" | jq -r '.spec.display_name // .spec.name // empty')

                    # If still not found, try to extract from metadata section
                    if [[ -z "$selected_kafka_name" ]]; then
                        selected_kafka_name=$(echo "$output" | jq -r '.metadata.name // empty')
                    fi

                    # If still not found, use a composed name (best effort)
                    if [[ -z "$selected_kafka_name" ]]; then
                        selected_kafka_name="kafka-${selected_kafka_id#lkc-}"
                        warn "Could not find cluster name in API response, generated: $selected_kafka_name"
                    fi
                fi

                status=$(echo "$output" | jq -r '.status // "UNKNOWN"')
                if [[ -z "$selected_kafka_bootstrap" ]]; then error "Failed parse Bootstrap from Kafka describe: $output"; missing_vars+=("kafka_bootstrap_servers"); KAFKA_BLOCKER=1; else
                    save_var "kafka_id" "$selected_kafka_id"
                    save_var "kafka_cluster_name" "$selected_kafka_name"
                    save_var "kafka_bootstrap_servers" "SASL_SSL://$selected_kafka_bootstrap"
                    info " -> Kafka Status: $status"; [[ "$status" != "UP" ]] && warn "Cluster status not 'UP'."; fi; fi; fi
    else
        info "Using existing Kafka Cluster: $kafka_cluster_name ($kafka_id)"

        # If we have an ID but no name, try to fetch the name
        if [[ -n "$kafka_id" ]] && [[ -z "$kafka_cluster_name" || "$kafka_cluster_name" == "$kafka_id" ]]; then
            info "Kafka cluster name is missing or same as ID. Trying to fetch actual name..."
            output=$(confluent kafka cluster describe "$kafka_id" -o json 2>/dev/null)
            if [[ $? -eq 0 ]] && echo "$output" | jq empty 2>/dev/null; then
                # Try multiple fields/paths to find the name
                kafka_name=$(echo "$output" | jq -r '.name // .display_name // .spec.display_name // .spec.name // .metadata.name // empty')

                if [[ -n "$kafka_name" ]]; then
                    info "Found Kafka cluster name: $kafka_name"
                    save_var "kafka_cluster_name" "$kafka_name"
                else
                    # Generate a name if none was found
                    generated_name="kafka-${kafka_id#lkc-}"
                    warn "Could not find name in API response, using generated name: $generated_name"
                    save_var "kafka_cluster_name" "$generated_name"
                fi
            else
                warn "Failed to get Kafka cluster details. Using ID as name."
                save_var "kafka_cluster_name" "$kafka_id"
            fi
        fi

        export kafka_id kafka_cluster_name kafka_bootstrap_servers
    fi

    # Schema Registry Check
    if [[ "$KAFKA_BLOCKER" == "1" ]]; then warn "Skipping SR check due to Kafka failure."
    else SR_BLOCKER=0
        if [[ ${required_vars[schema_registry_id]} -eq 0 ]] || [[ -z "${schema_registry_id}" ]]; then info "Checking Schema Registry status..."
            # First attempt - use direct schema-registry cluster describe command
            output=$(confluent schema-registry cluster describe -o json 2> /dev/null); exit_code=$?
            sr_id="" sr_url=""

            if [[ $exit_code -eq 0 ]] && echo "$output" | jq empty 2>/dev/null; then
                info "Successfully retrieved schema registry details"
                sr_id=$(echo "$output" | jq -r '.cluster_id // empty')
                sr_url=$(echo "$output" | jq -r '.endpoint_url // empty')
            else
                info "First attempt failed, trying alternative approach via cluster endpoints..."
                # Second attempt - get from environment describe
                env_output=$(confluent environment describe "$environment_id" -o json 2>/dev/null)

                if [[ $? -eq 0 ]] && echo "$env_output" | jq empty 2>/dev/null; then
                    # Try to find schema registry endpoint in the environment output
                    # Check different possible paths where it might be stored
                    sr_url=$(echo "$env_output" | jq -r '.schema_registry_url // .schema_registry.endpoint_url // .schema_registry.endpoint // empty')

                    # If we found the URL but not the ID, extract ID from URL or environment
                    if [[ -n "$sr_url" ]]; then
                        info "Found schema registry URL: $sr_url"
                        # Extract ID from URL or use a combination of env ID and region
                        if [[ "$sr_url" =~ /([^/]+)\.([^/]+)\.cloud ]]; then
                            sr_id="${BASH_REMATCH[1]}"
                            info "Extracted schema registry ID from URL: $sr_id"
                        elif [[ -n "$environment_id" ]]; then
                            sr_id="lsrc-${environment_id:0:6}"
                            info "Generated schema registry ID from environment: $sr_id"
                        fi
                    else
                        warn "Could not find schema registry URL in environment details"
                    fi
                fi

                # Third attempt - try to use Kafka cluster to get schema registry info
                if [[ -z "$sr_url" ]] && [[ -n "$kafka_id" ]]; then
                    info "Trying to get schema registry from Kafka cluster details..."
                    kafka_output=$(confluent kafka cluster describe "$kafka_id" -o json 2>/dev/null)

                    if [[ $? -eq 0 ]] && echo "$kafka_output" | jq empty 2>/dev/null; then
                        sr_url=$(echo "$kafka_output" | jq -r '.schema_registry_url // .schema_registry.endpoint_url // .schema_registry.endpoint // empty')

                        if [[ -n "$sr_url" ]]; then
                            info "Found schema registry URL from Kafka cluster: $sr_url"
                            # Same ID extraction logic as above
                            if [[ "$sr_url" =~ /([^/]+)\.([^/]+)\.cloud ]]; then
                                sr_id="${BASH_REMATCH[1]}"
                                info "Extracted schema registry ID from URL: $sr_id"
                            elif [[ -n "$environment_id" ]]; then
                                sr_id="lsrc-${environment_id:0:6}"
                                info "Generated schema registry ID from environment: $sr_id"
                            fi
                        fi
                    fi
                fi
            fi

            # Now process the results
            if [[ -n "$sr_id" ]] && [[ -n "$sr_url" ]]; then
                info "Schema Registry is enabled: ID $sr_id, URL $sr_url"
                save_var "schema_registry_id" "$sr_id"
                save_var "schema_registry_url" "$sr_url"
                save_var "schema_registry_rest_endpoint" "$sr_url"
            else
                # Final attempt - if we have API key and secret but still no URL
                if [[ -n "$schema_registry_api_key" ]] && [[ -n "$schema_registry_api_secret" ]]; then
                    info "Using API key and secret to derive schema registry URL..."
                    # Determine cloud provider and region for URL pattern
                    provider=${confluent_cloud:-"azure"}
                    region=${confluent_region:-"eastus"}

                    # Generate URL based on common patterns
                    if [[ "$provider" == "azure" ]]; then
                        generated_url="https://psrc-xxx.${region}.${provider}.confluent.cloud"
                        sr_id="lsrc-${environment_id:0:6}"
                    elif [[ "$provider" == "gcp" ]]; then
                        generated_url="https://psrc-xxx.${region}.gcp.confluent.cloud"
                        sr_id="lsrc-${environment_id:0:6}"
                    elif [[ "$provider" == "aws" ]]; then
                        generated_url="https://psrc-xxx.${region}.aws.confluent.cloud"
                        sr_id="lsrc-${environment_id:0:6}"
                    else
                        generated_url="https://psrc-xxx.confluent.cloud"
                        sr_id="lsrc-${environment_id:0:6}"
                    fi

                    info "Generated schema registry URL pattern: $generated_url"
                    info "NOTE: This is a placeholder. You'll need to replace 'psrc-xxx' with actual value"
                    info "from the Confluent Cloud console or API."

                    warn "Saving incomplete schema registry details."
                    warn "You must manually update the schema_registry_url/rest_endpoint in $ENV_FILE!"

                    save_var "schema_registry_id" "$sr_id"
                    save_var "schema_registry_url" "$generated_url"
                    save_var "schema_registry_rest_endpoint" "$generated_url"
                else
                    warn "Could not determine schema registry details through any available method."
                    missing_vars+=("schema_registry_id" "schema_registry_url" "schema_registry_rest_endpoint")
                    SR_BLOCKER=1
                fi
            fi
        else info "Using existing SR details: ID $schema_registry_id"; export schema_registry_id schema_registry_url schema_registry_rest_endpoint; fi
    fi # End Kafka Blocker check for SR

    # Flink Compute Pool
    FLINK_BLOCKER=0
    if [[ ${required_vars[flink_compute_pool_id]} -eq 0 ]] || [[ -z "${flink_compute_pool_id}" ]]; then info "Selecting/Creating Flink Compute Pool..."
        selected_flink_pool_id="" selected_flink_pool_name="" selected_flink_rest_endpoint=""; suggested_flink_pool_name="${BASE_NAME}_flink_pool"; describe_template="confluent flink compute-pool describe <ID> -o json"
        select_item "Flink Compute Pool" "confluent flink compute-pool list -o json" "id" "display_name" selected_flink_pool_id selected_flink_pool_name "$describe_template"; select_rc=$?
        if [[ $select_rc -eq 1 ]]; then error "Failed list Flink Pools."; missing_vars+=("flink_compute_pool_id" "flink_rest_endpoint" "flink_pool_name"); FLINK_BLOCKER=1
        elif [[ $select_rc -eq 2 ]]; then if prompt_yes_no "No Flink Pools found. Create '$suggested_flink_pool_name' (Max CFU: $DEFAULT_FLINK_CFU)?" "y"; then info "Creating Flink Pool: $suggested_flink_pool_name..."
                 output=$(confluent flink compute-pool create "$suggested_flink_pool_name" --max-cfu "$DEFAULT_FLINK_CFU" --cloud "$confluent_cloud" --region "$confluent_region" -o json 2> >(tee /dev/stderr >&2)); exit_code=$?
                 if [[ $exit_code -ne 0 ]]; then error "Failed create Flink Pool '$suggested_flink_pool_name'."; missing_vars+=("flink_compute_pool_id" "flink_rest_endpoint" "flink_pool_name"); FLINK_BLOCKER=1; else
                     selected_flink_pool_id=$(echo "$output" | jq -r '.id // empty'); if [[ -z "$selected_flink_pool_id" ]]; then error "Failed parse ID from Flink create: $output"; missing_vars+=("flink_compute_pool_id" "flink_rest_endpoint" "flink_pool_name"); FLINK_BLOCKER=1; else
                        info "Flink Pool create initiated: $selected_flink_pool_id. Fetching details..."; sleep 5
                        describe_output=$(confluent flink compute-pool describe "$selected_flink_pool_id" -o json 2> >(tee /dev/stderr >&2));
                        selected_flink_pool_name=$(echo "$describe_output" | jq -r '.display_name // empty')

                        # Try multiple ways to get the REST endpoint
                        selected_flink_rest_endpoint=$(echo "$describe_output" | jq -r '.http_endpoint // empty')
                        if [[ -z "$selected_flink_rest_endpoint" ]]; then
                            selected_flink_rest_endpoint=$(echo "$describe_output" | jq -r '.rest_endpoint // .endpoint // empty')

                            # Try different JSON paths
                            if [[ -z "$selected_flink_rest_endpoint" ]]; then
                                selected_flink_rest_endpoint=$(echo "$describe_output" | jq -r '.spec.http_endpoint // .spec.endpoint // empty')
                            fi
                        fi

                        status=$(echo "$describe_output" | jq -r '.status // "UNKNOWN"')
                        info "Created Flink Pool: ${selected_flink_pool_name:-$selected_flink_pool_id} ($selected_flink_pool_id), Status: $status"
                        save_var "flink_compute_pool_id" "$selected_flink_pool_id"
                        save_var "flink_pool_name" "${selected_flink_pool_name:-$selected_flink_pool_id}"

                        if [[ -n "$selected_flink_rest_endpoint" ]]; then
                            save_var "flink_rest_endpoint" "$selected_flink_rest_endpoint"
                        else
                            warn "Flink REST endpoint not yet available (Status: $status). Generating placeholder..."
                            # Generate a placeholder URL based on cloud provider and region
                            provider=${confluent_cloud:-"azure"}
                            region=${confluent_region:-"eastus"}
                            generated_url="https://flink.${region}.${provider}.confluent.cloud"
                            info "Generated placeholder Flink REST endpoint: $generated_url"
                            info "NOTE: You may need to update this later with the correct value."
                            save_var "flink_rest_endpoint" "$generated_url"
                        fi
                     fi; fi
            else error "Cannot proceed without Flink Pool."; missing_vars+=("flink_compute_pool_id" "flink_rest_endpoint" "flink_pool_name"); FLINK_BLOCKER=1; fi
        elif [[ $select_rc -eq 0 ]]; then info "Fetching details for selected Flink Pool $selected_flink_pool_name ($selected_flink_pool_id)..."
             output=$(confluent flink compute-pool describe "$selected_flink_pool_id" -o json 2> >(tee /dev/stderr >&2)); exit_code=$?
             if [[ $exit_code -ne 0 ]]; then error "Failed describe Flink Pool '$selected_flink_pool_id'."; missing_vars+=("flink_compute_pool_id" "flink_rest_endpoint" "flink_pool_name"); FLINK_BLOCKER=1; else
                 # Try multiple ways to get the REST endpoint
                 selected_flink_rest_endpoint=$(echo "$output" | jq -r '.http_endpoint // empty')
                 if [[ -z "$selected_flink_rest_endpoint" ]]; then
                     selected_flink_rest_endpoint=$(echo "$output" | jq -r '.rest_endpoint // .endpoint // empty')

                     # Try different JSON paths
                     if [[ -z "$selected_flink_rest_endpoint" ]]; then
                         selected_flink_rest_endpoint=$(echo "$output" | jq -r '.spec.http_endpoint // .spec.endpoint // empty')
                     fi
                 fi

                 status=$(echo "$output" | jq -r '.status // "UNKNOWN"')
                 save_var "flink_compute_pool_id" "$selected_flink_pool_id"
                 save_var "flink_pool_name" "$selected_flink_pool_name"

                 if [[ -n "$selected_flink_rest_endpoint" ]]; then
                     save_var "flink_rest_endpoint" "$selected_flink_rest_endpoint"
                     info " -> Flink Pool Status: $status"
                 else
                     warn "Flink REST endpoint not available (Status: $status). Generating placeholder..."
                     # Generate a placeholder URL based on cloud provider and region
                     provider=${confluent_cloud:-"azure"}
                     region=${confluent_region:-"eastus"}
                     generated_url="https://flink.${region}.${provider}.confluent.cloud"
                     info "Generated placeholder Flink REST endpoint: $generated_url"
                     info "NOTE: You may need to update this later with the correct value from the Confluent Cloud console."
                     save_var "flink_rest_endpoint" "$generated_url"
                 fi
             fi;
        fi
    else
        info "Using existing Flink Pool: $flink_pool_name ($flink_compute_pool_id)"

        # If we have an ID but no REST endpoint, try to fetch it
        if [[ -n "$flink_compute_pool_id" ]] && [[ -z "$flink_rest_endpoint" ]]; then
            info "Flink REST endpoint is missing. Trying to fetch actual endpoint..."
            output=$(confluent flink compute-pool describe "$flink_compute_pool_id" -o json 2>/dev/null)
            if [[ $? -eq 0 ]] && echo "$output" | jq empty 2>/dev/null; then
                # Try multiple ways to get the REST endpoint
                flink_endpoint=$(echo "$output" | jq -r '.http_endpoint // .rest_endpoint // .endpoint // .spec.http_endpoint // .spec.endpoint // empty')

                if [[ -n "$flink_endpoint" ]]; then
                    info "Found Flink REST endpoint: $flink_endpoint"
                    save_var "flink_rest_endpoint" "$flink_endpoint"
                else
                    # Generate a placeholder URL
                    provider=${confluent_cloud:-"azure"}
                    region=${confluent_region:-"eastus"}
                    generated_url="https://flink.${region}.${provider}.confluent.cloud"
                    warn "Could not find REST endpoint in API response, using generated endpoint: $generated_url"
                    info "NOTE: You'll need to update this with the actual value from the Confluent Cloud console."
                    save_var "flink_rest_endpoint" "$generated_url"
                fi
            else
                warn "Failed to get Flink pool details. Using generated endpoint."
                provider=${confluent_cloud:-"azure"}
                region=${confluent_region:-"eastus"}
                generated_url="https://flink.${region}.${provider}.confluent.cloud"
                info "Generated placeholder endpoint: $generated_url"
                save_var "flink_rest_endpoint" "$generated_url"
            fi
        fi

        export flink_compute_pool_id flink_rest_endpoint flink_pool_name
    fi

fi # End Environment Blocker check

# Get Catalog and Database Names (User Input)
if [[ ${required_vars[catalog_name]} -eq 0 ]] || [[ -z "${catalog_name}" ]]; then read -p "Catalog Name [Meeting_Coach_Demo_Catalog]: " user_catalog_name; user_catalog_name=${user_catalog_name:-Meeting_Coach_Demo_Catalog}; save_var "catalog_name" "$user_catalog_name"
else info "Using existing Catalog Name: $catalog_name"; export catalog_name; fi
if [[ ${required_vars[database_name]} -eq 0 ]] || [[ -z "${database_name}" ]]; then read -p "Database Name [meeting_coach_db]: " user_db_name; user_db_name=${user_db_name:-meeting_coach_db}; save_var "database_name" "$user_db_name"
else info "Using existing Database Name: $database_name"; export database_name; fi


# --- Final Checks for Pending Items ---
info "--- Running Final Checks for Pending Resources ---"

# Check Flink Endpoint again
if [[ -n "$flink_compute_pool_id" ]] && [[ -z "$flink_rest_endpoint" ]]; then info "Re-checking Flink Pool '$flink_pool_name' ($flink_compute_pool_id) for REST endpoint..."
    output=$(confluent flink compute-pool describe "$flink_compute_pool_id" -o json 2>/dev/null); if [[ $? -eq 0 ]]; then final_flink_endpoint=$(echo "$output" | jq -r '.http_endpoint // empty'); final_flink_status=$(echo "$output" | jq -r '.status // "UNKNOWN"')
        if [[ -n "$final_flink_endpoint" ]]; then info "Flink REST endpoint is now available!"; save_var "flink_rest_endpoint" "$final_flink_endpoint"; else warn "Flink REST endpoint still not available (Status: $final_flink_status). Manual update of '$ENV_FILE' may be needed."; fi
    else warn "Failed to re-describe Flink pool '$flink_compute_pool_id'."; fi; fi

# Check Kafka Cluster Name again
if [[ -n "$kafka_id" ]] && ([[ "$kafka_cluster_name" == "$kafka_id" ]] || [[ -z "$kafka_cluster_name" ]]); then info "Re-checking Kafka Cluster '$kafka_id' for display name..."
    output=$(confluent kafka cluster describe "$kafka_id" -o json 2>/dev/null); if [[ $? -eq 0 ]]; then final_kafka_name=$(echo "$output" | jq -r '.display_name // empty')
        if [[ -n "$final_kafka_name" ]] && [[ "$final_kafka_name" != "$kafka_cluster_name" ]]; then info "Kafka Cluster display name is now available!"; save_var "kafka_cluster_name" "$final_kafka_name"
        elif [[ -z "$final_kafka_name" ]] && [[ "$kafka_cluster_name" == "$kafka_id" || -z "$kafka_cluster_name" ]]; then warn "Kafka Cluster display name still not available for '$kafka_id'."; fi
    else warn "Failed to re-describe Kafka cluster '$kafka_id'."; fi; fi


# --- Final Summary ---
info "--- Credential Script Summary ---"
info "Environment file saved at: $ENV_FILE"
all_set=1; echo "Variable Status:"; for key in $(echo "${!required_vars[@]}" | tr ' ' '\n' | sort); do if [[ -n "${!key}" ]]; then if [[ "$key" == *"_secret" ]]; then echo "  [✓] $key: ******** (Set)"; else echo "  [✓] $key: ${!key}"; fi; if [[ ${required_vars[$key]} -ne 1 ]]; then warn "Internal state mismatch for '$key'."; fi
    elif [[ "$key" == "flink_rest_endpoint" ]] && [[ -n "$flink_compute_pool_id" ]] && [[ ${required_vars[$key]} -eq 1 ]] && [[ -z "$flink_rest_endpoint" ]]; then echo "  [!] $key: (Endpoint pending - Check later)"; all_set=0
    elif [[ "$key" == "kafka_cluster_name" ]] && [[ -n "$kafka_id" ]] && [[ ${required_vars[$key]} -eq 1 ]] && ([[ "$kafka_cluster_name" == "$kafka_id" ]] || [[ -z "$kafka_cluster_name" ]]); then echo "  [!] $key: (Name pending - Check later)"; all_set=0
    else is_missing=0; for missing_key in "${missing_vars[@]}"; do if [[ "$missing_key" == "$key" ]]; then is_missing=1; break; fi; done; if [[ $is_missing -eq 1 ]]; then echo "  [✗] $key: (Skipped/Failed)"; else echo "  [✗] $key: (Not Set)"; fi; all_set=0; required_vars[$key]=0; fi; done
echo ""; if [[ $all_set -eq 1 ]]; then info "All required variables appear set in $ENV_FILE!"; exit 0; else warn "Script finished, but some variables missing/skipped or pending."; warn "Review output & $ENV_FILE."; if [[ "$BLOCKER_HIT" == "1" ]]; then error "Critical environment setup failed."; fi; exit 1; fi
