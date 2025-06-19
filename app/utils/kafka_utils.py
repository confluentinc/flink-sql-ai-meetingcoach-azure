"""
Kafka Utility Functions for the Meeting Coach Application
"""

import json
import os
import uuid
import socket
import threading
import subprocess
from pathlib import Path
from confluent_kafka import Producer, Consumer, KafkaError
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer, AvroDeserializer
from confluent_kafka.serialization import SerializationContext, MessageField

def load_credentials_from_tfstate():
    """Load Kafka and Schema Registry credentials from Terraform state file"""
    # Look for terraform state file relative to the app directory
    tfstate_path = Path(__file__).parent.parent.parent / 'terraform' / 'terraform.tfstate'

    if not tfstate_path.exists():
        print(f"Terraform state file not found at {tfstate_path}")
        return {}

    try:
        with open(tfstate_path, 'r') as f:
            tfstate = json.load(f)

        credentials = {}

        # Extract from terraform state outputs
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
                credentials['bootstrap_servers'] = bootstrap_endpoint[11:]  # Remove SASL_SSL:// prefix
            else:
                credentials['bootstrap_servers'] = bootstrap_endpoint
            print(f"Found bootstrap servers: {credentials['bootstrap_servers']}")

        # Extract Schema Registry credentials - check resources for new OrganizationAdmin keys
        org_admin_sr_key = None
        org_admin_sr_secret = None

        # Check resources for the new OrganizationAdmin Schema Registry API key
        for resource in tfstate.get('resources', []):
            if (resource.get('type') == 'confluent_api_key' and
                resource.get('name') == 'schema_registry_org_admin'):
                instances = resource.get('instances', [])
                for instance in instances:
                    attributes = instance.get('attributes', {})
                    if attributes.get('id') and attributes.get('secret'):
                        org_admin_sr_key = attributes.get('id')
                        org_admin_sr_secret = attributes.get('secret')
                        print(f"Found Schema Registry API key (OrganizationAdmin from resources): {org_admin_sr_key}")
                        break

        # Prioritize OrganizationAdmin, then outputs, then fallback
        if org_admin_sr_key and org_admin_sr_secret:
            credentials['sr_api_key'] = org_admin_sr_key
            credentials['sr_api_secret'] = org_admin_sr_secret
            print(f"Using Schema Registry API key (OrganizationAdmin): {credentials['sr_api_key']}")
        elif 'schema_registry_api_key_org_admin' in outputs:
            credentials['sr_api_key'] = outputs['schema_registry_api_key_org_admin']['value']
            credentials['sr_api_secret'] = outputs['schema_registry_api_secret_org_admin']['value']
            print(f"Found Schema Registry API key (OrganizationAdmin): {credentials['sr_api_key']}")
        elif 'schema_registry_api_key' in outputs:
            credentials['sr_api_key'] = outputs['schema_registry_api_key']['value']
            credentials['sr_api_secret'] = outputs['schema_registry_api_secret']['value']
            print(f"Found Schema Registry API key (CloudClusterAdmin): {credentials['sr_api_key']}")

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

# Load credentials from Terraform state first, fallback to environment variables
tf_credentials = load_credentials_from_tfstate()

# Global variables for Kafka configuration - prioritize Terraform state, then system env
BOOTSTRAP_SERVERS = tf_credentials.get('bootstrap_servers') or os.getenv('KAFKA_BOOTSTRAP_SERVERS')
SCHEMA_REGISTRY_URL = tf_credentials.get('schema_registry_url') or os.getenv('SCHEMA_REGISTRY_URL')
SASL_USERNAME = tf_credentials.get('kafka_api_key') or os.getenv('KAFKA_API_KEY')
SASL_PASSWORD = tf_credentials.get('kafka_api_secret') or os.getenv('KAFKA_API_SECRET')
SR_API_KEY = tf_credentials.get('sr_api_key') or os.getenv('SCHEMA_REGISTRY_API_KEY')
SR_API_SECRET = tf_credentials.get('sr_api_secret') or os.getenv('SCHEMA_REGISTRY_API_SECRET')
ENVIRONMENT_ID = tf_credentials.get('environment_id') or os.getenv('TF_VAR_environment_id')

