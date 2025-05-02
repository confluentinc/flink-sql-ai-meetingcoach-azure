"""
Cache utilities for the Meeting Coach Demo app
"""

import os
import csv
import pathlib

# Global cache for messages
message_cache = {}

# Get the absolute path to the CSV file
def get_cache_file_path():
    # Get the root project directory (parent of app directory)
    root_dir = pathlib.Path(__file__).parent.parent.parent.absolute()
    return os.path.join(root_dir, 'static/cached.csv')

# Function to load cache from CSV
def load_cache():
    global message_cache
    try:
        # Initialize empty cache
        message_cache = {}

        # Get absolute path to cache file
        csv_file_path = get_cache_file_path()

        # Check if file exists first
        if not os.path.exists(csv_file_path):
            print(f"{csv_file_path} not found. Creating empty file.")
            # Create the file with headers
            with open(csv_file_path, mode='w', newline='', encoding='utf-8') as file:
                writer = csv.writer(file)
                writer.writerow(['Message', 'Response', 'Reasoning', 'Used Excerpts', 'RAG sources'])
            return

        # Check if file is empty
        if os.path.getsize(csv_file_path) == 0:
            print(f"{csv_file_path} is empty. Adding headers.")
            with open(csv_file_path, mode='w', newline='', encoding='utf-8') as file:
                writer = csv.writer(file)
                writer.writerow(['Message', 'Response', 'Reasoning', 'Used Excerpts', 'RAG sources'])
            return

        with open(csv_file_path, mode='r', newline='', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            if not reader.fieldnames or 'Message' not in reader.fieldnames or 'Response' not in reader.fieldnames:
                print(f"Error: {csv_file_path} must contain 'Message' and 'Response' columns.")
                # Fix the file by rewriting with proper headers
                with open(csv_file_path, mode='w', newline='', encoding='utf-8') as new_file:
                    writer = csv.writer(new_file)
                    writer.writerow(['Message', 'Response', 'Reasoning', 'Used Excerpts', 'RAG sources'])
                return

            for row in reader:
                if row.get('Message'):  # Skip rows without a Message field
                    # Ensure all fields have at least empty string values, not None
                    sanitized_row = {k: (v if v is not None else '') for k, v in row.items()}
                    # Add question field to maintain consistency with frontend expectations
                    sanitized_row['question'] = sanitized_row.get('Message', '')
                    # Store the entire sanitized row data
                    message_cache[sanitized_row['Message']] = sanitized_row

            print(f"Loaded {len(message_cache)} items into cache.")
    except Exception as e:
        print(f"Error loading cache from {csv_file_path}: {e}")
        # Initialize empty cache to prevent further errors
        message_cache = {}

def add_to_cache(question, response, reasoning='', used_excerpts='', rag_sources=''):
    """Add a new entry to the cache"""
    global message_cache

    # Define standard fieldnames
    fieldnames = ['Message', 'Response', 'Reasoning', 'Used Excerpts', 'RAG sources']
    csv_file_path = get_cache_file_path()

    try:
        # Check if file exists and create it with header if needed
        file_exists = os.path.isfile(csv_file_path)
        write_header = not file_exists or os.path.getsize(csv_file_path) == 0

        # Append the new data
        with open(csv_file_path, mode='a', newline='', encoding='utf-8') as file:
            writer = csv.DictWriter(file, fieldnames=fieldnames)

            if write_header:
                writer.writeheader()

            # Create the row dictionary with standard field names
            row_to_write = {
                'Message': question,
                'Response': response,
                'Reasoning': reasoning,
                'Used Excerpts': used_excerpts,
                'RAG sources': rag_sources
            }

            writer.writerow(row_to_write)

        # Update in-memory cache with both Message and question keys for consistency
        cached_item = {
            'Message': question,
            'Response': response,
            'question': question,  # Add question field for frontend consistency
            'Reasoning': reasoning,
            'Used Excerpts': used_excerpts,
            'RAG sources': rag_sources
        }

        # Add to message_cache with Message as the key
        message_cache[question] = cached_item
        print(f"Appended to {csv_file_path} and updated cache: {question}")

        return True, cached_item

    except Exception as e:
        print(f"Error adding to cache file {csv_file_path}: {e}")
        return False, str(e)

def delete_from_cache(index):
    """Delete an entry from the cache by index"""
    global message_cache
    csv_file_path = get_cache_file_path()
    rows = []

    try:
        # Check if file exists first
        if not os.path.exists(csv_file_path):
            print(f"Error: {csv_file_path} not found.")
            # Create the file with headers
            with open(csv_file_path, mode='w', newline='', encoding='utf-8') as file:
                writer = csv.writer(file)
                writer.writerow(['Message', 'Response', 'Reasoning', 'Used Excerpts', 'RAG sources'])
            return False, "Cache file not found, created new empty file"

        # Check if file is empty
        if os.path.getsize(csv_file_path) == 0:
            # Create the file with headers
            with open(csv_file_path, mode='w', newline='', encoding='utf-8') as file:
                writer = csv.writer(file)
                writer.writerow(['Message', 'Response', 'Reasoning', 'Used Excerpts', 'RAG sources'])
            return False, "Cache file was empty, added headers"

        # Read all rows into memory
        with open(csv_file_path, mode='r', newline='', encoding='utf-8') as file:
            reader = csv.reader(file)
            try:
                header = next(reader) # Read header
                rows.append(header)
                rows.extend(list(reader)) # Read data rows
            except StopIteration:
                # Handle empty file or just header
                print("File is empty or has only header row")
                return False, "No data to delete"

        # Validate index (0-based index for data rows)
        if index < 0 or index >= len(rows) - 1: # -1 because rows includes header
            return False, "Index out of bounds"

        # Remove the specified row (index + 1 because rows list includes header)
        deleted_row = rows.pop(index + 1)
        print(f"Deleted row {index}: {deleted_row}")

        # Rewrite the file without the deleted row
        with open(csv_file_path, mode='w', newline='', encoding='utf-8') as file:
            writer = csv.writer(file)
            writer.writerows(rows)

        # Reload the in-memory cache for immediate consistency
        load_cache()
        print("In-memory cache reloaded after deletion")

        return True, f"Deleted row at index {index}"

    except Exception as e:
        print(f"Error deleting from cache: {e}")
        return False, str(e)

def get_cached_responses():
    """Get all cached responses"""
    global message_cache
    cached_data = []
    csv_file_path = get_cache_file_path()

    try:
        # Check if file exists first or create it
        if not os.path.exists(csv_file_path):
            print(f"Warning: {csv_file_path} not found. Creating new file.")
            # Create the file with headers
            with open(csv_file_path, mode='w', newline='', encoding='utf-8') as file:
                writer = csv.writer(file)
                writer.writerow(['Message', 'Response', 'Reasoning', 'Used Excerpts', 'RAG sources'])
            # Return empty data
            return []

        # Check if file is empty (just header or nothing)
        file_size = os.path.getsize(csv_file_path)
        if file_size == 0:
            # Create the file with headers
            with open(csv_file_path, mode='w', newline='', encoding='utf-8') as file:
                writer = csv.writer(file)
                writer.writerow(['Message', 'Response', 'Reasoning', 'Used Excerpts', 'RAG sources'])
            # Return empty data
            return []

        with open(csv_file_path, mode='r', newline='', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            # Check if reader.fieldnames is None or missing required columns
            if not reader.fieldnames or not all(field in reader.fieldnames for field in ['Message', 'Response']):
                # Log error if columns are missing
                print(f"Warning: Expected columns 'Message' and 'Response' not found in {csv_file_path}")
                # Recreate the file with proper headers
                with open(csv_file_path, mode='w', newline='', encoding='utf-8') as new_file:
                    writer = csv.writer(new_file)
                    writer.writerow(['Message', 'Response', 'Reasoning', 'Used Excerpts', 'RAG sources'])
                # Return empty data
                return []

            # Process each row, sanitizing data
            for row in reader:
                if not row or not row.get('Message'):  # Skip empty rows or rows without Message
                    continue

                # Make sure no None values - replace with empty strings
                sanitized_row = {k: (v if v is not None else '') for k, v in row.items()}
                # Add 'question' field for frontend consistency
                sanitized_row['question'] = sanitized_row.get('Message', '')
                sanitized_row['response'] = sanitized_row.get('Response', '')

                # Only add rows that have both a Message/question and a Response/response
                if sanitized_row['question'] and (sanitized_row.get('Response') or sanitized_row.get('response')):
                    cached_data.append(sanitized_row)

        # Sort data alphabetically by question for consistency
        cached_data.sort(key=lambda x: x.get('question', ''))
        return cached_data

    except Exception as e:
        print(f"Error reading cache file {csv_file_path}: {e}")
        # Force reload the cache and return empty array
        try:
            # Create the file with headers
            with open(csv_file_path, mode='w', newline='', encoding='utf-8') as file:
                writer = csv.writer(file)
                writer.writerow(['Message', 'Response', 'Reasoning', 'Used Excerpts', 'RAG sources'])
            # Reload cache
            load_cache()
        except Exception as inner_e:
            print(f"Error recreating cache file: {inner_e}")

        return []
