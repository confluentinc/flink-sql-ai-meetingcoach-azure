"""
Cache management routes for the Meeting Coach application
"""

from flask import jsonify, request
from app import app
from app.utils.cache_utils import (
    load_cache,
    add_to_cache,
    delete_from_cache,
    get_cached_responses,
    message_cache,
)

# Endpoint to get all cached responses
@app.route('/cached_responses', methods=['GET'])
def get_cached_responses_route():
    """
    Reads cached.csv and returns its content as JSON.
    """
    cached_data = get_cached_responses()
    return jsonify(cached_data)

# Endpoint to delete a specific cached response by index
@app.route('/cached_responses/<int:index>', methods=['DELETE'])
def delete_cached_response(index):
    """
    Deletes a row from cached.csv based on its 0-based index (after header).
    """
    success, message = delete_from_cache(index)

    if success:
        return jsonify({"status": "success", "message": message})
    else:
        return jsonify({"status": "error", "message": message}), 400 if "bounds" in message else 500

# Endpoint to add a new cached response
@app.route('/cached_responses', methods=['POST'])
def add_cached_response():
    """
    Adds a new question/response pair to cached.csv.
    Expects JSON: {"question": "...", "response": "..."}
    """
    try:
        data = request.get_json()
        if not data or 'question' not in data or 'response' not in data:
            return jsonify({'status': 'error', 'message': 'Missing question or response in request body'}), 400

        question = data['question']
        response_text = data['response']

        success, result = add_to_cache(
            question=question,
            response=response_text,
            reasoning=data.get('reasoning', ''),
            used_excerpts=data.get('used_excerpts', ''),
            rag_sources=data.get('rag_sources', '')
        )

        if success:
            return jsonify({'status': 'success', 'question': question, 'response': response_text, 'item': result})
        else:
            return jsonify({'status': 'error', 'message': result}), 500

    except Exception as e:
        print(f"Error adding to cache: {e}")
        return jsonify({'status': 'error', 'message': f"Failed to add to cache: {e}"}), 500

# Alternate endpoint for saving interactions from the UI
@app.route('/cache_interaction', methods=['POST'])
def cache_interaction():
    """
    Receives a question and response via POST request and appends them to cached.csv.
    """
    try:
        data = request.get_json()
        if not data or 'question' not in data or 'response' not in data:
            return jsonify({'status': 'error', 'message': 'Missing question or response in request body'}), 400

        question = data['question']
        response_text = data['response']

        # Get any coaching content from the client-side if it exists
        coaching_data = {}
        if 'coaching_data' in data and isinstance(data['coaching_data'], dict):
            coaching_data = data['coaching_data']

        success, _ = add_to_cache(
            question=question,
            response=response_text,
            reasoning=coaching_data.get('reasoning', ''),
            used_excerpts=coaching_data.get('used_excerpts', ''),
            rag_sources=coaching_data.get('rag_sources', '')
        )

        if success:
            return jsonify({'status': 'success', 'question': question})
        else:
            return jsonify({'status': 'error', 'message': 'Failed to cache interaction'}), 500

    except Exception as e:
        print(f"Error caching interaction: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500
