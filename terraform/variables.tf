# ====================================================================
# MINIMAL VARIABLES FOR FRESH DEPLOYMENTS
# ====================================================================

# ====================================================================
# 1. REQUIRED CREDENTIALS (from .env)
# ====================================================================

# Confluent Cloud API credentials
variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key"
  type        = string
  sensitive   = true
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret"
  type        = string
  sensitive   = true
}

# Azure credentials
variable "azure_subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "azure_tenant_id" {
  description = "Azure Tenant ID"
  type        = string
}

variable "azure_client_id" {
  description = "Azure Client ID (Service Principal)"
  type        = string
}

variable "azure_client_secret" {
  description = "Azure Client Secret (Service Principal Secret)"
  type        = string
  sensitive   = true
}

# MongoDB Atlas credentials
variable "mongodbatlas_public_key" {
  description = "MongoDB Atlas Public API Key"
  type        = string
  sensitive   = true
}

variable "mongodbatlas_private_key" {
  description = "MongoDB Atlas Private API Key"
  type        = string
  sensitive   = true
}

variable "mongodbatlas_org_id" {
  description = "MongoDB Atlas Organization ID"
  type        = string
}

variable "mongodbatlas_project_id" {
  description = "MongoDB Atlas Project ID (for existing project)"
  type        = string
}

# ====================================================================
# 2. DEPLOYMENT CONFIGURATION (with good defaults)
# ====================================================================

variable "deployment_prefix" {
  description = "Unique prefix for all resources to avoid naming conflicts"
  type        = string
  default     = "flink-ml-demo"
}

variable "azure_location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

# Mapping from Azure regions to MongoDB Atlas regions
locals {
  # MongoDB Atlas Azure region names - M0 free tier requires eastus2
  mongodb_region_mapping = {
    "eastus"      = "EAST_US_2"         # Azure East US -> MongoDB Atlas East US 2 (M0 requirement)
    "eastus2"     = "EAST_US_2"         # Azure East US 2 -> MongoDB Atlas East US 2
    "westus"      = "WEST_US"           # Azure West US -> MongoDB Atlas West US
    "westus2"     = "WEST_US_2"         # Azure West US 2 -> MongoDB Atlas West US 2
    "centralus"   = "CENTRAL_US"        # Azure Central US -> MongoDB Atlas Central US
    "northeurope" = "EUROPE_NORTH"      # Azure North Europe -> MongoDB Atlas Europe North
    "westeurope"  = "EUROPE_WEST"       # Azure West Europe -> MongoDB Atlas Europe West
  }

  mongodb_region = lookup(local.mongodb_region_mapping, var.azure_location, "EAST_US_2")
}

variable "confluent_region" {
  description = "Confluent Cloud region (should match Azure region)"
  type        = string
  default     = "eastus"
}

# ====================================================================
# 3. RESOURCE NAMING (with good defaults)
# ====================================================================

# Confluent resources
variable "environment_name" {
  description = "Confluent Environment name"
  type        = string
  default     = "flink-ml-demo"
}

variable "kafka_cluster_name" {
  description = "Confluent Kafka Cluster name"
  type        = string
  default     = "demo-cluster"
}

variable "flink_compute_pool_name" {
  description = "Confluent Flink Compute Pool name"
  type        = string
  default     = "meeting-coach-flink"
}

# Azure resources
variable "resource_group_name" {
  description = "Azure Resource Group name (will be prefixed)"
  type        = string
  default     = "meeting-coach-resources"
}

variable "openai_service_name" {
  description = "Azure OpenAI Service name (will be prefixed)"
  type        = string
  default     = "meeting-coach-openai"
}

variable "openai_managed_identity" {
  description = "Whether to use managed identity for Azure OpenAI"
  type        = bool
  default     = true
}

# MongoDB Atlas resources
variable "mongodb_project_name" {
  description = "MongoDB Atlas project name"
  type        = string
  default     = "Meeting Coach Demo"
}

variable "mongodb_cluster_name" {
  description = "MongoDB Atlas cluster name"
  type        = string
  default     = "aimeetingcoach"
}

variable "mongodb_connection_string" {
  description = "MongoDB Atlas connection string (e.g., mongodb+srv://cluster.xxx.mongodb.net)"
  type        = string
  sensitive   = true
}

variable "mongodb_username" {
  description = "MongoDB database username"
  type        = string
  default     = "demo-user"
}

variable "mongodb_password" {
  description = "MongoDB database password"
  type        = string
  sensitive   = true
  default     = "change-me-in-production"
}

variable "mongodb_database_name" {
  description = "MongoDB database name"
  type        = string
  default     = "knowledge_db"
}

variable "mongodb_collection_name" {
  description = "MongoDB collection name"
  type        = string
  default     = "knowledge_embeddings"
}

variable "mongodb_index_name" {
  description = "MongoDB vector search index name"
  type        = string
  default     = "vector_search_index"
}

variable "mongodb_embedding_column" {
  description = "MongoDB embedding column name"
  type        = string
  default     = "embedding"
}

variable "mongodb_num_candidates" {
  description = "Number of MongoDB vector search candidates"
  type        = number
  default     = 150
}

# ====================================================================
# 4. FLINK CONFIGURATION (for manual operations)
# ====================================================================

variable "catalog_name" {
  description = "Flink catalog name"
  type        = string
  default     = "Meeting-Coach-Demo"
}

variable "database_name" {
  description = "Flink database name"
  type        = string
  default     = "meeting-coach-cluster"
}

# ====================================================================
# 5. DYNAMIC VARIABLES (set by Terraform provider config)
# ====================================================================

# These are set by the Confluent provider and don't need to be in .env
variable "flink_api_key" {
  description = "Flink API key (auto-set by provider)"
  type        = string
  default     = ""
}

variable "flink_api_secret" {
  description = "Flink API secret (auto-set by provider)"
  type        = string
  default     = ""
}

variable "flink_rest_endpoint" {
  description = "Flink REST endpoint (auto-set by provider)"
  type        = string
  default     = ""
}

variable "organization_id" {
  description = "Confluent organization ID (auto-set by provider)"
  type        = string
  default     = ""
}

variable "environment_id" {
  description = "Confluent environment ID (auto-set by provider)"
  type        = string
  default     = ""
}

variable "flink_compute_pool_id" {
  description = "Flink compute pool ID (auto-set by provider)"
  type        = string
  default     = ""
}

variable "flink_principal_id" {
  description = "Flink principal ID (auto-set by provider)"
  type        = string
  default     = ""
}
