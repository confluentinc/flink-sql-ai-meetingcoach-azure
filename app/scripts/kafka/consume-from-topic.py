#!/usr/bin/env python3
"""
consume-from-topic.py - Consumes messages from the messages_prospect_rag_llm_response Confluent Kafka topic in Avro format
"""

import os
import signal
import sys
import socket
from pathlib import Path
from confluent_kafka import Consumer, Producer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroDeserializer, AvroSerializer
from confluent_kafka.serialization import SerializationContext, MessageField
import uuid

# Load environment variables from the .env file
env_file = Path(__file__).parent.parent.parent / 'terraform' / '.env'
if env_file.exists():
    print(f"Loading configuration from {env_file}")
    # Simple env file parser
    with open(env_file, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                try:
                    key, value = line.split('=', 1)
                    os.environ[key] = value
                except ValueError:
                    pass  # Skip lines that don't have key=value format

# Configuration
BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS')
if not BOOTSTRAP_SERVERS:
    print("❌ Error: Kafka bootstrap servers not found in environment variables")
    print("Please set KAFKA_BOOTSTRAP_SERVERS environment variable or run from Terraform directory")
    sys.exit(1)

# Strip the "SASL_SSL://" prefix if present
if BOOTSTRAP_SERVERS.startswith("SASL_SSL://"):
    BOOTSTRAP_SERVERS = BOOTSTRAP_SERVERS[10:]

SCHEMA_REGISTRY_URL = os.getenv('SCHEMA_REGISTRY_URL')
if not SCHEMA_REGISTRY_URL:
    print("❌ Error: Schema Registry URL not found in environment variables")
    print("Please set SCHEMA_REGISTRY_URL environment variable or run from Terraform directory")
    sys.exit(1)
INPUT_TOPIC = 'messages_prospect_rag_llm_response'
OUTPUT_TOPIC = 'messages_conversation'
GROUP_ID = 'rag-consumer-group'

# Authentication - use the environment variables from .env file
SASL_USERNAME = os.getenv('SCRIPT_KAFKA_API_KEY', os.getenv('confluent_cloud_api_key'))
SASL_PASSWORD = os.getenv('SCRIPT_KAFKA_API_SECRET', os.getenv('confluent_cloud_api_secret'))
SR_API_KEY = os.getenv('SCHEMA_REGISTRY_API_KEY')
SR_API_SECRET = os.getenv('SCHEMA_REGISTRY_API_SECRET')

# Print the configuration for debugging
print(f"Using Kafka bootstrap servers: {BOOTSTRAP_SERVERS}")
print(f"Using Schema Registry URL: {SCHEMA_REGISTRY_URL}")

# Setup consumer configuration
consumer_conf = {
    'bootstrap.servers': BOOTSTRAP_SERVERS,
    'security.protocol': 'SASL_SSL',
    'sasl.mechanisms': 'PLAIN',
    'sasl.username': SASL_USERNAME,
    'sasl.password': SASL_PASSWORD,
    'group.id': GROUP_ID,
    'auto.offset.reset': 'earliest',  # Start from the beginning of the topic
    'enable.auto.commit': True,
    'auto.commit.interval.ms': 5000,  # Commit every 5 seconds
    'client.id': f'python-consumer-{socket.gethostname()}',
    'isolation.level': 'read_uncommitted'
}

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

    # Instead of defining a schema, let's get the schema from the Schema Registry for input topic
    try:
        # Try to get the schema that Flink is using
        schema_metadata = schema_registry_client.get_latest_version(f"{INPUT_TOPIC}-value")
        input_schema_str = schema_metadata.schema.schema_str
        print(f"Retrieved schema from Schema Registry for {INPUT_TOPIC}: {input_schema_str}")
    except Exception as e:
        print(f"Error retrieving schema from Schema Registry: {e}")
        # Fallback to a default schema if we can't get it
        input_schema_str = """
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
        print(f"Using fallback schema for input: {input_schema_str}")

    # Get or create schema for output topic
    try:
        # Try to get the schema for output topic
        schema_metadata = schema_registry_client.get_latest_version(f"{OUTPUT_TOPIC}-value")
        output_schema_str = schema_metadata.schema.schema_str
        print(f"Retrieved schema from Schema Registry for {OUTPUT_TOPIC}: {output_schema_str}")
    except Exception as e:
        print(f"Error retrieving schema from Schema Registry for output topic: {e}")
        # Fallback to a default schema
        output_schema_str = """
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
        print(f"Using fallback schema for output: {output_schema_str}")

    # Create the Avro deserializer
    avro_deserializer = AvroDeserializer(
        schema_registry_client,
        input_schema_str
    )

    # Create the Avro serializer for output
    avro_serializer = AvroSerializer(
        schema_registry_client,
        output_schema_str,
        lambda record, ctx: record
    )

    # Create Kafka consumer
    print("Connecting to Kafka consumer...")
    consumer = Consumer(consumer_conf)
    print("Kafka consumer connected successfully")

    # Create Kafka producer
    print("Connecting to Kafka producer...")
    producer = Producer(producer_config)
    print("Kafka producer connected successfully")

    # Subscribe to the topic
    consumer.subscribe([INPUT_TOPIC])

    print(f"Consumer initialized. Consuming messages from '{INPUT_TOPIC}'...")
    print("Press Ctrl+C to exit")

    try:
        while True:
            # Poll for messages
            msg = consumer.poll(1.0)  # Timeout in seconds

            if msg is None:
                # No message received
                continue

            if msg.error():
                print(f"Consumer error: {msg.error()}")
                continue

            # Get the message key if available
            key = msg.key()

            try:
                # Deserialize the message value using Avro
                value = avro_deserializer(
                    msg.value(),
                    SerializationContext(INPUT_TOPIC, MessageField.VALUE)
                )

                # Print the message in a formatted way
                print("\n" + "="*50)
                print(f"Received message with key: {key}")
                print(f"Message: {value.get('message', 'N/A')}")
                print("\nRAG Results:")
                print(f"{value.get('rag_results_string', 'N/A')}")
                print("\nCoaching Response:")
                print(f"{value.get('coaching_response', 'N/A')}")
                print("="*50 + "\n")

                # We no longer publish the coaching_response back to Kafka
                # Instead, the frontend will handle displaying it locally
                if value.get('coaching_response'):
                    print(f"Received coaching response: {value.get('coaching_response')}")

            except Exception as e:
                import traceback
                traceback.print_exc()
                print(f"Error deserializing message: {e}")
                print(f"Raw message value: {msg.value()}")

    except KeyboardInterrupt:
        print("\nConsumer interrupted.")
    finally:
        # Close the consumer to commit final offsets and clean up
        if 'consumer' in locals():
            consumer.close()

        # Flush any remaining producer messages
        if 'producer' in locals():
            producer.flush()

        print("Consumer and producer shut down.")

if __name__ == "__main__":
    main()
