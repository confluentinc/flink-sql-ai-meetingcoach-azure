#!/usr/bin/env python3
"""
Meeting Coach Demo App - Main Entry Point
"""

import threading
from app import app, start_consumer, shutdown

if __name__ == '__main__':
    # Start the Kafka consumer thread before running the app
    consumer_thread = start_consumer()

    try:
        # Run the Flask app
        app.run(debug=True, threaded=True, host='0.0.0.0', port=5000)
    finally:
        # Signal the consumer thread to stop
        shutdown()
        # Wait for the consumer thread to finish
        consumer_thread.join(timeout=5)
