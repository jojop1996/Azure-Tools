import json
import sys
from datetime import datetime
import os
import time

all_skus = json.load(sys.stdin)
location = sys.argv[1]

filtered = [obj for obj in all_skus if obj.get("restrictions") == []]

# Get the directory where this script resides
script_dir = os.path.dirname(os.path.abspath(__file__))
output_dir = os.path.join(script_dir, "output")
os.makedirs(output_dir, exist_ok=True)

now = datetime.now()  # Use system local time
timezone_acronym = time.strftime("%Z")  # Get timezone acronym (like EDT, CST, etc.)
timestamp = now.strftime("%m-%d-%yT%H.%M.%S") + f"{timezone_acronym}"
output_filename = f"{location}_skus_{timestamp}.json"
output_path = os.path.join(output_dir, output_filename)

with open(output_path, "w") as f:
    json.dump(filtered, f, indent=2)