# Print configuration for debugging
print(f"Using Kafka bootstrap servers: {BOOTSTRAP_SERVERS}")
print(f"Using Schema Registry URL: {SCHEMA_REGISTRY_URL}")
print(f"SASL Username: {SASL_USERNAME}")
print(f"SASL Password: {'***' if SASL_PASSWORD else 'None'}")
print(f"SR API Key: {SR_API_KEY}")
print(f"SR API Secret: {'***' if SR_API_SECRET else 'None'}")
print(f"Environment ID: {ENVIRONMENT_ID}")

# Check if credentials are available
if not all([BOOTSTRAP_SERVERS, SCHEMA_REGISTRY_URL, SASL_USERNAME, SASL_PASSWORD, SR_API_KEY, SR_API_SECRET]):
    print("WARNING: Required Kafka credentials not found.")
    missing = []
    if not BOOTSTRAP_SERVERS: missing.append("BOOTSTRAP_SERVERS")
    if not SCHEMA_REGISTRY_URL: missing.append("SCHEMA_REGISTRY_URL")
    if not SASL_USERNAME: missing.append("KAFKA_API_KEY")
    if not SASL_PASSWORD: missing.append("KAFKA_API_SECRET")
    if not SR_API_KEY: missing.append("SCHEMA_REGISTRY_API_KEY")
    if not SR_API_SECRET: missing.append("SCHEMA_REGISTRY_API_SECRET")
    print(f"Missing credentials: {missing}")
    print("Credentials are automatically loaded from terraform/terraform.tfstate")

# Kafka Topic Names
INPUT_TOPIC = 'messages_prospect'
OUTPUT_TOPIC = 'messages_prospect_rag_llm_response'

# Kafka producer configuration
producer_config = {
    'bootstrap.servers': BOOTSTRAP_SERVERS,
    'security.protocol': 'SASL_SSL',
    'sasl.mechanisms': 'PLAIN',
    'sasl.username': SASL_USERNAME,
    'sasl.password': SASL_PASSWORD,
    'client.id': f'python-producer-{socket.gethostname()}'
}

# Kafka consumer configuration
consumer_config = {
    'bootstrap.servers': BOOTSTRAP_SERVERS,
    'security.protocol': 'SASL_SSL',
    'sasl.mechanisms': 'PLAIN',
    'sasl.username': SASL_USERNAME,
    'sasl.password': SASL_PASSWORD,
    'group.id': f'meeting-coach-consumer-{uuid.uuid4()}',
    'auto.offset.reset': 'latest',
    'enable.auto.commit': True,
    'client.id': f'python-consumer-{socket.gethostname()}',
    'isolation.level': 'read_uncommitted'
}

# Schema registry configuration
schema_registry_conf = {
    'url': SCHEMA_REGISTRY_URL,
    'basic.auth.user.info': f"{SR_API_KEY}:{SR_API_SECRET}"
}

# Initialize Kafka producer
producer = None
consumer_running = True

# Initialize Kafka
def initialize_kafka():
    global producer
    producer = Producer(producer_config)
    print("Kafka producer initialized")
    return producer

# Callback for message delivery reports
def delivery_report(err, msg):
    if err is not None:
        print(f"Message delivery failed: {err}")
    else:
        print(f"Message delivered to {msg.topic()} [{msg.partition()}] at offset {msg.offset()}")

# Function to send a message to Kafka
def send_to_kafka(message, speaker="prospect"):
    global producer
    if producer is None:
        initialize_kafka()

    try:
        # Create a schema registry client
        schema_registry_client = SchemaRegistryClient(schema_registry_conf)

        # Try to get the schema that Flink is using
        try:
            schema_metadata = schema_registry_client.get_latest_version(f"{INPUT_TOPIC}-value")
            schema_str = schema_metadata.schema.schema_str
            print(f"Retrieved schema from Schema Registry: {schema_str}")
        except Exception as e:
            print(f"Error retrieving schema from Schema Registry: {e}")
            # Fallback to a default schema
            schema_str = """
            {
                "type": "record",
                "name": "messages_conversation_value",
                "namespace": "org.apache.flink.avro.generated.record",
                "fields": [
                    {"name": "message", "type": ["null", "string"], "default": null},
                    {"name": "speaker", "type": ["null", "string"], "default": null}
                ]
            }
            """
            print(f"Using fallback schema: {schema_str}")

        # Create an Avro serializer with no auto-registration
        serializer_config = {
            'auto.register.schemas': False,
            'use.latest.version': True,
            'normalize.schemas': False
        }

        avro_serializer = AvroSerializer(
            schema_registry_client,
            schema_str,
            lambda record, ctx: record,  # Identity function
            serializer_config
        )

        # Create the message with the right schema format
        message_obj = {
            "message": message,
            "speaker": speaker
        }

        # Serialize the message
        serialized_value = avro_serializer(
            message_obj,
            SerializationContext(INPUT_TOPIC, MessageField.VALUE)
        )

        # Generate a unique key
        key = str(uuid.uuid4()).encode('utf-8')

        # Produce the message to Kafka
        producer.produce(
            topic=INPUT_TOPIC,
            key=key,
            value=serialized_value,
            callback=delivery_report
        )

        # Poll to handle delivery reports
        producer.poll(0)

        return {"status": "success", "message": "Message sent to Kafka"}
    except Exception as e:
        print(f"Error sending to Kafka: {e}")
        return {"status": "error", "message": str(e)}

