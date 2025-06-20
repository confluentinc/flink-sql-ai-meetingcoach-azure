#!/bin/bash

# =============================================================================
# PERSONALIZED CONFLUENT & FLINK COMMAND GENERATOR
# =============================================================================
# This script generates all CLI and SQL commands needed for your specific
# infrastructure, using values from your terraform deployment.
# =============================================================================

set -e

echo "🚀 Generating Personalized Commands for Flink ML Demo (Regional Environment)"
echo "======================================================="

# Check if terraform output is available
if ! terraform output environment_id > /dev/null 2>&1; then
    echo "⚠️  Warning: Some Terraform outputs not available. Generating with available resources..."
    PARTIAL_MODE=true
else
    PARTIAL_MODE=false
fi

# =============================================================================
# EXTRACT VARIABLES FROM TERRAFORM OUTPUTS
# =============================================================================

echo "📊 Extracting infrastructure variables..."

# Get terraform outputs
TF_OUTPUT=$(terraform output -json)

# Extract Confluent variables (fail if terraform outputs not available)
ENVIRONMENT_ID=$(echo "$TF_OUTPUT" | jq -r '.environment_id.value')
KAFKA_CLUSTER_ID=$(echo "$TF_OUTPUT" | jq -r '.kafka_cluster_id.value')
FLINK_COMPUTE_POOL_ID=$(echo "$TF_OUTPUT" | jq -r '.flink_compute_pool_id.value')
SCHEMA_REGISTRY_ID=$(echo "$TF_OUTPUT" | jq -r '.schema_registry_id.value')

# Validate that required outputs are available
if [ -z "$ENVIRONMENT_ID" ] || [ "$ENVIRONMENT_ID" = "null" ]; then
    echo "❌ Error: Terraform outputs not available. Please run 'terraform apply' first."
    exit 1
fi

# Extract Azure variables from terraform outputs (required)
AZURE_OPENAI_ENDPOINT=$(echo "$TF_OUTPUT" | jq -r '.azure_openai_endpoint.value')
AZURE_OPENAI_EMBEDDING_ENDPOINT=$(echo "$TF_OUTPUT" | jq -r '.azure_openai_embedding_endpoint.value')
AZURE_OPENAI_GPT4_ENDPOINT=$(echo "$TF_OUTPUT" | jq -r '.azure_openai_gpt4_endpoint.value')
AZURE_STORAGE_ACCOUNT=$(echo "$TF_OUTPUT" | jq -r '.azure_storage_account_name.value')

# Validate that Azure endpoints are available
if [ -z "$AZURE_OPENAI_EMBEDDING_ENDPOINT" ] || [ "$AZURE_OPENAI_EMBEDDING_ENDPOINT" = "null" ]; then
    echo "❌ Error: Azure OpenAI endpoints not available in Terraform outputs."
    echo "   Please ensure 'terraform apply' completed successfully for Azure resources."
    exit 1
fi

# Get Azure OpenAI API key from terraform output (required)
AZURE_OPENAI_API_KEY=$(echo "$TF_OUTPUT" | jq -r '.azure_openai_api_key.value')
if [ -z "$AZURE_OPENAI_API_KEY" ] || [ "$AZURE_OPENAI_API_KEY" = "null" ]; then
    echo "❌ Error: Azure OpenAI API key not available in Terraform outputs."
    echo "   Please ensure 'terraform apply' completed successfully for Azure resources."
    exit 1
fi

# Extract deployment prefix for resource naming
DEPLOYMENT_PREFIX=$(grep "^DEPLOYMENT_PREFIX=" ../.env 2>/dev/null | cut -d'=' -f2- | tr -d '"' || echo "flink-ai-demo")

# Extract MongoDB variables (support both .env and .env-regional)
ENV_FILE=""
if [ -f "../.env-regional" ]; then
    ENV_FILE="../.env-regional"
elif [ -f "../.env" ]; then
    ENV_FILE="../.env"
fi

