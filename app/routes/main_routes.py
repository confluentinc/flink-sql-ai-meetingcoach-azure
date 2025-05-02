"""
Main routes for the Meeting Coach application
"""

import os
from flask import render_template, jsonify
from app import app

# Main route to render the index page
@app.route('/')
def index():
    """Renders the main index.html template"""
    return render_template('index.html')

# Route to get meeting data
@app.route('/api/meeting-data')
def meeting_data():
    """Returns simulated meeting data as JSON"""
    from app.utils.data_utils import load_meeting_data
    return jsonify(load_meeting_data())

# Route to get documents
@app.route('/api/get-document/<path:doc_path>')
def get_document(doc_path):
    """
    Retrieve the content of a markdown document from the knowledge base.

    Args:
        doc_path: The path to the document within the knowledge base directory

    Returns:
        The document content or an error message
    """
    try:
        # Construct the full path to the file
        full_path = os.path.join('sample-data', 'knowledge_base_markdown', doc_path)

        # Validate the path to prevent directory traversal attacks
        if not os.path.normpath(full_path).startswith(os.path.join('sample-data', 'knowledge_base_markdown')):
            return jsonify({"error": "Invalid document path"}), 400

        # Check if the file exists
        if not os.path.isfile(full_path):
            return jsonify({"error": "Document not found"}), 404

        # Read the file content
        with open(full_path, 'r', encoding='utf-8') as file:
            content = file.read()

        return jsonify({"content": content, "path": doc_path})
    except Exception as e:
        print(f"Error retrieving document: {e}")
        return jsonify({"error": str(e)}), 500
