"""
WebSocket routes for the Meeting Coach application
"""

from app import app, sock, clients, verbose_print

# WebSocket endpoint for real-time coaching advice
@sock.route('/ws/coaching')
def coaching_socket(ws):
    """WebSocket connection handler for real-time coaching advice"""
    # Add the new client to our set
    clients.add(ws)
    verbose_print(f"🔌 New WebSocket client connected, total clients: {len(clients)}")

    try:
        # Keep the connection alive until client disconnects
        while True:
            # This will block until client sends a message or disconnects
            message = ws.receive()
            if message is None:
                break
            # We don't expect clients to send messages, but if they do:
            verbose_print(f"Received WebSocket message: {message}")
    except Exception as e:
        verbose_print(f"WebSocket error: {e}")
    finally:
        # Remove the client when they disconnect
        clients.discard(ws)
        verbose_print(f"🔌 WebSocket client disconnected, remaining clients: {len(clients)}")
