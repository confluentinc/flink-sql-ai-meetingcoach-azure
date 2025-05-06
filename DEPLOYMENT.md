# 🚀 Fresh Deployment Guide - Flink ML Demo

This guide helps you deploy the complete Flink ML Demo infrastructure from scratch with **minimal credentials**.

## 📋 Prerequisites

You need accounts and API credentials for:
1. **Confluent Cloud** (for Kafka + Flink)
2. **Microsoft Azure** (for OpenAI services)
3. **MongoDB Atlas** (for vector database)

⚠️ **MongoDB Atlas M2 Shared Tier**
- This deployment uses **MongoDB Atlas M2 shared tier** (smallest tier available via Terraform)
- **Payment information required** - M2 costs ~$9/month (very affordable for demo)
- **Note**: M0 free tier cannot be created via Terraform API - must be created manually in Atlas UI
- Alternative: Create M0 manually in Atlas UI, then import into Terraform with `terraform import`
- M2 supports full vector search with up to 5 search indexes per cluster

## 🔑 Step 1: Get Required Credentials

### Confluent Cloud API Keys
1. Go to [Confluent Cloud](https://confluent.cloud/settings/api-keys)
2. Create a new **Cloud API Key** (not cluster-specific)
3. Note down: `API Key` and `API Secret`

### Azure Service Principal
1. Go to [Azure Portal](https://portal.azure.com) > App registrations
2. Create a new app registration
3. Go to "Certificates & secrets" > New client secret
4. Go to "Subscriptions" > Your subscription > Access control (IAM)
5. Add role assignment: "Contributor" for your app
6. Note down: `Subscription ID`, `Tenant ID`, `Client ID`, `Client Secret`

### MongoDB Atlas API Keys
1. Go to [MongoDB Atlas](https://cloud.mongodb.com) > Access Manager > API Keys
2. Create new **Organization API Key** with "Project Creator" permissions
3. Note down: `Public Key`, `Private Key`, and your `Organization ID`

## 🛠️ Step 2: Configure Environment

1. **Copy the template:**
   ```bash
   cp .env.template .env
   ```

2. **Edit .env with your credentials:**
   ```bash
   # Required credentials only
   CONFLUENT_CLOUD_API_KEY=your-confluent-cloud-api-key
   CONFLUENT_CLOUD_API_SECRET=your-confluent-cloud-api-secret

   AZURE_SUBSCRIPTION_ID=your-azure-subscription-id
   AZURE_TENANT_ID=your-azure-tenant-id
   AZURE_CLIENT_ID=your-service-principal-client-id
   AZURE_CLIENT_SECRET=your-service-principal-client-secret

   MONGODBATLAS_PUBLIC_KEY=your-mongodb-atlas-public-key
   MONGODBATLAS_PRIVATE_KEY=your-mongodb-atlas-private-key
   MONGODBATLAS_ORG_ID=your-mongodb-atlas-org-id

   # Optional - will get defaults if not set
   DEPLOYMENT_PREFIX=my-unique-prefix
   AZURE_REGION=eastus  # All resources use this region (MongoDB auto-maps to EAST_US)
   MONGODB_USERNAME=demo-user
   MONGODB_PASSWORD=secure-password-123
   ```

## 🚀 Step 3: Deploy Infrastructure

1. **Initialize Terraform:**
   ```bash
   cd terraform
   terraform init
   ```

2. **Load environment variables:**
   ```bash
   source ./load_tf_vars.sh
   ```

3. **Plan deployment:**
   ```bash
   terraform plan
   ```

4. **Deploy everything:**
   ```bash
   terraform apply
   ```

## 📊 Step 4: Get Connection Info

After successful deployment, Terraform will output all the connection details:

```bash
# Get all outputs
terraform output

# Get specific connection strings (for your applications)
terraform output -raw mongodb_connection_string
terraform output -raw azure_openai_endpoint
terraform output -raw kafka_bootstrap_endpoint
```

## 🔗 Step 5: Manual Flink Configuration

The infrastructure is now ready! For Flink SQL statements, you'll need to:

1. **Create connections manually** (one-time setup):
   ```bash
   # Use the outputs from terraform to create these connections
   confluent flink connection create azure-openai-embedding-connection \
     --cloud azure --region eastus --type azureopenai \
     --endpoint $(terraform output -raw azure_openai_endpoint) \
     --environment $(terraform output -raw confluent_environment_id)

   confluent flink connection create mongodb-connection \
     --cloud azure --region eastus --type mongodb \
     --endpoint $(terraform output -raw mongodb_connection_string) \
     --environment $(terraform output -raw confluent_environment_id)
   ```

2. **Create your Flink statements** via Confluent Cloud UI or CLI

## 🧹 Cleanup

To destroy all resources:
```bash
terraform destroy
```

## 🎯 What Gets Created

This Terraform creates **everything from scratch**:

### Confluent Cloud
- ✅ New environment
- ✅ Kafka cluster with all topics
- ✅ Flink compute pool
- ✅ Service accounts and API keys
- ✅ MongoDB sink connector

### Azure
- ✅ Resource group
- ✅ OpenAI service
- ✅ Text embedding model deployment
- ✅ GPT-4 completion model deployment

### MongoDB Atlas
- ✅ New project
- ✅ M10 cluster with vector search support
- ✅ Database user with proper permissions
- ✅ Vector search index (1536 dimensions for OpenAI)
- ✅ IP allowlist for access

## 🔒 Security Notes

- All resources use proper authentication
- MongoDB allows all IPs by default (restrict in production)
- Azure OpenAI uses managed identity
- All sensitive outputs are marked as sensitive

## 🆘 Troubleshooting

**"Resource already exists" errors:**
- Change your `DEPLOYMENT_PREFIX` in .env to something unique

**MongoDB connection issues:**
- Wait 2-3 minutes after cluster creation for it to be fully ready
- Check that your IP is in the access list

**Azure permission errors:**
- Ensure your service principal has "Contributor" role on the subscription
- Check that the Azure region supports OpenAI services

**Confluent connection errors:**
- Verify your Cloud API key has organization-level permissions
- Use the exact resource IDs from terraform outputs
