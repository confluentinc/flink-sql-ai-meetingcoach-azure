# Minimal Terraform configuration for Confluent Cloud with Schema Registry
# Based on proven working patterns

terraform {
  required_providers {
    confluent = {
      source = "confluentinc/confluent"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = "~> 1.35.0"
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
  tenant_id       = var.azure_tenant_id
}

provider "mongodbatlas" {
  public_key  = var.mongodbatlas_public_key
  private_key = var.mongodbatlas_private_key
}

# Variables are defined in variables.tf

# Local values for computed configurations
locals {
  # Extract MongoDB host from connection string for connector configuration
  # Connection string format: mongodb+srv://cluster.bgvpswo.mongodb.net/database
  mongodb_host = var.mongodb_connection_host != "" ? var.mongodb_connection_host : regex("mongodb\\+srv://([^/]+)", var.mongodb_connection_string)[0]
}

# 1. Environment with ESSENTIALS governance (this enables Schema Registry!)
resource "confluent_environment" "main" {
  display_name = var.environment_name

  stream_governance {
    package = "ESSENTIALS"
  }
}

# 2. STANDARD Kafka cluster (Schema Registry auto-created with this)
resource "confluent_kafka_cluster" "main" {
  display_name = var.kafka_cluster_name
  availability = "SINGLE_ZONE"
  cloud        = "AZURE"
  region       = var.confluent_region
  standard {}  # This enables Schema Registry - NOT basic {}

  environment {
    id = confluent_environment.main.id
  }
}

# 3. Schema Registry data source (automatically available after Standard cluster)
data "confluent_schema_registry_cluster" "main" {
  environment {
    id = confluent_environment.main.id
  }

  depends_on = [confluent_kafka_cluster.main]
}

# 4. Service account for app management
resource "confluent_service_account" "app" {
  display_name = "kafka-app-manager"
  description  = "Service account for Kafka and Schema Registry access"
}

# 5. Kafka cluster admin role
resource "confluent_role_binding" "app-kafka-admin" {
  principal   = "User:${confluent_service_account.app.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.main.rbac_crn
}

# 6. Schema Registry admin role
resource "confluent_role_binding" "app-env-admin" {
  principal   = "User:${confluent_service_account.app.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.main.resource_name
}

# 7. Kafka API key
resource "confluent_api_key" "kafka" {
  display_name = "kafka-api-key"
  description  = "API key for Kafka operations"

  owner {
    id          = confluent_service_account.app.id
    api_version = confluent_service_account.app.api_version
    kind        = confluent_service_account.app.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.main.id
    api_version = confluent_kafka_cluster.main.api_version
    kind        = confluent_kafka_cluster.main.kind

    environment {
      id = confluent_environment.main.id
    }
  }

  depends_on = [confluent_role_binding.app-kafka-admin]
}

# 8. Schema Registry API key
resource "confluent_api_key" "schema_registry" {
  display_name = "schema-registry-api-key"
  description  = "API key for Schema Registry operations"

  owner {
    id          = confluent_service_account.app.id
    api_version = confluent_service_account.app.api_version
    kind        = confluent_service_account.app.kind
  }

  managed_resource {
    id          = data.confluent_schema_registry_cluster.main.id
    api_version = data.confluent_schema_registry_cluster.main.api_version
    kind        = data.confluent_schema_registry_cluster.main.kind

    environment {
      id = confluent_environment.main.id
    }
  }

  # depends_on = [confluent_role_binding.app-sr-admin]
}

# 9. Essential Kafka topics - COMMENTED OUT - Topics created manually via CREATE TABLE statements
# resource "confluent_kafka_topic" "knowledge" {
#   topic_name       = "knowledge"
#   partitions_count = 6
#
#   kafka_cluster {
#     id = confluent_kafka_cluster.main.id
#   }
#
#   rest_endpoint = confluent_kafka_cluster.main.rest_endpoint
#
#   credentials {
#     key    = confluent_api_key.kafka.id
#     secret = confluent_api_key.kafka.secret
#   }
# }

# resource "confluent_kafka_topic" "messages_conversation" {
#   topic_name       = "messages_conversation"
#   partitions_count = 6
#
#   kafka_cluster {
#     id = confluent_kafka_cluster.main.id
#   }
#
#   rest_endpoint = confluent_kafka_cluster.main.rest_endpoint
#
#   credentials {
#     key    = confluent_api_key.kafka.id
#     secret = confluent_api_key.kafka.secret
#   }
# }

# 10. Flink compute pool
resource "confluent_flink_compute_pool" "main" {
  display_name = var.flink_compute_pool_name
  cloud        = "AZURE"
  region       = var.confluent_region
  max_cfu      = 20

  environment {
    id = confluent_environment.main.id
  }
}

# 10a. Flink service account for running SQL statements
resource "confluent_service_account" "flink" {
  display_name = "flink-statement-executor"
  description  = "Service account for running Flink SQL statements"
}

# 10b. Flink compute pool admin role - using EnvironmentAdmin is sufficient for Flink operations
# resource "confluent_role_binding" "flink-compute-admin" {
#   principal   = "User:${confluent_service_account.flink.id}"
#   role_name   = "FlinkAdmin"  # This role doesn't exist for compute pools
#   crn_pattern = confluent_flink_compute_pool.main.resource_name
# }

# 10c. Environment admin role for Flink service account
resource "confluent_role_binding" "flink-env-admin" {
  principal   = "User:${confluent_service_account.flink.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.main.resource_name
}


# 11. Azure Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${replace(var.deployment_prefix, "-", "_")}_rg"
  location = var.azure_location
}

# 12. Azure OpenAI Service
resource "azurerm_cognitive_account" "openai" {
  name                = "${replace(var.deployment_prefix, "-", "_")}_openai"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  kind                = "OpenAI"
  sku_name            = "S0"

  custom_subdomain_name = replace(var.deployment_prefix, "_", "-")
}

# 13. OpenAI Embedding Model
resource "azurerm_cognitive_deployment" "embedding" {
  name                 = "text-embedding-ada-002"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "text-embedding-ada-002"
    version = "2"
  }

  scale {
    type     = "Standard"
    capacity = 120
  }
}

