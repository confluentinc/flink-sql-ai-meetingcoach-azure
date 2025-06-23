"""
Meeting Coach Demo App - Flask Web Application Package

This package contains the Flask application for the Meeting Coach Demo.
"""

import os
import threading
from dotenv import load_dotenv
from flask import Flask
from flask_sock import Sock

# Global verbose mode flag (set by command line argument)
VERBOSE_MODE = False

def verbose_print(message):
    """Print message only if verbose mode is enabled"""
    if VERBOSE_MODE:
        print(message)

# Load environment variables from .env file in the parent directory
# Assumes .env is in the root project directory, one level up from 'app'
dotenv_path = os.path.join(os.path.dirname(__file__), '..', '.env')
load_dotenv(dotenv_path=dotenv_path)
verbose_print(f"Attempted to load .env from: {dotenv_path}")
verbose_print(f"KAFKA_API_KEY loaded: {os.getenv('KAFKA_API_KEY') is not None}")
verbose_print(f"KAFKA_API_SECRET loaded: {os.getenv('KAFKA_API_SECRET') is not None}")

# Create Flask app instance
app = Flask(__name__,
            static_folder='static',
            template_folder='templates')
sock = Sock(app)

# Global active WebSocket clients
clients = set()

# Initialize Kafka and cache when the app starts
from app.utils.kafka_utils import initialize_kafka, start_kafka_consumer, shutdown_kafka
from app.utils.cache_utils import load_cache

# Initialize app
def init_app():
    """Initialize the Flask application with Kafka and cache"""
    # Initialize Kafka producer
    initialize_kafka()

    # Load cache
    load_cache()

    # Import routes to register them with Flask
    from app.routes import main_routes, api_routes, websocket_routes, cache_routes

# Initialize in app context
with app.app_context():
    init_app()

# For use in app.py to start the consumer thread
def start_consumer():
    """Start the Kafka consumer thread"""
    return start_kafka_consumer(clients)

# For use in app.py to shutdown Kafka connections
def shutdown():
    """Shutdown Kafka connections"""
    shutdown_kafka()
