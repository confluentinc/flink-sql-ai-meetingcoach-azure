#!/usr/bin/env python3
"""
publish-to-topic.py - Publishes messages to the messages_prospect Confluent Kafka topic in Avro format
"""

import os
import uuid
import signal
import sys
import socket
import json
import subprocess
from pathlib import Path
from confluent_kafka import Producer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer
from confluent_kafka.serialization import SerializationContext, MessageField

# Configuration - Topic name (change this if needed)
TOPIC = 'messages_prospect'

def load_credentials_from_tfstate():
    """Load Kafka and Schema Registry credentials from Terraform state file"""
    tfstate_path = Path(__file__).parent.parent.parent / 'terraform' / 'terraform.tfstate'

    if not tfstate_path.exists():
        print(f"Terraform state file not found at {tfstate_path}")
        return {}

    try:
        with open(tfstate_path, 'r') as f:
            tfstate = json.load(f)

        credentials = {}

        # Extract from terraform state outputs - this is where the credentials are stored
        outputs = tfstate.get('outputs', {})

        # Extract environment info
        if 'environment_id' in outputs:
            credentials['environment_id'] = outputs['environment_id']['value']
            print(f"Found environment ID: {credentials['environment_id']}")

        # Extract Kafka credentials - prioritize OrganizationAdmin keys
        if 'kafka_api_key_org_admin' in outputs:
            credentials['kafka_api_key'] = outputs['kafka_api_key_org_admin']['value']
            print(f"Found Kafka API key (OrganizationAdmin): {credentials['kafka_api_key']}")
        elif 'kafka_api_key' in outputs:
            credentials['kafka_api_key'] = outputs['kafka_api_key']['value']
            print(f"Found Kafka API key (CloudClusterAdmin): {credentials['kafka_api_key']}")

        if 'kafka_api_secret_org_admin' in outputs:
            credentials['kafka_api_secret'] = outputs['kafka_api_secret_org_admin']['value']
            print(f"Found Kafka API secret (OrganizationAdmin): ***")
        elif 'kafka_api_secret' in outputs:
            credentials['kafka_api_secret'] = outputs['kafka_api_secret']['value']
            print(f"Found Kafka API secret (CloudClusterAdmin): ***")

        if 'kafka_bootstrap_endpoint' in outputs:
            bootstrap_endpoint = outputs['kafka_bootstrap_endpoint']['value']
            if bootstrap_endpoint.startswith('SASL_SSL://'):
                credentials['bootstrap_servers'] = bootstrap_endpoint[11:]  # Remove SASL_SSL:// prefix (11 chars)
            else:
                credentials['bootstrap_servers'] = bootstrap_endpoint
            print(f"Found bootstrap servers: {credentials['bootstrap_servers']}")

        # Extract Schema Registry credentials - prioritize OrganizationAdmin keys
        if 'schema_registry_api_key_org_admin' in outputs:
            credentials['sr_api_key'] = outputs['schema_registry_api_key_org_admin']['value']
            print(f"Found Schema Registry API key (OrganizationAdmin): {credentials['sr_api_key']}")
        elif 'schema_registry_api_key' in outputs:
            credentials['sr_api_key'] = outputs['schema_registry_api_key']['value']
            print(f"Found Schema Registry API key (CloudClusterAdmin): {credentials['sr_api_key']}")

        if 'schema_registry_api_secret_org_admin' in outputs:
            credentials['sr_api_secret'] = outputs['schema_registry_api_secret_org_admin']['value']
            print(f"Found Schema Registry API secret (OrganizationAdmin): ***")
        elif 'schema_registry_api_secret' in outputs:
            credentials['sr_api_secret'] = outputs['schema_registry_api_secret']['value']
            print(f"Found Schema Registry API secret (CloudClusterAdmin): ***")

        # Schema Registry URL can be in multiple output keys
        for sr_url_key in ['schema_registry_url', 'schema_registry_endpoint']:
            if sr_url_key in outputs:
                credentials['schema_registry_url'] = outputs[sr_url_key]['value']
                print(f"Found Schema Registry URL: {credentials['schema_registry_url']}")
                break

        # Also check resources section for Schema Registry info if not in outputs
        if 'schema_registry_url' not in credentials:
            for resource in tfstate.get('resources', []):
                if resource.get('type') == 'confluent_schema_registry_cluster':
                    instances = resource.get('instances', [])
                    for instance in instances:
                        attributes = instance.get('attributes', {})
                        rest_endpoint = attributes.get('rest_endpoint')
                        if rest_endpoint:
                            credentials['schema_registry_url'] = rest_endpoint
                            print(f"Found Schema Registry URL in resources: {credentials['schema_registry_url']}")
                            break

        return credentials

    except Exception as e:
        print(f"Error reading Terraform state: {e}")
        return {}

