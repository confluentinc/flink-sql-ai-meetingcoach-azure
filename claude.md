## How to run this configuration on your own and avoid conflicts

### 1. Provider configuration
Always keep the Schema Registry and Kafka configuration settings completely omitted from the provider block like this:

```hcl
provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret

  # Flink specific configuration
  flink_api_key         = var.flink_api_key
  flink_api_secret      = var.flink_api_secret
  flink_rest_endpoint   = var.flink_rest_endpoint
  organization_id       = var.organization_id
  environment_id        = var.environment_id
  flink_compute_pool_id = var.flink_compute_pool_id
  flink_principal_id    = var.flink_principal_id
}
```

### 2. Best practices for statement names and table names
To avoid conflicts, use a consistent and versioned naming pattern:

- **For statement names**: Add a timestamp or incremental version number
  ```hcl
  statement_name = "create-table-xyz-$(date +%Y%m%d%H%M%S)"
  ```
  or
  ```hcl
  statement_name = "create-table-xyz-v1"  # v2, v3, etc.
  ```

- **For table names**: Similarly, add a timestamp or incremental version
  ```sql
  CREATE TABLE `${var.environment_name}`.`${var.kafka_cluster_name}`.table_name_$(date +%Y%m%d%H%M%S)
  ```
  or
  ```sql
  CREATE TABLE `${var.environment_name}`.`${var.kafka_cluster_name}`.table_name_v1  # v2, v3, etc.
  ```

### 3. Before applying changes:
- Run `terraform state list | grep flink_statement` to see existing statements in state.
- List Flink statements on the server with:
  ```bash
  export $(grep -v '^#' .env | xargs) &&
  confluent flink statement list --region eastus --cloud azure | grep YOUR_TABLE_NAME
  ```
- If a statement exists but isn't in Terraform state, use a new name.

### 4. When updating existing statements:
- Use Terraform state rm to remove the statement from state.
- Create a new statement with a new version number.
- This approach maintains your infrastructure while avoiding conflicts.

### 5. For complex changes:
- Create new tables with new names and leave existing ones.
- Create a migration plan to transition data if needed.
- Drop old tables only after successful migration.

---

By following these practices, you'll avoid naming conflicts and ensure smooth operation when applying Terraform changes.



To run Terraform successfully with the Confluent provider, here are steps to avoid errors:


Required Variables for Confluent Provider
These must be set in your environment variables (TF_VAR_*) or . tfvars file:
1. Basic Credentials:
- confluent_cloud_api_key confluent_cloud_api_secret
2. Flink-specific Variables:
flink_api_key
- flink_api_secret
- flink rest endpoint - typically "https://flink.eastus.azure.confluent.cloud"
- organization_id - e.g., "b5f82d0d-20fd-44a9-8078-d882c3deb135"
- environment_id - e.g., "env-y29pwk"
- flink_compute_pool_id - e.g., "lfcp-ky806g"
- flink_principal_id - e.g., "sa-vx38dj"
3. Schema & Database Names:
- catalog_name - usually "Meeting-Coach-Demo"
- database_name - usually "meeting-coach-cluster"

How to Run Successfully
1. Load Environment Variables:
- Use unique
statement names with incrementing versions:
statement_name = "create-table-xyz-v1" # increment to v2, v3, etc.
- Use unique table names with incrementing versions: CREATE TABLE '${var.environment_name}'. '${var kafka_cluster_name}*.table_name_v1
- If a statement exists but conflicts: terraform state rm confluent flink statement. resource name
- Then edit main.tf to rename both:
- Statement name (e.g., "statement-name-v6" )
- Output table (e.g., "table_name_v6")
4. Provider Configuration:
- Never include Schema Registry or Kafka attributes in provider block
- Only include cloud_api_key/secret and Flink-specific attributes
5. Statements Using Manual Connections:
Ensure manual connections are created first via CLI commands
Example connections: 'azure-openai-embedding-connection', 'mongodb-connection-tf'
The key is ensuring unique names for each statement and table when reapplying, and completely omitting the schema registry and Kafka configuration from the provider block.

## Progress Summary (May 4, 2025)

### Completed Tasks:
1. ✅ Fixed schema registry attributes issue in the provider block
2. ✅ Configured MongoDB sink to use `knowledge_embeddings_chunked_tf_v2` and the `knowledge-mongodb` collection
3. ✅ Updated connection name for MongoDB to use `mongodb-connection-tf`
4. ✅ Cleaned up the main.tf file by removing old commented-out definitions
5. ✅ Updated all table names to use consistent versioning with `_tf_v1` or `_tf_v2` suffixes
6. ✅ Updated all relevant table dependencies to use versioned table names

### Current Infrastructure Components:
- MongoDB sink connector configured to use `knowledge_embeddings_chunked_tf_v2` topic
- MongoDB vector database table defined as `knowledge_mongodb_tf_v1`
- Versioned tables throughout the pipeline:
  - `knowledge_tf` (base table)
  - `messages_conversation_tf` (original conversations)
  - `messages_prospect_tf_v1` (filtered prospects)
  - `messages_prospect_embeddings_tf_v2` (embeddings for prospect messages)
  - `messages_prospect_rag_results_tf_v2` (RAG search results)
  - `messages_prospect_rag_llm_response_tf_v7` (final LLM responses)

### Known Issue:
The `create_knowledge_embeddings_chunked_tf` statement is failing with an internal server error. This statement is crucial as it:
1. Takes data from the `knowledge_tf` table
2. Splits text into chunks using ML_CHARACTER_TEXT_SPLITTER
3. Generates embeddings using ML_PREDICT with the openaiembed_tf model
4. Outputs to `knowledge_embeddings_chunked_tf_v2` topic, which feeds the MongoDB sink

The error message is not descriptive: "Internal error occurred. Statement: create-knowledge-embeddings-chunked-tf-v2"

### Next Steps:
1. The knowledge embedding statement needs to be created manually through the Confluent UI or CLI for now
2. Investigate the exact cause of the "Internal error" in the knowledge embedding statement
3. Consider implementing a direct producer application to generate embeddings as an alternative
4. Test the full data flow from knowledge input to LLM response

From the Terraform folder, be sure to run `source ./load_tf_vars` before `terraform plan`/`terraform apply` when testing.
