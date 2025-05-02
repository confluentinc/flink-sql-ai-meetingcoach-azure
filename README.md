# Flink AI Meeting Coach — Real-time Sales Coaching with RAG

This project demonstrates a real-time AI "Meeting Coach" showcasing the use of Confluent Cloud for Apache Flink AI Inference functions to build a real-time Retrieval-Augmented Generation (RAG) pipeline. The demo uses both a static knowledge base of sales documents and real-time simulated meeting data.

## Overview

The Meeting Coach system consumes a chat stream representing a sales meeting. When specific triggers occur (like a customer raising a price objection), it uses a RAG pipeline to retrieve relevant context from a knowledge base of company documents (e.g., battlecards, sales materials, previous meeting notes, objection handling tips) stored in a vector database, and generates real-time coaching suggestions for the salesperson using an LLM.

## Architecture
![Architecture Diagram](docs/architecture/Architecture%20Diagram.jpg)

## Prerequisites

- Confluent Cloud account with:
  - Kafka cluster
  - Flink compute pool
  - Schema Registry
  - [Confluent CLI installed](https://docs.confluent.io/confluent-cli/current/install.html) locally
- Microsoft Azure account with ability to spin up:
  - Azure OpenAI service (with access to `text-embedding-ada-002` and `gpt-4o-mini` models/deployments)
  - Azure Blob storage (Optional, if used for knowledge base source)
- MongoDB Atlas account with a cluster configured for vector search.

You will need appropriate credentials and permissions to create and manage resources in these cloud environments.

## Setup Steps

Setting up this demo involves configuring cloud resources and then defining the Flink pipelines using SQL.

### 1. Environment Variable Setup

Before running any commands, set up the required environment variables to configure your connection details:

```bash
# Adjust values based on your specific resource names and regions
export AZURE_REGION="eastus"
export CONFLUENT_ENV="<your-confluent-environment-id>"
export AZURE_OPENAI_RESOURCE="<your-azure-openai-resource-name>"
export MONGODB_CLUSTER="<your-mongodb-cluster-host-prefix>" # e.g., my-cluster.abcde
```

### 2. Cloud Resource Preparation

Ensure the following cloud resources are created and configured *before* proceeding with the Flink setup:

- **Azure OpenAI**: Deploy the `text-embedding-ada-002` and `gpt-4o-mini` models in your Azure OpenAI service. Note the endpoint URL and obtain an API key.
- **MongoDB Atlas**: Create a MongoDB Atlas cluster. Set up a database (e.g., `knowledgedb`) and a collection (e.g., `knowledge`). Create a vector search index (e.g., `vector_search`) on the collection, targeting the field where embeddings will be stored (e.g., `embedding`). Note the connection string, username, and password.
- **Confluent Cloud**:
    - Ensure you have a Kafka cluster and a Flink compute pool running in your specified environment (`$CONFLUENT_ENV`), in the same region.
    - Use Flink SQL to create the necessary Kafka topics. The required topic names are listed in the `end_to_end_architectural_overview.md` document (e.g., `knowledge`, `messages_conversation`, etc.).

### 3. Flink Configuration and Pipeline Creation

All the specific Confluent CLI commands and Flink SQL statements needed to build this demo are detailed in the [End-to-End Architectural Overview](end_to_end_architectural_overview.md) document.

Follow the steps in that document sequentially to:

1.  **Create Flink Connections:** Use the Confluent CLI to establish connections to Azure OpenAI and MongoDB Atlas.
2.  **Create AI Models:** Define the Flink SQL models (`openaiembed`, `coaching_response_generator`) that interface with the AI services.
3.  **Create Database Tables:** Define the Flink SQL tables that map to Kafka topics and the MongoDB collection.
4.  **Create Document Processing Pipeline:** Define the Flink SQL logic to chunk and embed knowledge base documents.
5.  **Create Message Processing Pipeline:** Define the Flink SQL logic to process incoming messages, generate embeddings, and perform vector search (RAG).
6.  **Create Response Generation Pipeline:** Define the Flink SQL logic to generate coaching responses using the LLM.
7.  **(Optional) Create Views:** Define Flink SQL views for monitoring.
8.  **(Optional) Set Storage Configuration:** Apply consistent Kafka consumer isolation levels.

Execute these commands and SQL statements via the Confluent CLI (preferably using the Flink SQL shell, accessed by entering `confluent flink shell` in the command line once the Confluent CLI is installed) or directly within the Confluent Cloud Flink SQL workspace associated with your compute pool.

## Data Flow
There are two main tracks that define how data flows within this project: the "Knowledge processing track", used to create document embeddings/vectors that enable RAG search, and the real-time "Query processing track," used to vectorize conversation snippets, enabling RAG search to retrieve relevant, contextual documents in real time.

### Knowledge Base Data Prep Pipeline:

1.  **Ingestion**: Generate static, synthetic knowledge base documents (e.g., .txt, .md). Use a method like the Kafka file source connector or a custom producer to send these documents as messages to the `knowledge` Kafka topic.
2.  **Processing & Embedding**: A Flink SQL job consumes these documents, chunks them using `ML_CHARACTER_TEXT_SPLITTER`, uses `ML_PREDICT` with the `openaiembed` model to call Azure OpenAI for embeddings, and prepares the data for the vector store.
3.  **Storage**: The embedded knowledge is stored in MongoDB Atlas via the `knowledge_mongodb` external table definition and a suitable sink mechanism (like the MongoDB Sink Connector, which needs separate configuration if not managed manually via Flink SQL's `INSERT INTO knowledge_mongodb`).

### Real-time Coaching Pipeline:

1.  **Input**: Real or simulated chat messages are sent to the `messages_conversation` Kafka topic via the frontend web UI.
2.  **Processing**:
    - Flink SQL filters the conversation for prospect messages (`messages_prospect`), then generates embeddings for these messages (`messages_prospect_embeddings`) by calling out to the Azure OpenAI `text-embedding-ada-002` model.
3.  **RAG**:
    - The system then uses Flink SQL AI functions to perform vector search against MongoDB Atlas vector database using `VECTOR_SEARCH`, and saves the results (`messages_prospect_rag_results`).
4.  **Generation**:
    - The system calls the Azure OpenAI `gpt-4o-mini` model via `ML_PREDICT` using the `coaching_response_generator` model and a custom prompt, including the prospect's recent message, and the retrieved document chunk results from RAG retrieval.
    - The result is stored in `messages_prospect_rag_llm_response`.
5.  **Pipeline result storage**: The original message, along with the relevant document chunks retrieved via RAG search, and the `coaching_response_generator`'s final meeting coaching output, are saved for later review and model retraining to Azure CosmosDB.

## Running the Application

1.  **Activate Virtual Environment**:
    Before running the application, activate the Python virtual environment. If you haven't created one, you can do so with `python -m venv .venv`.

    *   On macOS/Linux:
        ```bash
        source .venv/bin/activate
        ```
    *   On Windows:
        ```bash
        .\.venv\Scripts\activate
        ```

2.  **Install Dependencies**:
    Install the required Python packages:
    ```bash
    pip install -r requirements.txt
    ```
    *(Alternatively, if using `uv`, run `uv sync`)*

3.  **Set Environment Variables**:
    Ensure you have a `.env` file in the project root directory with the necessary configurations (see `sample_env.env` for required variables like Kafka/Schema Registry credentials and Azure OpenAI keys).

4.  **Run the Flask App**:
    Start the Flask development server:
    ```bash
    python app.py
    ```
    The application should now be accessible at `http://127.0.0.1:5000` (or the host/port specified in the output).
