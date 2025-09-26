import json
import sys
from datetime import datetime
import os
import time

all_skus = json.load(sys.stdin)
location = sys.argv[1]

def is_fully_available(sku, location):
    restrictions = sku.get("restrictions", [])
    if not restrictions:
        return True  # No restrictions at all

    # Keep SKUs that are only restricted in zones, not the whole location
    for r in restrictions:
        if r.get("type") == "Location" and r.get("reasonCode") == "NotAvailableForSubscription":
            if location in r.get("restrictionInfo", {}).get("locations", []):
                return False  # Fully restricted in this location
    return True  # Not fully restricted

filtered = [obj for obj in all_skus if is_fully_available(obj, location)]

# Get the directory where this script resides
script_dir = os.path.dirname(os.path.abspath(__file__))
output_dir = os.path.join(script_dir, "output")
os.makedirs(output_dir, exist_ok=True)

now = datetime.now()  # Use system local time
timezone_acronym = time.strftime("%Z")  # Get timezone acronym (like CDT, CST, etc.)
timestamp = now.strftime("%m-%d-%yT%H.%M.%S") + f"{timezone_acronym}"
output_filename = f"{location}_skus_{timestamp}.json"
output_path = os.path.join(output_dir, output_filename)

with open(output_path, "w") as f:
    json.dump(filtered, f, indent=2)