# Function to consume messages from Kafka and broadcast to WebSockets
def consume_from_kafka(clients_set):
    try:
        # Create a consumer
        consumer = Consumer(consumer_config)

        # Subscribe to the output topic
        consumer.subscribe([OUTPUT_TOPIC])
        print(f"Consumer subscribed to {OUTPUT_TOPIC}")

        # Create a schema registry client
        schema_registry_client = SchemaRegistryClient(schema_registry_conf)

        # Try to get the schema
        try:
            schema_metadata = schema_registry_client.get_latest_version(f"{OUTPUT_TOPIC}-value")
            schema_str = schema_metadata.schema.schema_str
            print(f"Retrieved schema from Schema Registry: {schema_str}")
        except Exception as e:
            print(f"Error retrieving schema from Schema Registry: {e}")
            # Fallback to a default schema
            schema_str = """
            {
                "type": "record",
                "name": "messages_prospect_rag_llm_response_value",
                "namespace": "org.apache.flink.avro.generated.record",
                "fields": [
                    {"name": "message", "type": ["null", "string"], "default": null},
                    {"name": "rag_results_string", "type": ["null", "string"], "default": null},
                    {"name": "coaching_response", "type": ["null", "string"], "default": null}
                ]
            }
            """
            print(f"Using fallback schema: {schema_str}")

        # Create an Avro deserializer
        def dict_to_llm_response(obj, ctx):
            """Convert deserialized dict back to object"""
            return obj

        avro_deserializer = AvroDeserializer(
            schema_registry_client,
            schema_str,
            dict_to_llm_response
        )

        # Main consumption loop
        while consumer_running:
            msg = consumer.poll(1.0)

            if msg is None:
                continue

            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    # End of partition event - not an error
                    continue
                else:
                    print(f"Consumer error: {msg.error()}")
                    continue

            try:
                print(f"Received raw message from Kafka topic {OUTPUT_TOPIC}: {msg.value()}")

                # Deserialize the message
                value = avro_deserializer(
                    msg.value(),
                    SerializationContext(OUTPUT_TOPIC, MessageField.VALUE)
                )

                print(f"Deserialized message: {value}")

                if not value:
                    print("Deserialized value is empty or null, skipping broadcast.")
                    continue

                # Prepare data for sending (ensure it's JSON serializable)
                try:
                    json_payload = json.dumps(value)
                    print(f"Broadcasting to {len(clients_set)} WebSocket clients: {json_payload}")
                except TypeError as te:
                    print(f"Error: Cannot serialize message to JSON: {te}")
                    print(f"Problematic value: {value}")
                    continue # Skip broadcasting if serialization fails

                # Broadcast to all connected WebSocket clients
                active_clients = clients_set.copy()
                if not active_clients:
                    print("No active WebSocket clients to broadcast to.")

                for client in active_clients:
                    try:
                        client.send(json_payload)
                        print(f"Successfully sent message to client {client}")
                    except Exception as e:
                        print(f"Error sending to WebSocket client {client}: {e}")
                        clients_set.discard(client) # Remove potentially broken client
            except Exception as e:
                print(f"Error processing message: {e}")

        # Clean up before exiting
        consumer.close()
        print("Kafka consumer closed")

    except Exception as e:
        print(f"Error in Kafka consumer thread: {e}")

# Start the Kafka consumer in a background thread
def start_kafka_consumer(clients_set):
    consumer_thread = threading.Thread(target=consume_from_kafka, args=(clients_set,))
    consumer_thread.daemon = True
    consumer_thread.start()
    print("Kafka consumer thread started")
    return consumer_thread

def shutdown_kafka():
    global producer, consumer_running
    consumer_running = False
    if producer:
        producer.flush()
        print("Kafka producer flushed and shutting down")