def get_schema_via_cli(topic_name, environment_id):
    """Get schema ID and schema string using Confluent CLI"""
    try:
        # Set up environment for confluent CLI
        env = os.environ.copy()

        # Try to get schema using confluent CLI
        subject_name = f"{topic_name}-value"
        cmd = ["confluent", "schema-registry", "schema", "describe", subject_name, "--environment", environment_id]

        print(f"Attempting to get schema for {subject_name} using Confluent CLI...")
        result = subprocess.run(cmd, capture_output=True, text=True, env=env)

        if result.returncode == 0:
            # Parse the CLI output to extract schema ID and schema
            output = result.stdout
            schema_info = {}

            # Look for schema ID and schema content in the output
            for line in output.split('\n'):
                if 'Schema ID' in line or 'ID' in line:
                    # Extract ID number
                    import re
                    id_match = re.search(r'\d+', line)
                    if id_match:
                        schema_info['id'] = int(id_match.group())
                elif line.strip().startswith('{') and line.strip().endswith('}'):
                    # This looks like the schema JSON
                    try:
                        schema_info['schema'] = json.loads(line.strip())
                    except json.JSONDecodeError:
                        pass

            if 'id' in schema_info and 'schema' in schema_info:
                print(f"✅ Retrieved schema via CLI - ID: {schema_info['id']}")
                return schema_info['id'], json.dumps(schema_info['schema'])
            else:
                print(f"⚠️  Could not parse schema info from CLI output")
                return None, None
        else:
            print(f"⚠️  CLI failed to get schema: {result.stderr}")
            return None, None

    except Exception as e:
        print(f"⚠️  Error using Confluent CLI: {e}")
        return None, None

def ensure_schema_via_cli(topic_name, environment_id, schema_str):
    """Ensure schema exists using Confluent CLI, create if necessary"""
    try:
        # First try to get existing schema
        schema_id, existing_schema = get_schema_via_cli(topic_name, environment_id)

        if schema_id and existing_schema:
            return schema_id, existing_schema

        print(f"Schema doesn't exist for {topic_name}, attempting to create via CLI...")

        # Try to create the schema using confluent CLI
        subject_name = f"{topic_name}-value"

        # Write schema to temp file
        import tempfile
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            f.write(schema_str)
            schema_file = f.name

        try:
            cmd = ["confluent", "schema-registry", "schema", "create",
                   "--subject", subject_name,
                   "--schema", schema_file,
                   "--environment", environment_id]

            result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode == 0:
                print(f"✅ Created schema via CLI")
                # Get the newly created schema
                return get_schema_via_cli(topic_name, environment_id)
            else:
                print(f"⚠️  Failed to create schema via CLI: {result.stderr}")
                return None, None

        finally:
            # Clean up temp file
            os.unlink(schema_file)

    except Exception as e:
        print(f"⚠️  Error ensuring schema via CLI: {e}")
        return None, None

# Load credentials from Terraform state
tf_credentials = load_credentials_from_tfstate()

