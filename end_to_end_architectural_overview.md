## Complete RAG System Architecture
![Architecture Diagram](docs/architecture/Architecture%20Diagram.jpg)

### 1. Environment Setup

First, set up the environment variables:
```bash
export AZURE_REGION="<your-region>" # like 'eastus'
export CONFLUENT_ENV="<your-env-ID>" # like 'env-y29pwk'
export AZURE_OPENAI_RESOURCE="<endpoint-url-root-here" # Based on OpenAI endpoint URL, like 'meeting-coach-openai'
export MONGODB_CLUSTER="<endpoint-url-root-here" # Based on MongoDB endpoint URL, like 'mongodb-vector-cluster.qeyfh'
```

### 2. Create Connections

```bash
# Create embedding connection
confluent flink connection create azure-openai-embedding-connection \
  --type azureopenai \
  --cloud azure \
  --region $AZURE_REGION \
  --environment $CONFLUENT_ENV \
  --endpoint "https://$AZURE_OPENAI_RESOURCE.openai.azure.com/openai/deployments/text-embedding-ada-002/embeddings?api-version=2023-05-15" \
  --api-key "<your-api-key>"

# Create LLM connection
confluent flink connection create gpt-4o-mini-connection \
  --type azureopenai \
  --cloud azure \
  --region $AZURE_REGION \
  --environment $CONFLUENT_ENV \
  --endpoint "https://$AZURE_OPENAI_RESOURCE.openai.azure.com/openai/deployments/gpt-4o-mini/chat/completions?api-version=2025-01-01-preview" \
  --api-key "your-api-key"

# Create MongoDB connection
confluent flink connection create mongodb-connection \
  --type mongodb \
  --cloud azure \
  --region $AZURE_REGION \
  --environment $CONFLUENT_ENV \
  --endpoint "mongodb+srv://$MONGODB_CLUSTER.mongodb.net" \
  --username "<mongodb-username>" \
  --password "<mongodb-password>"
```

### 3. Create AI Models

```sql
-- Create embedding model
CREATE MODEL openaiembed
INPUT (input STRING)
OUTPUT (embedding ARRAY<FLOAT>)
WITH(
  'azureopenai.connection' = 'azure-openai-embedding-connection',
  'azureopenai.input_format' = 'OPENAI-EMBED',
  'provider' = 'azureopenai',
  'task' = 'classification'
);

-- Create text generation model
CREATE MODEL coaching_response_generator
INPUT (prompt STRING)
OUTPUT (coaching_response STRING)
WITH(
  'provider' = 'azureopenai',
  'task' = 'text_generation',
  'azureopenai.connection' = 'gpt-4o-mini-connection',
  'azureopenai.model_version' = 'gpt-4o-mini'
);
```

### 4. Create Database Tables

```sql
-- Create knowledge base table
CREATE TABLE knowledge (
  document_id STRING,
  document_name STRING,
  document_category STRING,
  document_text STRING
) WITH (
  'kafka.consumer.isolation-level' = 'read-uncommitted'
);

-- Create conversation message table
CREATE TABLE messages_conversation (
  message STRING NOT NULL,
  speaker STRING
) WITH (
  'kafka.consumer.isolation-level' = 'read-uncommitted'
);

-- Create MongoDB vector search table
CREATE TABLE knowledge_mongodb (
  document_id STRING,
  chunks STRING
) WITH (
  'connector' = 'mongodb',
  'mongodb.connection' = 'mongodb-connection-2',
  'mongodb.database' = 'knowledgedb',
  'mongodb.collection' = 'knowledge',
  'mongodb.index' = 'vector_search',
  'mongodb.embedding_column' = 'embedding',
  'mongodb.numCandidates' = '150'
);
```

### 5. Create Document Processing Pipeline

```sql
-- Create chunked and embedded knowledge
CREATE TABLE knowledge_embeddings_chunked AS
WITH chunked_texts AS (
  SELECT
    document_id,
    document_text,
    chunks
  FROM knowledge
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
```

### 6. Create Message Processing Pipeline

```sql
-- Filter prospect messages
CREATE TABLE messages_prospect AS
SELECT * FROM messages_conversation
WHERE speaker = 'prospect';

-- Create embedding table
CREATE TABLE messages_prospect_embeddings (
  message STRING,
  speaker STRING,
  embedding ARRAY<FLOAT>
);

-- Insert embeddings
INSERT INTO messages_prospect_embeddings
SELECT * FROM messages_prospect,
LATERAL TABLE(ML_PREDICT('openaiembed', message));

-- Create RAG results table
CREATE TABLE messages_prospect_rag_results AS
SELECT
    qe.message,
    qe.speaker,
    vs.search_results AS rag_results
FROM
    messages_prospect_embeddings AS qe,
    LATERAL TABLE(VECTOR_SEARCH(
        knowledge_mongodb,
        3,
        qe.embedding
    )) AS vs;
```

### 7. Create Response Generation Pipeline

```sql
-- Create final response table with LLM
CREATE TABLE `messages_prospect_rag_llm_response` AS
SELECT
    qr.message,
    CAST(qr.rag_results AS STRING) AS rag_results_string,
    pred.coaching_response
FROM messages_prospect_rag_results qr,
LATERAL TABLE(
    ml_predict(
        'coaching_response_generator',
        CONCAT(
                'You are an expert sales coach AI. Provide actionable sales guidance formatted as JSON.',
                '\n\n## PROSPECT MESSAGE: ', qr.message,
                '\n\n## RAG DOCUMENTS: \n',
                'Document 1: ', qr.rag_results[1].document_id, '\n',
                qr.rag_results[1].chunks, '\n\n',
                'Document 2: ', qr.rag_results[2].document_id, '\n',
                qr.rag_results[2].chunks, '\n\n',
                'Document 3: ', qr.rag_results[3].document_id, '\n',
                qr.rag_results[3].chunks, '\n\n',
                '\n\n## OUTPUT REQUIREMENTS:
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

```

### 8. Create Views for Monitoring

```sql
-- Create view for recent conversation history
CREATE VIEW recent_conversation_history AS
WITH ranked_messages AS (
  SELECT
    message,
    speaker,
    $rowtime,
    ROW_NUMBER() OVER (ORDER BY $rowtime DESC) AS msg_rank
  FROM messages_conversation
)
SELECT
  message,
  speaker,
  $rowtime
FROM ranked_messages
WHERE msg_rank <= 6
ORDER BY $rowtime;
```

### 9. Setup Storage Configuration

```sql
-- Set consistent isolation levels for all tables
ALTER TABLE knowledge SET ('kafka.consumer.isolation-level' = 'read-uncommitted');
ALTER TABLE knowledge_embeddings_chunked SET ('kafka.consumer.isolation-level' = 'read-uncommitted');
ALTER TABLE messages_conversation SET ('kafka.consumer.isolation-level' = 'read-uncommitted');
ALTER TABLE messages_prospect SET ('kafka.consumer.isolation-level' = 'read-uncommitted');
ALTER TABLE messages_prospect_embeddings SET ('kafka.consumer.isolation-level' = 'read-uncommitted');
ALTER TABLE messages_prospect_rag_results SET ('kafka.consumer.isolation-level' = 'read-uncommitted');
ALTER TABLE messages_prospect_rag_llm_response SET ('kafka.consumer.isolation-level' = 'read-uncommitted');
```
