import urllib.request
import sys

job_id = "92097998207"
url = f"https://api.github.com/repos/akshayjango/dealbuster/actions/jobs/{job_id}/logs"

req = urllib.request.Request(
    url, 
    headers={'User-Agent': 'Mozilla/5.0'}
)

try:
    with urllib.request.urlopen(req) as response:
        # Since this is a redirect, urlopen automatically follows it
        log_data = response.read().decode('utf-8', errors='ignore')
        lines = log_data.splitlines()
        print(f"Total lines in log: {len(lines)}")
        print("\n".join(lines[-150:]))
except Exception as e:
    print(f"Error fetching logs: {e}")
    sys.exit(1)