# 14. OpenAI GPT-4 Model for Chat Completion
resource "azurerm_cognitive_deployment" "gpt4" {
  name                 = "gpt-4"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "gpt-4"
    version = "turbo-2024-04-09"
  }

  scale {
    type     = "Standard"
    capacity = 30
  }
}

# 15. Azure Storage Account for documents and files
resource "azurerm_storage_account" "main" {
  name                     = "${replace(replace(var.deployment_prefix, "-", ""), "_", "")}storage"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  blob_properties {
    change_feed_enabled = true
    versioning_enabled  = true
  }
}

# 16. Storage Container for knowledge base documents
resource "azurerm_storage_container" "knowledge" {
  name                  = "knowledge-base"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# 17. Azure Cosmos DB (optional alternative to MongoDB)
# Uncomment if you want to use Cosmos DB instead of MongoDB Atlas
# resource "azurerm_cosmosdb_account" "main" {
#   name                = "${replace(var.deployment_prefix, "-", "_")}_cosmosdb"
#   location            = azurerm_resource_group.main.location
#   resource_group_name = azurerm_resource_group.main.name
#   offer_type          = "Standard"
#   kind                = "MongoDB"
#
#   consistency_policy {
#     consistency_level       = "BoundedStaleness"
#     max_interval_in_seconds = 300
#     max_staleness_prefix    = 100000
#   }
#
#   geo_location {
#     location          = azurerm_resource_group.main.location
#     failover_priority = 0
#   }
#
#   capabilities {
#     name = "EnableMongo"
#   }
#
#   capabilities {
#     name = "MongoDBv3.4"
#   }
# }
#
# resource "azurerm_cosmosdb_mongo_database" "main" {
#   name                = "knowledge_db"
#   resource_group_name = azurerm_resource_group.main.name
#   account_name        = azurerm_cosmosdb_account.main.name
# }
#
# resource "azurerm_cosmosdb_mongo_collection" "embeddings" {
#   name                = "knowledge_embeddings"
#   resource_group_name = azurerm_resource_group.main.name
#   account_name        = azurerm_cosmosdb_account.main.name
#   database_name       = azurerm_cosmosdb_mongo_database.main.name
#
#   default_ttl_seconds = -1
#   shard_key           = "_id"
# }

# OUTPUTS - What you need for next steps
output "environment_id" {
  value = confluent_environment.main.id
}

output "environment_name" {
  value = confluent_environment.main.display_name
}

output "kafka_cluster_id" {
  value = confluent_kafka_cluster.main.id
}

output "kafka_cluster_name" {
  value = confluent_kafka_cluster.main.display_name
}

output "kafka_bootstrap_endpoint" {
  value = confluent_kafka_cluster.main.bootstrap_endpoint
}

output "schema_registry_id" {
  value = data.confluent_schema_registry_cluster.main.id
}

output "schema_registry_endpoint" {
  value = data.confluent_schema_registry_cluster.main.rest_endpoint
}

output "kafka_api_key" {
  value = confluent_api_key.kafka.id
}

output "kafka_api_secret" {
  value     = confluent_api_key.kafka.secret
  sensitive = true
}

output "schema_registry_api_key" {
  value = confluent_api_key.schema_registry.id
}

output "schema_registry_api_secret" {
  value     = confluent_api_key.schema_registry.secret
  sensitive = true
}

output "azure_openai_endpoint" {
  value = azurerm_cognitive_account.openai.endpoint
}

output "azure_openai_api_key" {
  value     = azurerm_cognitive_account.openai.primary_access_key
  sensitive = true
}

output "azure_openai_embedding_endpoint" {
  description = "Full Azure OpenAI embedding endpoint URL"
  value = "${azurerm_cognitive_account.openai.endpoint}openai/deployments/${azurerm_cognitive_deployment.embedding.name}/embeddings?api-version=2023-05-15"
}

output "azure_openai_gpt4_endpoint" {
  description = "Full Azure OpenAI GPT-4 chat completions endpoint URL"
  value = "${azurerm_cognitive_account.openai.endpoint}openai/deployments/${azurerm_cognitive_deployment.gpt4.name}/chat/completions?api-version=2024-02-01"
}

output "azure_storage_account_name" {
  value = azurerm_storage_account.main.name
}

output "azure_storage_connection_string" {
  value     = azurerm_storage_account.main.primary_connection_string
  sensitive = true
}

# 18. MongoDB Atlas Resources - Using existing free tier cluster
# Reference existing MongoDB Atlas cluster (created manually in UI)
data "mongodbatlas_cluster" "existing" {
  project_id = var.mongodbatlas_project_id
  name       = var.mongodb_cluster_name  # "aimeetingcoach" - your existing cluster
}

# MongoDB vector search index - commented out as it already exists
# resource "mongodbatlas_search_index" "vector_search" {
#   project_id      = var.mongodbatlas_project_id
#   cluster_name    = data.mongodbatlas_cluster.existing.name
#   collection_name = var.mongodb_collection_name
#   database        = var.mongodb_database_name
#   name            = var.mongodb_index_name
#   type            = "vectorSearch"

#   fields = <<-EOF
# [{
#       "type": "vector",
#       "path": "${var.mongodb_embedding_column}",
#       "numDimensions": 1536,
#       "similarity": "cosine"
# }]
# EOF
# }

# Removed locals - now using actual MongoDB Atlas resources

# Database user for the application - temporarily commented for debugging
# resource "mongodbatlas_database_user" "main" {
#   username           = var.mongodb_username
#   password           = var.mongodb_password
#   project_id         = data.mongodbatlas_project.main.id
#   auth_database_name = "admin"

#   roles {
#     role_name     = "readWrite"
#     database_name = var.mongodb_database_name
#   }
# }

# # IP Access List - allow from anywhere for development
# resource "mongodbatlas_project_ip_access_list" "main" {
#   project_id = data.mongodbatlas_project.main.id
#   cidr_block = "0.0.0.0/0"
#   comment    = "Allow all IPs for development (restrict in production)"
# }

# # Vector Search Index for embeddings
# resource "mongodbatlas_search_index" "vector_search" {
#   project_id      = data.mongodbatlas_project.main.id
#   cluster_name    = data.mongodbatlas_cluster.main.name
#   database        = var.mongodb_database_name
#   collection_name = var.mongodb_collection_name
#   name            = var.mongodb_index_name
#   type            = "vectorSearch"

#   fields = jsonencode([
#     {
#       type = "vector"
#       path = var.mongodb_embedding_column
#       numDimensions = 1536  # OpenAI text-embedding-ada-002 dimensions
#       similarity = "cosine"
#     }
#   ])

#   depends_on = [
#     mongodbatlas_database_user.main,
#     mongodbatlas_project_ip_access_list.main
#   ]
# }

# 19. Additional Kafka Topics for Full Pipeline - COMMENTED OUT - Topics created manually via CREATE TABLE statements
# resource "confluent_kafka_topic" "knowledge_embeddings_chunked" {
#   topic_name       = "knowledge_embeddings_chunked"
#   partitions_count = 6
#
#   kafka_cluster {
#     id = confluent_kafka_cluster.main.id
#   }
#
#   rest_endpoint = confluent_kafka_cluster.main.rest_endpoint
#
#   credentials {
#     key    = confluent_api_key.kafka.id
#     secret = confluent_api_key.kafka.secret
#   }
# }

# resource "confluent_kafka_topic" "messages_prospect" {
#   topic_name       = "messages_prospect"
#   partitions_count = 6
#
#   kafka_cluster {
#     id = confluent_kafka_cluster.main.id
#   }
#
#   rest_endpoint = confluent_kafka_cluster.main.rest_endpoint
#
#   credentials {
#     key    = confluent_api_key.kafka.id
#     secret = confluent_api_key.kafka.secret
#   }
# }

# resource "confluent_kafka_topic" "messages_prospect_embeddings" {
#   topic_name       = "messages_prospect_embeddings"
#   partitions_count = 6
#
#   kafka_cluster {
#     id = confluent_kafka_cluster.main.id
#   }
#
#   rest_endpoint = confluent_kafka_cluster.main.rest_endpoint
#
#   credentials {
#     key    = confluent_api_key.kafka.id
#     secret = confluent_api_key.kafka.secret
#   }
# }

# resource "confluent_kafka_topic" "messages_prospect_rag_results" {
#   topic_name       = "messages_prospect_rag_results"
#   partitions_count = 6
#
#   kafka_cluster {
#     id = confluent_kafka_cluster.main.id
#   }
#
#   rest_endpoint = confluent_kafka_cluster.main.rest_endpoint
#
#   credentials {
#     key    = confluent_api_key.kafka.id
#     secret = confluent_api_key.kafka.secret
#   }
# }

# resource "confluent_kafka_topic" "messages_prospect_rag_llm_response" {
#   topic_name       = "messages_prospect_rag_llm_response"
#   partitions_count = 6
#
#   kafka_cluster {
#     id = confluent_kafka_cluster.main.id
#   }
#
#   rest_endpoint = confluent_kafka_cluster.main.rest_endpoint
#
#   credentials {
#     key    = confluent_api_key.kafka.id
#     secret = confluent_api_key.kafka.secret
#   }
# }

# 20. MongoDB Sink Connector for Knowledge Embeddings - Using existing cluster
resource "confluent_connector" "mongodb_sink" {
  environment {
    id = confluent_environment.main.id
  }

  kafka_cluster {
    id = confluent_kafka_cluster.main.id
  }

  config_sensitive = {
    "connection.password" = var.mongodb_password
  }

  config_nonsensitive = {
    "connector.class"                                = "MongoDbAtlasSink"
    "name"                                          = "mongodb-sink-eastus2"
    "kafka.api.key"                                 = confluent_api_key.kafka.id
    "kafka.api.secret"                              = confluent_api_key.kafka.secret
    "topics"                                        = "knowledge_embeddings_chunked"
    "input.data.format"                             = "AVRO"
    "connection.host"                               = local.mongodb_host
    "connection.user"                               = var.mongodb_username
    "database"                                      = var.mongodb_database_name
    "collection"                                    = var.mongodb_collection_name
    "tasks.max"                                     = "1"
    "value.converter.schemas.enable"                = "false"
    "value.converter.decimal.format"                = "BASE64"
    "max.num.retries"                               = "3"
    "retries.defer.timeout"                         = "5000"
    "delete.on.null.values"                         = "false"
    "writemodel.strategy"                           = "DefaultWriteModelStrategy"
    "max.batch.size"                                = "0"
    "use.ordered.bulk.writes"                       = "true"
    "document.id.strategy"                          = "BsonOidStrategy"
    "document.id.strategy.overwrite.existing"       = "false"
  }

  depends_on = [
    confluent_role_binding.app-kafka-admin
  ]
}

# MongoDB Atlas outputs - using manual configuration
output "mongodb_connection_string" {
  description = "MongoDB Atlas connection string"
  value       = replace(data.mongodbatlas_cluster.existing.connection_strings[0].standard_srv, "mongodb+srv://", "mongodb+srv://${var.mongodb_username}:${var.mongodb_password}@")
  sensitive   = true
}

output "mongodb_cluster_name" {
  description = "MongoDB Atlas cluster name"
  value       = data.mongodbatlas_cluster.existing.name
}

output "mongodb_vector_index_config" {
  description = "MongoDB Atlas Vector Search Index configuration for manual creation"
  value = {
    cluster_name    = data.mongodbatlas_cluster.existing.name
    database        = var.mongodb_database_name
    collection      = var.mongodb_collection_name
    index_name      = var.mongodb_index_name
    embedding_field = var.mongodb_embedding_column
    dimensions      = 1536
    similarity      = "cosine"
    instructions    = "1. Go to MongoDB Atlas UI → Your Cluster → Search Tab → Create Index. 2. Use JSON Editor. 3. Paste the json_config below. 4. Set Database and Collection as shown above."
    json_config     = jsonencode({
      fields = [{
        type = "vector"
        path = var.mongodb_embedding_column
        numDimensions = 1536
        similarity = "cosine"
      }]
    })
  }
}

output "flink_compute_pool_id" {
  value = confluent_flink_compute_pool.main.id
}

# MongoDB vector search index outputs - commented out as index already exists
# output "mongodb_vector_search_index_id" {
#   description = "MongoDB Atlas Vector Search Index ID"
#   value = mongodbatlas_search_index.vector_search.id
# }

# output "mongodb_vector_search_index_status" {
#   description = "MongoDB Atlas Vector Search Index status"
#   value = mongodbatlas_search_index.vector_search.status
# }

output "flink_service_account_id" {
  value = confluent_service_account.flink.id
}

output "mongodb_sink_connector_id" {
  description = "MongoDB Sink Connector ID"
  value = confluent_connector.mongodb_sink.id
}

output "mongodb_sink_connector_status" {
  description = "MongoDB Sink Connector Status"
  value = confluent_connector.mongodb_sink.status
}
