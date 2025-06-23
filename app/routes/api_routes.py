"""
API routes for the Meeting Coach application
"""

from flask import jsonify, request

from app import app, verbose_print
from app.utils.data_utils import generate_coaching_advice
from app.utils.kafka_utils import send_to_kafka
from app.utils.cache_utils import load_cache, message_cache

# API endpoint for coaching advice
@app.route('/api/coaching-advice')
def coaching_advice():
    """Returns coaching advice based on a message query parameter"""
    message = request.args.get('message', '')
    advice = generate_coaching_advice(message)

    if advice:
        return jsonify({"has_advice": True, "advice": advice})
    else:
        return jsonify({"has_advice": False})

# API endpoint to send a message
@app.route('/api/send-message', methods=['POST'])
def send_message():
    """Sends a message to Kafka or returns cached response if available"""
    data = request.json
    message = data.get('message', '')

    if not message:
        return jsonify({"status": "error", "message": "Empty message"}), 400

    # Check cache first
    if message in message_cache:
        verbose_print(f"Returning cached response for: {message}")
        # Return the full cached data structure
        cached_data = message_cache[message]
        return jsonify({"status": "cached", "coaching_response": cached_data["Response"], "full_data": cached_data})
    else:
        print(f"📤 Message not in cache, sending to Kafka: {message}")
        result = send_to_kafka(message, speaker="prospect")
        # Note: The response from Kafka will be handled by the WebSocket consumer
        # This endpoint just confirms the message was sent to Kafka
        return jsonify(result)

# Endpoint to provide cached questions for the frontend
@app.route('/api/cached-questions')
def cached_questions():
    """Returns all cached questions for the frontend"""
    try:
        # If message_cache is empty, trigger a reload
        if not message_cache:
            load_cache()

        # Transform the cache dictionary into the list format expected by the frontend
        questions_list = []
        for msg, data in message_cache.items():
            if not msg:  # Skip empty keys
                continue

            # Create a properly formatted item for each cached message
            item = {
                "question": msg
            }

            # Add all other fields from the data dictionary
            # Ensure no None values that can cause JSON serialization errors
            for key, value in data.items():
                if key is None:  # Skip None keys
                    continue
                item[key] = "" if value is None else value

            # Sanity check - make sure both question and Response exist
            if not item.get("question") or not item.get("Response"):
                continue

            questions_list.append(item)

        # Sort by alphabetical order of questions
        questions_list.sort(key=lambda x: x.get("question", ""))

        return jsonify(questions_list)
    except Exception as e:
        verbose_print(f"Error in cached_questions endpoint: {e}")
        # Return an empty list in case of error to prevent frontend from breaking
        return jsonify([])