# Load environment variables from the .env file as fallback
env_file = Path(__file__).parent.parent.parent / 'terraform' / '.env'
if env_file.exists():
    print(f"Loading additional configuration from {env_file}")
    with open(env_file, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                try:
                    key, value = line.split('=', 1)
                    os.environ[key] = value
                except ValueError:
                    pass

# Configuration - prioritize Terraform state, fallback to environment variables
BOOTSTRAP_SERVERS = tf_credentials.get('bootstrap_servers') or os.getenv('KAFKA_BOOTSTRAP_SERVERS')
if not BOOTSTRAP_SERVERS:
    print("❌ Error: Kafka bootstrap servers not found in Terraform state or environment variables")
    print("Please ensure Terraform has been applied successfully or set KAFKA_BOOTSTRAP_SERVERS environment variable")
    sys.exit(1)

# Strip the "SASL_SSL://" prefix if present
if BOOTSTRAP_SERVERS.startswith("SASL_SSL://"):
    BOOTSTRAP_SERVERS = BOOTSTRAP_SERVERS[10:]

SCHEMA_REGISTRY_URL = tf_credentials.get('schema_registry_url') or os.getenv('SCHEMA_REGISTRY_URL')
if not SCHEMA_REGISTRY_URL:
    print("❌ Error: Schema Registry URL not found in Terraform state or environment variables")
    print("Please ensure Terraform has been applied successfully or set SCHEMA_REGISTRY_URL environment variable")
    sys.exit(1)

# Authentication - prioritize Terraform state, fallback to environment variables
SASL_USERNAME = tf_credentials.get('kafka_api_key') or os.getenv('SCRIPT_KAFKA_API_KEY', os.getenv('confluent_cloud_api_key'))
SASL_PASSWORD = tf_credentials.get('kafka_api_secret') or os.getenv('SCRIPT_KAFKA_API_SECRET', os.getenv('confluent_cloud_api_secret'))
SR_API_KEY = tf_credentials.get('sr_api_key') or os.getenv('SCHEMA_REGISTRY_API_KEY')
SR_API_SECRET = tf_credentials.get('sr_api_secret') or os.getenv('SCHEMA_REGISTRY_API_SECRET')
ENVIRONMENT_ID = tf_credentials.get('environment_id') or os.getenv('TF_VAR_environment_id')

# Print the configuration for debugging
print(f"Using Kafka bootstrap servers: {BOOTSTRAP_SERVERS}")
print(f"Using Schema Registry URL: {SCHEMA_REGISTRY_URL}")
print(f"SASL Username: {SASL_USERNAME}")
print(f"SASL Password: {'***' if SASL_PASSWORD else 'None'}")
print(f"SR API Key: {SR_API_KEY}")
print(f"SR API Secret: {'***' if SR_API_SECRET else 'None'}")
print(f"Environment ID: {ENVIRONMENT_ID}")

# Check if we have the required credentials
if not SASL_USERNAME or not SASL_PASSWORD:
    print("ERROR: Missing Kafka API credentials (SASL_USERNAME/SASL_PASSWORD)")
    sys.exit(1)

if not SR_API_KEY or not SR_API_SECRET:
    print("ERROR: Missing Schema Registry API credentials (SR_API_KEY/SR_API_SECRET)")
    sys.exit(1)

# Setup producer configuration
producer_config = {
    'bootstrap.servers': BOOTSTRAP_SERVERS,
    'security.protocol': 'SASL_SSL',
    'sasl.mechanisms': 'PLAIN',
    'sasl.username': SASL_USERNAME,
    'sasl.password': SASL_PASSWORD,
    'client.id': f'python-producer-{socket.gethostname()}'
}

# Setup schema registry configuration
schema_registry_conf = {
    'url': SCHEMA_REGISTRY_URL,
    'basic.auth.user.info': f"{SR_API_KEY}:{SR_API_SECRET}"
}

def delivery_report(err, msg):
    """Called once for each message produced to indicate delivery result."""
    if err is not None:
        print(f'Message delivery failed: {err}')
    else:
        print(f'Message delivered to {msg.topic()} [{msg.partition()}] at offset {msg.offset()}')

def signal_handler(sig, frame):
    print("\nInterrupted by user, shutting down...")
    sys.exit(0)

def main():
    # Set up signal handler for graceful shutdown
    signal.signal(signal.SIGINT, signal_handler)

    # Create the schema registry client
    print("Connecting to Schema Registry...")
    schema_registry_client = SchemaRegistryClient(schema_registry_conf)
    print("Schema Registry connected successfully")

    # Define the known schema for messages_prospect topic based on Flink SQL definition
    fallback_schema_str = """{
        "type": "record",
        "name": "messages_conversation_value",
        "namespace": "org.apache.flink.avro.generated.record",
        "fields": [
            {"name": "message", "type": ["null", "string"], "default": null},
            {"name": "speaker", "type": ["null", "string"], "default": null}
        ]
    }"""

    # Try to get schema via Confluent CLI first
    if ENVIRONMENT_ID:
        print(f"Attempting to get schema via Confluent CLI...")
        schema_id, schema_str = get_schema_via_cli(TOPIC, ENVIRONMENT_ID)

        if not schema_id:
            print(f"Schema not found, attempting to create via CLI...")
            schema_id, schema_str = ensure_schema_via_cli(TOPIC, ENVIRONMENT_ID, fallback_schema_str)

        if schema_id and schema_str:
            print(f"✅ Using schema ID {schema_id} from CLI")
        else:
            print(f"⚠️  CLI approach failed, falling back to Schema Registry client")
            schema_str = fallback_schema_str
    else:
        print(f"⚠️  No environment ID found, using fallback schema")
        schema_str = fallback_schema_str

    # Create the Avro serializer with specific configuration to avoid auto-registration
    try:
        # Configure serializer to NOT auto-register schemas
        serializer_config = {
            'auto.register.schemas': False,
            'use.latest.version': True,
            'normalize.schemas': False
        }

        # If we got a schema ID from CLI, use it
        if 'schema_id' in locals() and schema_id:
            serializer_config['schema.id'] = schema_id
            print(f"Using explicit schema ID: {schema_id}")

        avro_serializer = AvroSerializer(
            schema_registry_client,
            schema_str,
            lambda record, ctx: record,
            serializer_config
        )
        print(f"✅ Avro serializer created successfully with config: {serializer_config}")
    except Exception as e:
        print(f"❌ Failed to create Avro serializer: {e}")
        print("This could be due to Schema Registry permissions or the schema not existing.")
        print("Try running the Flink SQL statements first to create the topic and schema.")
        sys.exit(1)

    # Create Kafka producer
    print("Connecting to Kafka...")
    producer = Producer(producer_config)
    print("Kafka producer connected successfully")

    print(f"Producer initialized. Publishing messages to '{TOPIC}'")
    print("Enter your message below (Ctrl+C to exit):")

    try:
        # Main message loop
        while True:
            # Get user input
            try:
                user_input = input("> ")
            except EOFError:
                print("EOF detected, using test message instead.")
                user_input = "Test message due to EOF"

            if not user_input:
                continue

            # Create the message object according to our schema
            # Note: Using the exact structure Flink expects
            # All messages sent by user should have speaker as 'prospect'
            message = {
                "message": user_input,
                "speaker": "prospect"
            }

            print(f"Sending message: {message}")

            try:
                # Serialize the message using Avro
                serialized_value = avro_serializer(
                    message,
                    SerializationContext(TOPIC, MessageField.VALUE)
                )

                # Create a unique key
                key = str(uuid.uuid4()).encode('utf-8')

                # Produce the message to Kafka
                producer.produce(
                    topic=TOPIC,
                    key=key,
                    value=serialized_value,
                    callback=delivery_report
                )

                # Flush to ensure delivery
                producer.poll(0)
            except Exception as e:
                import traceback
                traceback.print_exc()
                print(f"Error producing message: {e}")

    except KeyboardInterrupt:
        print("\nProducer interrupted.")
    finally:
        # Final flush to make sure all messages are sent
        remaining = producer.flush(timeout=10)
        if remaining > 0:
            print(f"Warning: {remaining} messages may not have been delivered")

        print("Producer shut down.")

if __name__ == "__main__":
    main()