if [ -n "$ENV_FILE" ]; then
    MONGODB_CONNECTION_STRING=$(grep "^MONGODB_CONNECTION_STRING" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"')
    MONGODB_USERNAME=$(grep "^MONGODB_USERNAME" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"')
    MONGODB_PASSWORD=$(grep "^MONGODB_PASSWORD" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"')
else
    echo "❌ Error: No environment file (.env or .env-regional) found."
    echo "   Please create .env file with MongoDB credentials."
    exit 1
fi

# MongoDB configuration (from terraform outputs)
MONGODB_CLUSTER_NAME=$(echo "$TF_OUTPUT" | jq -r '.mongodb_cluster_name.value // "aimeetingcoach"')
MONGODB_DATABASE="knowledge_db"
MONGODB_COLLECTION="knowledge_embeddings"
MONGODB_INDEX_NAME="vector_search_index"

# Extract environment and cluster names from Terraform outputs
ENVIRONMENT_NAME=$(echo "$TF_OUTPUT" | jq -r '.environment_name.value')
KAFKA_CLUSTER_NAME=$(echo "$TF_OUTPUT" | jq -r '.kafka_cluster_name.value')

# Extract Azure region from environment or fallback
AZURE_REGION=$(grep "^AZURE_REGION=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || echo "eastus2")

# If outputs are empty, try terraform.tfvars as fallback
if [ -z "$ENVIRONMENT_NAME" ] || [ "$ENVIRONMENT_NAME" = "null" ]; then
    ENVIRONMENT_NAME=$(grep "^environment_name" terraform.tfvars | cut -d'"' -f2)
fi
if [ -z "$KAFKA_CLUSTER_NAME" ] || [ "$KAFKA_CLUSTER_NAME" = "null" ]; then
    KAFKA_CLUSTER_NAME=$(grep "^kafka_cluster_name" terraform.tfvars | cut -d'"' -f2)
fi

# Final fallback to defaults from variables.tf if still empty
if [ -z "$ENVIRONMENT_NAME" ] || [ "$ENVIRONMENT_NAME" = "null" ]; then
    ENVIRONMENT_NAME=$(grep -A 3 'variable "environment_name"' variables.tf | grep 'default' | sed 's/.*= *"//' | sed 's/".*//')
    if [ -z "$ENVIRONMENT_NAME" ]; then
        ENVIRONMENT_NAME="flink-ml-demo"
    fi
fi
if [ -z "$KAFKA_CLUSTER_NAME" ] || [ "$KAFKA_CLUSTER_NAME" = "null" ]; then
    KAFKA_CLUSTER_NAME=$(grep -A 3 'variable "kafka_cluster_name"' variables.tf | grep 'default' | sed 's/.*= *"//' | sed 's/".*//')
    if [ -z "$KAFKA_CLUSTER_NAME" ]; then
        KAFKA_CLUSTER_NAME="demo-cluster"
    fi
fi
if [ -z "$MONGODB_USERNAME" ]; then
    echo "❌ Error: MongoDB username not found in environment files."
    echo "   Please set MONGODB_USERNAME in your .env file."
    exit 1
fi
if [ -z "$MONGODB_PASSWORD" ]; then
    echo "❌ Error: MongoDB password not found in environment files."
    echo "   Please set MONGODB_PASSWORD in your .env file."
    exit 1
fi

# Extract region from tfvars or env-regional as fallback
AZURE_REGION=$(grep "azure_location" terraform.tfvars 2>/dev/null | cut -d'"' -f2)
if [ -z "$AZURE_REGION" ]; then
    AZURE_REGION=$(grep "^AZURE_REGION" .env-regional | cut -d'=' -f2- | tr -d '"')
fi

# Extract resource names for display purposes only (not used for URL construction)
AZURE_OPENAI_RESOURCE=$(echo "$AZURE_OPENAI_ENDPOINT" | sed 's|https://||' | sed 's|\.openai\.azure\.com.*||')

echo "✅ Variables extracted successfully!"
echo "   Environment Name: $ENVIRONMENT_NAME"
echo "   Kafka Cluster Name: $KAFKA_CLUSTER_NAME"
echo ""

# =============================================================================
# GENERATE OUTPUT FILE
# =============================================================================

OUTPUT_FILE="personalized_setup_commands.md"

cat > "$OUTPUT_FILE" << EOF
# Personalized Flink ML Demo Setup Commands

This file contains all the CLI and SQL commands customized for your specific infrastructure.

**Generated on:** $(date)
**Environment ID:** $ENVIRONMENT_ID
**Region:** $AZURE_REGION

## 📋 Prerequisites

1. **Confluent CLI installed and authenticated**
2. **Access to Confluent Cloud Flink SQL workspace**
3. **MongoDB Atlas credentials available**

---

## 1. 🌍 Set Environment Variables

Run these commands in your terminal to set up the environment:

\`\`\`bash
export AZURE_REGION="$AZURE_REGION"
export CONFLUENT_ENV="$ENVIRONMENT_ID"
export AZURE_OPENAI_RESOURCE="$AZURE_OPENAI_RESOURCE"
export AZURE_OPENAI_API_KEY="$AZURE_OPENAI_API_KEY"
export AZURE_OPENAI_EMBEDDING_ENDPOINT="$AZURE_OPENAI_EMBEDDING_ENDPOINT"
export AZURE_OPENAI_GPT4_ENDPOINT="$AZURE_OPENAI_GPT4_ENDPOINT"
export MONGODB_CONNECTION_STRING="$MONGODB_CONNECTION_STRING"
export MONGODB_USERNAME="$MONGODB_USERNAME"
export MONGODB_PASSWORD="$MONGODB_PASSWORD"
\`\`\`

---

## 2. 🔗 Create Connections

### Step 2.1: Create Azure OpenAI Embedding Connection

\`\`\`bash
confluent flink connection create azure-openai-embedding-connection --type azureopenai --cloud azure --region \$AZURE_REGION --endpoint "\$AZURE_OPENAI_EMBEDDING_ENDPOINT" --api-key "\$AZURE_OPENAI_API_KEY" --environment \$CONFLUENT_ENV
\`\`\`

### Step 2.2: Create Azure OpenAI GPT-4 Connection

\`\`\`bash
confluent flink connection create gpt-4-connection --type azureopenai --cloud azure --region \$AZURE_REGION --endpoint "\$AZURE_OPENAI_GPT4_ENDPOINT" --api-key "\$AZURE_OPENAI_API_KEY" --environment \$CONFLUENT_ENV
\`\`\`

### Step 2.3: Create MongoDB Connection

\`\`\`bash
confluent flink connection create mongodb-connection --type mongodb --cloud azure --region \$AZURE_REGION --endpoint "\$MONGODB_CONNECTION_STRING" --username "\$MONGODB_USERNAME" --password "\$MONGODB_PASSWORD" --environment \$CONFLUENT_ENV
\`\`\`

---

## 3. 🤖 Create AI Models

Open your **Confluent Cloud Flink SQL workspace** and run these commands:

### Step 3.1: Create Embedding Model

\`\`\`sql
CREATE MODEL openaiembed
INPUT (input STRING)
OUTPUT (embedding ARRAY<FLOAT>)
WITH(
  'azureopenai.connection' = 'azure-openai-embedding-connection',
  'azureopenai.input_format' = 'OPENAI-EMBED',
  'provider' = 'azureopenai',
  'task' = 'embedding'
);
\`\`\`

### Step 3.2: Create Text Generation Model

\`\`\`sql
CREATE MODEL coaching_response_generator
INPUT (prompt STRING)
OUTPUT (coaching_response STRING)
WITH(
  'provider' = 'azureopenai',
  'task' = 'text_generation',
  'azureopenai.connection' = 'gpt-4-connection',
  'azureopenai.model_version' = 'gpt-4',
  'azureopenai.system_prompt' = 'You are an expert sales coach AI. Provide actionable sales guidance formatted as JSON.

## OUTPUT REQUIREMENTS:
1. Create a JSON response with these fields:
  - suggested_response: A concise, actionable talking point (75 words max)
  - sources: An array with 3 objects (one for each document) containing:
    * document_index: The document number (1, 2, or 3)
    * document_id: The full document ID as provided
    * title: Just the filename extracted from document_id
    * path: Just the directory path extracted from document_id
    * full_text: The complete document text
    * used_excerpt: Exact text you used from this document (or empty if unused)
  - reasoning: Brief explanation of your suggestion (25 words max)

2. For each document:
  - Extract the filename from the document_id (Example: from objection_response_playbooks/pricing_objection_playbook.md, extract pricing_objection_playbook.md)
  - Extract the directory path if present (Example: from objection_response_playbooks/pricing_objection_playbook.md, extract objection_response_playbooks/)
  - Include only the exact text passages you used to form your response in used_excerpt

3. Always include all 3 documents in your response, even if you did not use them all.

4. Ensure your response is valid JSON that can be automatically parsed.'
);
\`\`\`

---

## 4. 📊 Create Database Tables

### Step 4.1: Create Knowledge Base Table

\`\`\`sql
CREATE TABLE \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.knowledge (
  document_id STRING,
  document_name STRING,
  document_category STRING,
  document_text STRING
) WITH (
  'kafka.consumer.isolation-level' = 'read-uncommitted'
);
\`\`\`

### Step 4.2: Create Conversation Message Table

\`\`\`sql
CREATE TABLE \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.messages_conversation (
  message STRING NOT NULL,
  speaker STRING
) WITH (
  'kafka.consumer.isolation-level' = 'read-uncommitted'
);
\`\`\`

### Step 4.3: Create MongoDB Vector Search Table

\`\`\`sql
CREATE TABLE \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.knowledge_mongodb (
  document_id STRING,
  chunks STRING,
  embedding ARRAY<FLOAT>
) WITH (
  'connector' = 'mongodb',
  'mongodb.connection' = 'mongodb-connection',
  'mongodb.database' = '$MONGODB_DATABASE',
  'mongodb.collection' = '$MONGODB_COLLECTION',
  'mongodb.index' = '$MONGODB_INDEX_NAME',
  'mongodb.embedding_column' = 'embedding',
  'mongodb.numCandidates' = '150'
);
\`\`\`

---

## 5. 🔄 Create Document Processing Pipeline

### Step 5.1: Populate Chunked and Embedded Knowledge

\`\`\`sql
INSERT INTO \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.knowledge_embeddings_chunked
WITH chunked_texts AS (
  SELECT
    document_id,
    document_text,
    chunks
  FROM \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.knowledge
  CROSS JOIN UNNEST(
    ML_CHARACTER_TEXT_SPLITTER(
      document_text, 200, 20, '###', false, false, true, 'START'
    )
  ) AS t(chunks)
)
SELECT
  document_id,
  chunks,
  embedding AS embedding
FROM chunked_texts,
LATERAL TABLE(
  ML_PREDICT('openaiembed', chunks)
);
\`\`\`

<!-- NOTE: The table structure is now created by Terraform, so this is an INSERT INTO operation -->

---

## 6. 💬 Create Message Processing Pipeline

### Step 6.1: Filter Prospect Messages

\`\`\`sql
CREATE TABLE \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.messages_prospect AS
SELECT * FROM \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.messages_conversation
WHERE speaker = 'prospect';
\`\`\`

### Step 6.2: Create Message Embeddings

\`\`\`sql
CREATE TABLE \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.messages_prospect_embeddings AS
SELECT
  message,
  speaker,
  embedding
FROM \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.messages_prospect,
LATERAL TABLE(ML_PREDICT('openaiembed', message));
\`\`\`

### Step 6.3: Create RAG Results Table

\`\`\`sql
CREATE TABLE \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.messages_prospect_rag_results AS
SELECT
    qe.message,
    qe.speaker,
    -- Transform the array with named fields to exclude embeddings
    ARRAY[
        CAST(ROW(vs.search_results[1].document_id, vs.search_results[1].chunks) AS ROW<document_id STRING, chunks STRING>),
        CAST(ROW(vs.search_results[2].document_id, vs.search_results[2].chunks) AS ROW<document_id STRING, chunks STRING>),
        CAST(ROW(vs.search_results[3].document_id, vs.search_results[3].chunks) AS ROW<document_id STRING, chunks STRING>)
    ] AS rag_results
FROM
    \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.messages_prospect_embeddings AS qe,
    LATERAL TABLE(VECTOR_SEARCH(
        \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.knowledge_mongodb,
        3,
        DESCRIPTOR(embedding),
        qe.embedding
    )) AS vs;
\`\`\`

<!-- OLD VERSION (commented out until new version is confirmed working)
\`\`\`sql
CREATE TABLE \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.messages_prospect_rag_results AS
SELECT
    qe.message,
    qe.speaker,
    vs.search_results AS rag_results
FROM
    \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.messages_prospect_embeddings AS qe,
    LATERAL TABLE(VECTOR_SEARCH(
        \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.knowledge_mongodb,
        3,
        DESCRIPTOR(embedding),
        qe.embedding
    )) AS vs;
\`\`\`
-->

---

## 7. 🎯 Create Response Generation Pipeline

### Step 7.1: Create Final LLM Response Table

\`\`\`sql
CREATE TABLE \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.messages_prospect_rag_llm_response AS
SELECT
    qr.message,
    CAST(qr.rag_results AS STRING) AS rag_results_string,
    pred.coaching_response
FROM \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.messages_prospect_rag_results qr,
LATERAL TABLE(
    ml_predict(
        'coaching_response_generator',
        CONCAT(
            '## PROSPECT MESSAGE: ', qr.message,
            '\\n\\n## RAG DOCUMENTS:\\n',
            'Document 1: ', qr.rag_results[1].document_id, '\\n',
            qr.rag_results[1].chunks, '\\n\\n',
            'Document 2: ', qr.rag_results[2].document_id, '\\n',
            qr.rag_results[2].chunks, '\\n\\n',
            'Document 3: ', qr.rag_results[3].document_id, '\\n',
            qr.rag_results[3].chunks
        )
    )
) AS pred;
\`\`\`

<!-- OLD VERSION (commented out until new version is confirmed working)
\`\`\`sql
CREATE TABLE \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.messages_prospect_rag_llm_response AS
SELECT
    qr.message,
    CAST(qr.rag_results AS STRING) AS rag_results_string,
    pred.coaching_response
FROM \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.messages_prospect_rag_results qr,
LATERAL TABLE(
    ml_predict(
        'coaching_response_generator',
        CONCAT(
                'You are an expert sales coach AI. Provide actionable sales guidance formatted as JSON.',
                '\\n\\n## PROSPECT MESSAGE: ', qr.message,
                '\\n\\n## RAG DOCUMENTS: \\n',
                'Document 1: ', qr.rag_results[1].document_id, '\\n',
                qr.rag_results[1].chunks, '\\n\\n',
                'Document 2: ', qr.rag_results[2].document_id, '\\n',
                qr.rag_results[2].chunks, '\\n\\n',
                'Document 3: ', qr.rag_results[3].document_id, '\\n',
                qr.rag_results[3].chunks, '\\n\\n',
                '\\n\\n## OUTPUT REQUIREMENTS:
                1. Create a JSON response with these fields:
                  - suggested_response: A concise, actionable talking point (75 words max)
                  - sources: An array with 3 objects (one for each document) containing:
                    * document_index: The document number (1, 2, or 3)
                    * document_id: The full document ID as provided
                    * title: Just the filename extracted from document_id
                    * path: Just the directory path extracted from document_id
                    * full_text: The complete document text
                    * used_excerpt: Exact text you used from this document (or empty if unused)
                  - reasoning: Brief explanation of your suggestion (25 words max)

                2. For each document:
                  - Extract the filename from the document_id (Example: from objection_response_playbooks/pricing_objection_playbook.md, extract pricing_objection_playbook.md)
                  - Extract the directory path if present (Example: from objection_response_playbooks/pricing_objection_playbook.md, extract objection_response_playbooks/)
                  - Include only the exact text passages you used to form your response in used_excerpt

                3. Always include all 3 documents in your response, even if you did not use them all.

                4. Ensure your response is valid JSON that can be automatically parsed.'
        )
    )
) AS pred;
\`\`\`
-->

---

## 8. 📈 Create Monitoring Views

### Step 8.1: Recent Conversation History View

\`\`\`sql
CREATE VIEW \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.recent_conversation_history AS
WITH ranked_messages AS (
  SELECT
    message,
    speaker,
    \$rowtime,
    ROW_NUMBER() OVER (ORDER BY \$rowtime DESC) AS msg_rank
  FROM \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.messages_conversation
)
SELECT
  message,
  speaker,
  \$rowtime
FROM ranked_messages
WHERE msg_rank <= 6
ORDER BY \$rowtime;
\`\`\`

---

## 9. ⚙️ Configure Table Settings

### Step 9.1: Set Isolation Levels

\`\`\`sql
ALTER TABLE \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.knowledge SET ('kafka.consumer.isolation-level' = 'read-uncommitted');
ALTER TABLE \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.knowledge_embeddings_chunked SET ('kafka.consumer.isolation-level' = 'read-uncommitted');
ALTER TABLE \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.messages_conversation SET ('kafka.consumer.isolation-level' = 'read-uncommitted');
ALTER TABLE \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.messages_prospect SET ('kafka.consumer.isolation-level' = 'read-uncommitted');
ALTER TABLE \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.messages_prospect_embeddings SET ('kafka.consumer.isolation-level' = 'read-uncommitted');
ALTER TABLE \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.messages_prospect_rag_results SET ('kafka.consumer.isolation-level' = 'read-uncommitted');
ALTER TABLE \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.messages_prospect_rag_llm_response SET ('kafka.consumer.isolation-level' = 'read-uncommitted');
\`\`\`

---

## 10. 🧪 Test Data Insertion

### Step 10.1: Insert Sample Knowledge

\`\`\`sql
INSERT INTO \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.knowledge VALUES (
  'sample/test_document.md',
  'Test Document',
  'sample',
  'This is a sample document for testing the RAG pipeline. It contains information about our product features and capabilities.'
);
\`\`\`

### Step 10.2: Insert Sample Conversation

\`\`\`sql
INSERT INTO \`$ENVIRONMENT_NAME\`.\`$KAFKA_CLUSTER_NAME\`.messages_conversation VALUES (
  'I am interested in your product but I am concerned about the pricing.',
  'prospect'
);
\`\`\`

---

## 📚 Quick Reference

### Your Infrastructure Details:
- **Environment ID:** \`$ENVIRONMENT_ID\`
- **Kafka Cluster ID:** \`$KAFKA_CLUSTER_ID\`
- **Flink Compute Pool ID:** \`$FLINK_COMPUTE_POOL_ID\`
- **Azure OpenAI Endpoint:** \`$AZURE_OPENAI_ENDPOINT\`
- **MongoDB Cluster:** \`$MONGODB_CLUSTER_NAME\`
- **Region:** \`$AZURE_REGION\`

### Connection Names Created:
- \`azure-openai-embedding-connection\`
- \`gpt-4-connection\`
- \`mongodb-connection\`

### Model Names Created:
- \`openaiembed\`
- \`coaching_response_generator\`

### Table Names Created:
- \`knowledge\`
- \`messages_conversation\`
- \`messages_prospect\`
- \`messages_prospect_embeddings\`
- \`messages_prospect_rag_results\`
- \`messages_prospect_rag_llm_response\`
- \`knowledge_mongodb\`
- \`knowledge_embeddings_chunked\`

---

## 🚨 Important Notes

1. **Run commands in sequence** - Each step depends on the previous ones
2. **MongoDB credentials** - Update the MongoDB username/password in the environment variables
3. **Vector search index** - Ensure your MongoDB vector search index is properly configured
4. **Flink SQL workspace** - All SQL commands should be run in the Confluent Cloud Flink SQL workspace
5. **Permissions** - Make sure your Confluent CLI is authenticated and has proper permissions
6. **MongoDB Sink Connector** - A Confluent Connect MongoDB sink connector will automatically store knowledge embeddings from the \`knowledge_embeddings_chunked\` topic to MongoDB for vector search

---

**Generated by:** Terraform-based Command Generator
**Timestamp:** $(date)
EOF

echo "✅ Personalized commands generated successfully!"
echo ""
echo "📄 Output file: $OUTPUT_FILE"
echo ""
echo "🔍 Your Infrastructure Summary:"
echo "   Environment ID: $ENVIRONMENT_ID"
echo "   Kafka Cluster ID: $KAFKA_CLUSTER_ID"
echo "   Region: $AZURE_REGION"
echo "   OpenAI Resource: $AZURE_OPENAI_RESOURCE"
echo "   MongoDB Cluster: $MONGODB_CLUSTER_NAME"
echo ""
echo "📝 Next Steps:"
echo "   1. Review the generated commands in: $OUTPUT_FILE"
echo "   2. Set your MongoDB credentials in the environment variables"
echo "   3. Run the CLI commands to create connections"
echo "   4. Execute the SQL commands in Confluent Cloud Flink SQL workspace"
echo ""
echo "🎉 Ready to deploy your RAG pipeline!"
