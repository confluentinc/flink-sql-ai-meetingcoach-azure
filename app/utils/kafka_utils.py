"""
Kafka Utility Functions for the Meeting Coach Application
"""

import json
import os
import uuid
import socket
import threading
from confluent_kafka import Producer, Consumer, KafkaError
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer, AvroDeserializer
from confluent_kafka.serialization import SerializationContext, MessageField

# Global variables for Kafka configuration
BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS')
SCHEMA_REGISTRY_URL = os.getenv('SCHEMA_REGISTRY_URL')
SASL_USERNAME = os.getenv('KAFKA_API_KEY')
SASL_PASSWORD = os.getenv('KAFKA_API_SECRET')
SR_API_KEY = os.getenv('SCHEMA_REGISTRY_API_KEY')
SR_API_SECRET = os.getenv('SCHEMA_REGISTRY_API_SECRET')

# Check if credentials are available
if not all([BOOTSTRAP_SERVERS, SCHEMA_REGISTRY_URL, SASL_USERNAME, SASL_PASSWORD, SR_API_KEY, SR_API_SECRET]):
    print("WARNING: Required Kafka credentials not found in environment variables.")
    print("Please set the following environment variables:")
    print("  - KAFKA_BOOTSTRAP_SERVERS")
    print("  - SCHEMA_REGISTRY_URL")
    print("  - KAFKA_API_KEY")
    print("  - KAFKA_API_SECRET")
    print("  - SCHEMA_REGISTRY_API_KEY")
    print("  - SCHEMA_REGISTRY_API_SECRET")

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

        # Create an Avro serializer
        avro_serializer = AvroSerializer(
            schema_registry_client,
            schema_str,
            lambda record, ctx: record  # Identity function
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
        avro_deserializer = AvroDeserializer(
            schema_registry_client,
            schema_str
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
                # Deserialize the message
                value = avro_deserializer(
                    msg.value(),
                    SerializationContext(OUTPUT_TOPIC, MessageField.VALUE)
                )

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
