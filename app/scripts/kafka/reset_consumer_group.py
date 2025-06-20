#!/usr/bin/env python3
"""
Reset consumer group offset to latest to skip old messages with vectors
"""

import os
import sys
from pathlib import Path
from confluent_kafka.admin import AdminClient, ConfigResource
from confluent_kafka import TopicPartition, OFFSET_END

# Add project root to path so we can import from app.utils
project_root = Path(__file__).parent.parent.parent.parent.absolute()
sys.path.append(str(project_root))

from app.utils.kafka_utils import (
    BOOTSTRAP_SERVERS, SASL_USERNAME, SASL_PASSWORD,
    tf_credentials, load_credentials_from_tfstate
)

def reset_consumer_group_offset():
    """Reset the consumer group offset to latest to skip old messages"""

    # Consumer group to reset
    GROUP_ID = 'meeting-coach-consumer-group'
    TOPIC = 'messages_prospect_rag_llm_response'

    print(f"Resetting consumer group '{GROUP_ID}' for topic '{TOPIC}' to latest offset...")

    # Admin client configuration
    admin_conf = {
        'bootstrap.servers': BOOTSTRAP_SERVERS,
        'security.protocol': 'SASL_SSL',
        'sasl.mechanisms': 'PLAIN',
        'sasl.username': SASL_USERNAME,
        'sasl.password': SASL_PASSWORD,
    }

    # Create admin client
    admin_client = AdminClient(admin_conf)

    try:
        # Get topic metadata
        metadata = admin_client.list_topics(topic=TOPIC, timeout=10)

        if TOPIC not in metadata.topics:
            print(f"Topic '{TOPIC}' not found!")
            return False

        topic_metadata = metadata.topics[TOPIC]
        partitions = list(topic_metadata.partitions.keys())

        print(f"Found {len(partitions)} partitions for topic '{TOPIC}': {partitions}")

        # Create TopicPartition objects set to OFFSET_END (latest)
        topic_partitions = []
        for partition in partitions:
            tp = TopicPartition(TOPIC, partition, OFFSET_END)
            topic_partitions.append(tp)

        print(f"Setting offset to LATEST for all partitions...")

        # This requires creating a consumer to commit the offset
        from confluent_kafka import Consumer

        consumer_conf = {
            'bootstrap.servers': BOOTSTRAP_SERVERS,
            'security.protocol': 'SASL_SSL',
            'sasl.mechanisms': 'PLAIN',
            'sasl.username': SASL_USERNAME,
            'sasl.password': SASL_PASSWORD,
            'group.id': GROUP_ID,
            'enable.auto.commit': False,  # We'll commit manually
        }

        consumer = Consumer(consumer_conf)

        # Assign the partitions and seek to end
        consumer.assign(topic_partitions)

        # Get the high water marks (latest offsets)
        high_water_marks = consumer.get_watermark_offsets(
            TopicPartition(TOPIC, 0), timeout=10
        )

        # Seek to end for each partition and commit
        committed_partitions = []
        for partition in partitions:
            tp = TopicPartition(TOPIC, partition)
            try:
                # Get high water mark for this partition
                low, high = consumer.get_watermark_offsets(tp, timeout=10)

                # Seek to the high water mark (latest)
                tp_with_offset = TopicPartition(TOPIC, partition, high)
                consumer.seek(tp_with_offset)
                committed_partitions.append(tp_with_offset)

                print(f"  Partition {partition}: Reset to offset {high}")

            except Exception as e:
                print(f"  Error resetting partition {partition}: {e}")

        # Commit the new offsets
        consumer.commit(offsets=committed_partitions)
        consumer.close()

        print(f"✅ Successfully reset consumer group '{GROUP_ID}' to latest offsets")
        print("   This will skip all old messages containing vectors")
        return True

    except Exception as e:
        print(f"❌ Error resetting consumer group: {e}")
        return False

if __name__ == "__main__":
    print("🔧 Consumer Group Offset Reset Tool")
    print("This will reset the consumer group to skip old messages with vectors\n")

    # Check if credentials are available
    if not all([BOOTSTRAP_SERVERS, SASL_USERNAME, SASL_PASSWORD]):
        print("❌ Missing Kafka credentials. Please ensure terraform state is available.")
        sys.exit(1)

    result = reset_consumer_group_offset()
    if result:
        print("\n✅ Reset complete! Restart your app to see the effect.")
        print("   The app should now only receive new messages without vectors.")
    else:
        print("\n❌ Reset failed. Please check the error messages above.")
        sys.exit(1)
