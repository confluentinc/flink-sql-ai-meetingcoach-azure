#!/usr/bin/env python3
"""
Meeting Coach Demo App - Main Entry Point
"""

import threading
import argparse
import sys
from app import app as flask_app, start_consumer, shutdown
import app

if __name__ == '__main__':
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='Meeting Coach Demo App')
    parser.add_argument('--verbose', '-v', action='store_true',
                       help='Enable verbose logging output')
    parser.add_argument('--port', '-p', type=int, default=5000,
                       help='Port to run the app on (default: 5000)')
    parser.add_argument('--host', default='0.0.0.0',
                       help='Host to bind to (default: 0.0.0.0)')

    args = parser.parse_args()

    # Set verbose mode globally
    import app
    app.VERBOSE_MODE = args.verbose

    # Display startup banner with app URL
    print("\n" + "="*60)
    print("🚀 MEETING COACH DEMO APP STARTING")
    print("="*60)
    print(f"📍 App will be available at:")
    print(f"   • http://127.0.0.1:{args.port}")
    print(f"   • http://localhost:{args.port}")
    if args.host == '0.0.0.0':
        print(f"   • http://192.168.1.112:{args.port} (if on network)")
    print("="*60 + "\n")

    # Start the Kafka consumer thread before running the app
    consumer_thread = start_consumer()

    try:
        # Run the Flask app - only enable debug mode if verbose
        flask_app.run(debug=args.verbose, threaded=True, host=args.host, port=args.port)
    finally:
        # Signal the consumer thread to stop
        shutdown()
        # Wait for the consumer thread to finish
        consumer_thread.join(timeout=5)

        # Display shutdown banner with URLs
        print("\n" + "="*60)
        print("✅ MEETING COACH DEMO APP STOPPED")
        print("="*60)
        print("💡 To restart the app, run:")
        print(f"   python app.py --port {args.port}")
        if args.verbose:
            print("   python app.py --verbose  (for detailed logs)")
        print("="*60 + "\n")
