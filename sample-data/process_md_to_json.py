import json
import os
import datetime
import argparse
import sys

# The purpose of this script is to preprocess the Markdown documents that comprise our Knowledge Base, so that they
# conform to the JSON schema expected by the `knowledge_raw` table.

# ================ CONFIGURATION OPTIONS ================
# Output directory for processed JSON files
DEFAULT_OUTPUT_DIR = "processed_json"

# File extensions to process (lowercase)
MARKDOWN_EXTENSIONS = [".md", ".markdown"]

# Date format for timestamp (ISO 8601 format for compatibility with schema)
DATE_FORMAT = "%Y-%m-%dT%H:%M:%S.%fZ"

# Whether to print verbose output
VERBOSE = True


# =====================================================

def process_markdown_to_json(file_path, output_dir=DEFAULT_OUTPUT_DIR, input_base_dir=None):
    """
    Reads a markdown file and converts it to JSON format ready for Azure Blob Storage
    to be later ingested by Confluent's managed Azure Blob Storage Source connector.

    Args:
        file_path: Path to the markdown file
        output_dir: Base directory to save the processed JSON files
        input_base_dir: Base input directory for preserving structure

    Returns:
        str: Path to the created JSON file or None if processing failed
    """
    # Check if file exists
    if not os.path.exists(file_path):
        if VERBOSE:
            print(f"Error: File not found at {file_path}")
        return None

    try:
        # Read markdown file
        with open(file_path, 'r', encoding='utf-8') as file:
            markdown_content = file.read()

        # Create metadata matching knowledge table schema
        metadata = {
            "document_id": os.path.relpath(file_path, input_base_dir).replace("\\", "/") if input_base_dir else os.path.basename(file_path),
            "document_name": os.path.basename(file_path),
            "document_category": os.path.basename(os.path.dirname(file_path)),
            "document_text": markdown_content
        }

        # Payload is just the flat metadata structure
        payload = metadata

        # Convert to JSON
        json_payload = json.dumps(payload)

        # Determine output path based on whether we want to preserve directory structure
        if input_base_dir:
            # Get relative path from input_base_dir
            rel_path = os.path.relpath(os.path.dirname(os.path.abspath(file_path)),
                                       os.path.abspath(input_base_dir))

            # If rel_path is '.', it means the file is directly in input_base_dir
            if rel_path == '.':
                target_dir = output_dir
            else:
                target_dir = os.path.join(output_dir, rel_path)

            if VERBOSE:
                print(f"File: {file_path}")
                print(f"Base dir: {input_base_dir}")
                print(f"Relative path: {rel_path}")
                print(f"Target dir: {target_dir}")
        else:
            target_dir = output_dir

        # Create output directory if it doesn't exist
        os.makedirs(target_dir, exist_ok=True)

        # Create output filename
        base_filename = os.path.basename(file_path)
        output_filename = f"{os.path.splitext(base_filename)[0]}.json"
        output_path = os.path.join(target_dir, output_filename)

        # Write JSON to file
        with open(output_path, 'w', encoding='utf-8') as output_file:
            output_file.write(json_payload)

        if VERBOSE:
            print(f"Processed: {file_path} -> {output_path}")
        return output_path

    except Exception as e:
        if VERBOSE:
            print(f"Error processing {file_path}: {str(e)}")
        return None


def process_directory(directory_path, output_dir=DEFAULT_OUTPUT_DIR, recursive=True, preserve_structure=True,
                      original_base_dir=None):
    """
    Process markdown files in a directory and optionally its subdirectories

    Args:
        directory_path: Path to directory containing markdown files
        output_dir: Directory to save processed JSON files
        recursive: Whether to process subdirectories
        preserve_structure: Whether to preserve directory structure in output
        original_base_dir: The original base directory for relative path calculation

    Returns:
        list: List of paths to created JSON files
    """
    if not os.path.exists(directory_path):
        if VERBOSE:
            print(f"Error: Directory not found at {directory_path}")
        return []

    # Use the original input directory as the root for relative path calculations if preserving structure
    # This ensures we maintain the proper structure for nested directories
    input_base_dir = original_base_dir if original_base_dir else directory_path
    processed_files = []

    # Process files in current directory
    for item in os.listdir(directory_path):
        item_path = os.path.join(directory_path, item)

        # If it's a file with markdown extension
        if os.path.isfile(item_path) and any(item.lower().endswith(ext) for ext in MARKDOWN_EXTENSIONS):
            result = process_markdown_to_json(item_path, output_dir, input_base_dir if preserve_structure else None)
            if result:
                processed_files.append(result)

        # If it's a directory and recursive processing is enabled
        elif os.path.isdir(item_path) and recursive:
            # Pass down the original base directory to maintain consistent relative paths
            sub_processed = process_directory(
                item_path, output_dir, recursive, preserve_structure,
                original_base_dir=input_base_dir if preserve_structure else None
            )
            processed_files.extend(sub_processed)

    return processed_files


def main():
    """Main function to process markdown files based on command line arguments"""
    parser = argparse.ArgumentParser(description='Process markdown files to JSON format for Azure Blob Storage')

    # Input can be specified either as a positional argument or with --input
    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument('input_pos', nargs='?', help='Input file or directory path (positional)', default=None)
    input_group.add_argument('-i', '--input', dest='input_named', help='Input file or directory path (named)')

    parser.add_argument('-o', '--output', default=DEFAULT_OUTPUT_DIR,
                        help=f'Output directory (default: {DEFAULT_OUTPUT_DIR})')
    parser.add_argument('-r', '--recursive', action='store_true',
                        help='Process subdirectories recursively (only applies to directories)')
    parser.add_argument('-f', '--flat', action='store_true',
                        help='Flatten output directory structure (ignore source directory structure)')
    parser.add_argument('-q', '--quiet', action='store_true',
                        help='Suppress verbose output')
    parser.add_argument('-v', '--verbose-debug', action='store_true',
                        help='Show extra debug information')

    args = parser.parse_args()

    # Determine the actual input path (either positional or named)
    input_path = args.input_pos if args.input_pos is not None else args.input_named

    # Update global verbose setting
    global VERBOSE
    VERBOSE = not args.quiet

    # Process input
    if os.path.isfile(input_path):
        # For a single file, we use its parent directory as the base directory if preserving structure
        input_base_dir = os.path.dirname(input_path) if not args.flat else None
        result = process_markdown_to_json(input_path, args.output, input_base_dir)
        processed_count = 1 if result else 0
    elif os.path.isdir(input_path):
        # Process directory
        processed_files = process_directory(
            input_path, args.output, args.recursive, not args.flat)
        processed_count = len(processed_files)
    else:
        print(f"Error: Input path '{input_path}' does not exist")
        return 1

    if VERBOSE:
        print(f"Processed {processed_count} markdown files to JSON format")

    return 0


if __name__ == "__main__":
    sys.exit(main())
