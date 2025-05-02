"""
Data utility functions for the Meeting Coach application
"""

import os
import json

# Load meeting data
def load_meeting_data():
    """Load the simulated meeting data from JSON file"""
    meetings_dir = 'static'
    meeting_file = os.path.join(meetings_dir, 'meeting_scenario_1.json')

    with open(meeting_file, 'r') as f:
        meeting_data = json.load(f)

    return meeting_data

# Keywords that trigger coaching advice
TRIGGER_KEYWORDS = [
    'price', 'expensive', 'cost', 'competitor', 'issue',
    'problem', 'concern', 'difficult', 'challenge', 'roi',
    'implementation', 'integration', 'budget', 'techriva', 'competex'
]

# Generate simulated coaching advice based on message content
def generate_coaching_advice(message):
    """Generate simulated coaching advice based on message content"""
    if not any(keyword in message.lower() for keyword in TRIGGER_KEYWORDS):
        return None

    if 'price' in message.lower() or 'expensive' in message.lower() or 'cost' in message.lower() or 'budget' in message.lower():
        return {
            "suggested_response": "I understand budget is important. Could you share more about your budget constraints so I can explore options that might work better for your situation?",
            "knowledge": "Our ROI calculator shows most customers see a full return on investment within 6 months due to efficiency gains and reduced operational costs."
        }

    if 'competitor' in message.lower() or 'competex' in message.lower() or 'techriva' in message.lower():
        return {
            "suggested_response": "While competitors might advertise shorter timeframes, our implementation includes full data migration, customized integrations, and team training to ensure you get maximum value from day one.",
            "knowledge": "CompeteX typically only performs basic software installation in their 2-week timeline, requiring customers to handle data migration and integration themselves."
        }

    if 'implementation' in message.lower() or 'integration' in message.lower():
        return {
            "suggested_response": "We've developed a streamlined implementation process based on over 500 successful deployments. Could you tell me more about your specific integration needs?",
            "knowledge": "Our implementation success rate is 98.7%, with most customers fully operational within the 4-6 week timeframe."
        }

    # Generic coaching advice for other triggers
    return {
        "suggested_response": "That's an important point. Could you elaborate a bit more on your specific concerns in this area?",
        "knowledge": "Our customer success team has documented that addressing objections directly leads to 35% higher close rates."
    }
