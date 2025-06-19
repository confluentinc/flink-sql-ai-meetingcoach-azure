#!/usr/bin/env python3
"""
Knowledge Document Publisher for Confluent Kafka

This script publishes knowledge documents from the sample-data/knowledge_base_json/
directory to the 'knowledge' topic in Confluent Kafka, using the same configuration
approach as the app/utils scripts.

Usage:
    python publish_knowledge_documents.py

Requirements:
    - Run from the terraform-regional-test directory
    - Ensure terraform.tfvars and .env-regional files are configured
    - Install required Python packages: confluent-kafka
"""

import json
import os
import sys
import uuid
from pathlib import Path
from confluent_kafka import Producer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer
from confluent_kafka.serialization import SerializationContext, MessageField

def load_terraform_vars():
    """Load configuration from terraform.tfvars file"""
    tfvars_path = Path(__file__).parent / 'terraform.tfvars'

    if not tfvars_path.exists():
        print(f"❌ terraform.tfvars file not found at {tfvars_path}")
        return {}

    config = {}
    try:
        with open(tfvars_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip().strip('"')
                    config[key] = value
        print("✅ Loaded configuration from terraform.tfvars")
        return config
    except Exception as e:
        print(f"❌ Error reading terraform.tfvars: {e}")
        return {}

def load_env_regional():
    """Load environment variables from .env-regional file"""
    env_path = Path(__file__).parent / '.env-regional'

    if not env_path.exists():
        print(f"❌ .env-regional file not found at {env_path}")
        return {}

    config = {}
    try:
        with open(env_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip().strip('"')
                    config[key] = value
        print("✅ Loaded configuration from .env-regional")
        return config
    except Exception as e:
        print(f"❌ Error reading .env-regional: {e}")
        return {}

def load_terraform_state():
    """Load Kafka configuration from Terraform state file"""
    tfstate_path = Path(__file__).parent / 'terraform.tfstate'

    if not tfstate_path.exists():
        print(f"❌ terraform.tfstate file not found at {tfstate_path}")
        return {}

    try:
        with open(tfstate_path, 'r') as f:
            tfstate = json.load(f)

        credentials = {}
        outputs = tfstate.get('outputs', {})

        # Extract Kafka credentials
        if 'kafka_api_key_org_admin' in outputs:
            credentials['kafka_api_key'] = outputs['kafka_api_key_org_admin']['value']
        elif 'kafka_api_key' in outputs:
            credentials['kafka_api_key'] = outputs['kafka_api_key']['value']

        if 'kafka_api_secret_org_admin' in outputs:
            credentials['kafka_api_secret'] = outputs['kafka_api_secret_org_admin']['value']
        elif 'kafka_api_secret' in outputs:
            credentials['kafka_api_secret'] = outputs['kafka_api_secret']['value']

        if 'kafka_bootstrap_endpoint' in outputs:
            bootstrap_endpoint = outputs['kafka_bootstrap_endpoint']['value']
            if bootstrap_endpoint.startswith('SASL_SSL://'):
                credentials['bootstrap_servers'] = bootstrap_endpoint[11:]
            else:
                credentials['bootstrap_servers'] = bootstrap_endpoint

        # Extract Schema Registry credentials
        if 'schema_registry_api_key' in outputs:
            credentials['schema_registry_api_key'] = outputs['schema_registry_api_key']['value']
        if 'schema_registry_api_secret' in outputs:
            credentials['schema_registry_api_secret'] = outputs['schema_registry_api_secret']['value']
        if 'schema_registry_endpoint' in outputs:
            credentials['schema_registry_endpoint'] = outputs['schema_registry_endpoint']['value']

        print("✅ Loaded Kafka configuration from terraform.tfstate")
        return credentials

    except Exception as e:
        print(f"❌ Error reading terraform.tfstate: {e}")
        return {}

def get_kafka_config():
    """Get Kafka configuration from available sources"""
    tf_state = load_terraform_state()

    if not all(key in tf_state for key in ['kafka_api_key', 'kafka_api_secret', 'bootstrap_servers']):
        print("❌ Required Kafka credentials not found in terraform.tfstate")
        print("Please ensure Terraform has been applied successfully")
        return None, None

    producer_config = {
        'bootstrap.servers': tf_state['bootstrap_servers'],
        'security.protocol': 'SASL_SSL',
        'sasl.mechanisms': 'PLAIN',
        'sasl.username': tf_state['kafka_api_key'],
        'sasl.password': tf_state['kafka_api_secret'],
        'client.id': f'knowledge-publisher-{uuid.uuid4()}'
    }

    # Get Schema Registry configuration from terraform outputs
    schema_registry_config = {}
    if 'schema_registry_api_key' in tf_state and 'schema_registry_endpoint' in tf_state:
        schema_registry_config = {
            'url': tf_state['schema_registry_endpoint'],
            'basic.auth.user.info': f"{tf_state['schema_registry_api_key']}:{tf_state.get('schema_registry_api_secret', '')}"
        }

    return producer_config, schema_registry_config

# AVRO schema for knowledge documents
KNOWLEDGE_AVRO_SCHEMA = """
{
  "type": "record",
  "name": "Knowledge",
  "fields": [
    {"name": "document_id", "type": "string"},
    {"name": "document_name", "type": "string"},
    {"name": "document_category", "type": "string"},
    {"name": "document_text", "type": "string"}
  ]
}
"""

def delivery_report(err, msg):
    """Callback for message delivery reports"""
    if err is not None:
        print(f"❌ Message delivery failed: {err}")
    else:
        print(f"✅ Message delivered to {msg.topic()} [{msg.partition()}] at offset {msg.offset()}")

def dict_to_knowledge(knowledge_dict, ctx):
    """Convert dictionary to knowledge record for AVRO serialization"""
    return knowledge_dict

def load_knowledge_documents():
    """Load all JSON knowledge documents from the sample-data directory"""
    # Navigate to the sample-data directory from terraform-regional-test
    sample_data_path = Path(__file__).parent.parent / 'sample-data' / 'knowledge_base_json'

    if not sample_data_path.exists():
        print(f"❌ Knowledge base directory not found at {sample_data_path}")
        return []

    documents = []

    # Recursively find all JSON files
    for json_file in sample_data_path.rglob('*.json'):
        try:
            with open(json_file, 'r', encoding='utf-8') as f:
                document_data = json.load(f)

            # Add metadata about the source file
            document_data['source_file'] = str(json_file.relative_to(sample_data_path))
            document_data['source_category'] = json_file.parent.name

            documents.append(document_data)
            print(f"📄 Loaded: {json_file.relative_to(sample_data_path)}")

        except Exception as e:
            print(f"❌ Error loading {json_file}: {e}")

    print(f"📚 Loaded {len(documents)} knowledge documents")
    return documents

def publish_documents_to_kafka(producer, avro_serializer, documents, topic='knowledge'):
    """Publish documents to the knowledge topic using AVRO format"""
    print(f"🚀 Publishing {len(documents)} documents to topic '{topic}' in AVRO format...")

    success_count = 0
    error_count = 0

    for i, document in enumerate(documents, 1):
        try:
            # Generate unique key for each document
            key = str(uuid.uuid4()).encode('utf-8')

            # Transform document to match Flink table schema
            flink_document = {
                "document_id": document.get('source_file', f"doc_{i}"),
                "document_name": document.get('title', document.get('name', 'Unknown Document')),
                "document_category": document.get('source_category', 'general'),
                "document_text": document.get('content', document.get('text', str(document)))
            }

            # Serialize to AVRO
            serialization_context = SerializationContext(topic, MessageField.VALUE)
            serialized_value = avro_serializer(flink_document, serialization_context)

            # Produce message
            producer.produce(
                topic=topic,
                key=key,
                value=serialized_value,
                callback=delivery_report
            )

            # Poll for delivery reports periodically
            if i % 10 == 0:
                producer.poll(0)

            success_count += 1
            print(f"📤 [{i}/{len(documents)}] Queued: {flink_document['document_id']}")

        except Exception as e:
            print(f"❌ Error publishing document {i}: {e}")
            error_count += 1

    # Wait for all messages to be delivered
    print("⏳ Waiting for all messages to be delivered...")
    producer.flush()

    print(f"✅ Publishing complete! Success: {success_count}, Errors: {error_count}")

def main():
    """Main function"""
    print("🎯 Knowledge Document Publisher for Confluent Kafka")
    print("=" * 60)

    # Load configuration
    print("📋 Loading configuration...")

    # Get Kafka and Schema Registry configuration
    kafka_config, schema_registry_config = get_kafka_config()
    if not kafka_config:
        print("❌ Cannot proceed without Kafka configuration")
        sys.exit(1)

    if not schema_registry_config:
        print("❌ Cannot proceed without Schema Registry configuration")
        sys.exit(1)

    # Load knowledge documents
    print("\n📚 Loading knowledge documents...")
    documents = load_knowledge_documents()

    if not documents:
        print("❌ No documents found to publish")
        sys.exit(1)

    # Create Schema Registry client and AVRO serializer
    print("\n🔌 Initializing Schema Registry client and AVRO serializer...")
    try:
        schema_registry_client = SchemaRegistryClient(schema_registry_config)
        avro_serializer = AvroSerializer(
            schema_registry_client,
            KNOWLEDGE_AVRO_SCHEMA,
            dict_to_knowledge
        )
        print("✅ Schema Registry client and AVRO serializer initialized")
    except Exception as e:
        print(f"❌ Error initializing Schema Registry: {e}")
        sys.exit(1)

    # Create Kafka producer
    print("\n🔌 Initializing Kafka producer...")
    try:
        producer = Producer(kafka_config)
        print("✅ Kafka producer initialized")
    except Exception as e:
        print(f"❌ Error initializing Kafka producer: {e}")
        sys.exit(1)

    # Publish documents
    print("\n🚀 Starting publication process...")
    try:
        publish_documents_to_kafka(producer, avro_serializer, documents)
        print("\n🎉 All documents published successfully!")
    except Exception as e:
        print(f"❌ Error during publication: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
