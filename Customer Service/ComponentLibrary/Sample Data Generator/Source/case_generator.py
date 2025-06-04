import json
import uuid
import datetime
import concurrent.futures
from faker import Faker
import requests
from faker.providers import BaseProvider
import random
from pathlib import Path
import sys
from dateutil.parser import isoparse

def load_config():
    config_path = Path("config.json")
    if not config_path.exists():
        print("Error: config.json not found. Please run setup.py first.")
        sys.exit(1)
    
    with open(config_path) as f:
        config = json.load(f)
    
    # Provide default for randomize_days if not present
    case_gen_config = config.get("case_generator", {})
    case_gen_config.setdefault("randomize_days", 0) 
    
    return case_gen_config

# Load configuration
config = load_config()
BATCH_SIZE = config["batch_size"]
TOTAL_RECORDS = config["total_records"]
USE_CASE_DATA_JSON = config.get("use_case_data_json", False)  # New configuration option
CASE_DATA_JSON_PATH = config.get("case_data_json_path", "case_data.json")  # New configuration option
CASE_ORIGIN_CODES = [700610000, 1, 2, 3, 2483, 3986]
RANDOMIZE_DAYS = config.get("randomize_days", 0)

# Configuration from config file
SERVER_URL = config["server_url"]
COOKIE = config["cookie"]
CUSTOMER_ID = config["customer_id"]

def get_timestamp():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def generate_random_past_date(days_ago: int) -> str:
    """Generates a random datetime within the last X days in ISO 8601 Z format."""
    if days_ago <= 0:
        # Return current time if no randomization needed
        return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    
    now = datetime.datetime.now(datetime.timezone.utc)
    # Generate random seconds within the specified day range
    total_seconds_in_range = days_ago * 24 * 60 * 60
    random_seconds = random.randint(0, total_seconds_in_range)
    
    past_datetime = now - datetime.timedelta(seconds=random_seconds)
    return past_datetime.strftime("%Y-%m-%dT%H:%M:%SZ")

def generate_random_date_after(start_date_str: str) -> str:
    """Generates a random datetime between start_date_str and now, in ISO 8601 Z format."""
    try:
        start_date = isoparse(start_date_str)
    except ValueError:
        # Fallback if parsing fails - use current time
        print(f"[{get_timestamp()}] Warning: Could not parse start_date '{start_date_str}'. Using current time.")
        return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        
    now = datetime.datetime.now(datetime.timezone.utc)
    
    # Ensure start_date is timezone-aware (UTC)
    if start_date.tzinfo is None or start_date.tzinfo.utcoffset(start_date) is None:
        start_date = start_date.replace(tzinfo=datetime.timezone.utc)
        
    # If start date is in the future or very close to now, just return now
    if start_date >= now:
        return now.strftime("%Y-%m-%dT%H:%M:%SZ")

    # Calculate the time difference in seconds
    time_difference_seconds = (now - start_date).total_seconds()
    
    # Generate a random number of seconds to add to the start date
    # Ensure it's at least a few seconds after the start time for safety
    min_offset_seconds = 1 # Add at least 1 second
    if time_difference_seconds <= min_offset_seconds:
         random_offset_seconds = time_difference_seconds # if difference is tiny, use it all
    else:
        random_offset_seconds = random.uniform(min_offset_seconds, time_difference_seconds)

    random_date = start_date + datetime.timedelta(seconds=random_offset_seconds)
    return random_date.strftime("%Y-%m-%dT%H:%M:%SZ")

class VersionProvider(BaseProvider):
    def version(self):
        major = random.randint(1, 5)
        minor = random.randint(0, 9)
        patch = random.randint(0, 9)
        return f"{major}.{minor}.{patch}"

class CaseGenerator:
    def __init__(self):
        self.faker = Faker()
        self.faker.add_provider(VersionProvider)
        self.issue_types = [
            "Product malfunction",
            "Service interruption",
            "Billing discrepancy",
            "Technical support",
            "Account access"
        ]
        self.products = [
            "Cloud Storage",
            "Mobile App",
            "Customer Portal",
            "Payment Gateway",
            "Analytics Dashboard",
            "Authentication Service",
            "Data Sync Service",
            "API Gateway",
            "Reporting Module",
            "Mobile Wallet"
        ]
        self.issues = [
            "not responding",
            "experiencing delays",
            "showing error messages",
            "needs configuration",
            "requires attention",
            "performance degradation",
            "synchronization issues",
            "connection timeout",
            "authentication failure",
            "unexpected behavior",
            "requires update",
            "data inconsistency",
            "loading issues"
        ]
        self.impacts = [
            "affecting multiple users",
            "in production environment",
            "during peak hours",
            "in specific region",
            "after recent update",
            "with specific configuration",
            "for enterprise clients",
            "in mobile version",
            "in latest release"
        ]

    def generate_random_issue_title(self):
        issue_type = random.choice(self.issue_types)
        product = random.choice(self.products)
        issue = random.choice(self.issues)
        impact = random.choice(self.impacts) if random.random() < 0.7 else ""
        
        title = f"{issue_type}: {product} {issue}"
        if impact:
            title += f" - {impact}"
        
        return title[:180]  # Truncate to 180 characters

    def generate_random_description(self, title):
        description = []
        
        # Parse title components
        title_parts = title.split(" - ", 1)
        issue_type = title_parts[0].split(":")[0].strip()
        details = title_parts[0].split(":")[1].strip() if ":" in title_parts[0] else ""
        
        # Extract product and issue
        detail_parts = [p.strip() for p in details.split() if p.strip()]
        product = detail_parts[0] if detail_parts else "System"
        
        # Build description
        recent_date = self.faker.date_between(start_date='-30d', end_date='today')
        description.append(f"Issue Report - {recent_date.strftime('%b %d, %Y')}")
        description.append(f"Product/Service: {product}")
        description.append(f"Customer Impact Level: {self.determine_impact_level(title)}")
        description.append("")
        description.append("Problem Description:")
        
        # Add problem description based on issue type
        problem_desc = self.generate_problem_description(issue_type, product, title)
        description.append(problem_desc)
        description.append("")
        
        # Add technical details
        description.append("Technical Details:")
        description.append(self.generate_technical_details(issue_type, product))
        description.append("")
        
        # Add reproduction steps
        description.append("Steps to Reproduce:")
        steps = self.generate_reproduction_steps(issue_type, product, title)
        for i, step in enumerate(steps, 1):
            description.append(f"{i}. {step}")
        
        description.append("")
        description.append("Environment Information:")
        description.append(self.generate_environment_info(product))
        
        return "\n".join(description)[:3900]  # Truncate to 3900 characters

    def determine_impact_level(self, title):
        if any(x in title.lower() for x in ["multiple users", "production environment", "peak hours"]):
            return "High"
        if any(x in title.lower() for x in ["specific region", "enterprise clients"]):
            return "Medium"
        return "Low"

    def generate_problem_description(self, issue_type, product, title):
        recent_date = self.faker.date_between(start_date='-30d', end_date='today')
        time_frame = recent_date.strftime("%m/%d/%Y %H:%M:%S")
        frequency = "intermittently" if "intermittent" in title.lower() else "consistently"
        
        if issue_type == "Product malfunction":
            return (f"The {product} system has been experiencing operational issues since {time_frame}. "
                   f"Users are {frequency} reporting that the system "
                   f"{'becomes unresponsive' if 'not responding' in title else 'malfunctions'} "
                   f"during {random.choice(['normal operation', 'peak usage periods', 'routine tasks'])}. "
                   f"Error Code: {self.faker.bothify('??##????').upper()} "
                   f"Last successful operation was recorded at {recent_date.strftime('%H:%M:%S')}. "
                   f"This issue is directly impacting {random.randint(5, 50)} active users.")
        
        elif issue_type == "Service interruption":
            impact_scope = ("Affecting {random.randint(50, 200)} users across {random.randint(2, 5)} departments"
                          if "multiple users" in title else "Isolated to specific user groups")
            return (f"Service disruption detected in {product} starting at {time_frame}. "
                   f"{impact_scope}. "
                   f"System monitoring shows {random.choice(['degraded performance', 'intermittent connectivity', 'complete service outage'])}. "
                   f"Current system response time: {random.randint(1000, 5000)}ms (Expected: <500ms). "
                   f"Error rate has increased by {random.randint(40, 90)}% compared to baseline.")
        
        elif issue_type == "Billing discrepancy":
            amount = random.uniform(50, 1000)
            date = recent_date.strftime("%m/%d/%Y")
            return (f"Billing discrepancy identified for {product} on {date}. "
                   f"Amount in question: ${amount:.2f}. "
                   f"Transaction ID: {self.faker.bothify('??##??????##').upper()}. "
                   f"Discrepancy type: {random.choice(['double charge', 'incorrect rate', 'missing credit'])}. "
                   f"Affected billing period: {recent_date.strftime('%b %Y')}.")
        
        elif issue_type == "Technical support":
            return (f"Technical support request for {product} received at {time_frame}. "
                   f"User experiencing {random.choice(['difficulty accessing', 'errors while using', 'performance issues with'])} "
                   f"the {random.choice(['interface', 'core functionality', 'reporting features'])}. "
                   f"Error message: {self.faker.sentence()}. "
                   f"Last successful operation: {recent_date.strftime('%H:%M:%S')}.")
        
        else:  # Account access
            username = self.faker.user_name()
            last_access = recent_date.strftime("%m/%d/%Y %H:%M:%S")
            return (f"Account access issue reported for {product}. "
                   f"Username: {username}. "
                   f"Last successful access: {last_access}. "
                   f"Error type: {random.choice(['authentication failure', 'password reset required', 'account locked'])}. "
                   f"Security verification {random.choice(['failed', 'timed out', 'returned error'])}.")

    def generate_technical_details(self, issue_type, product):
        details = []
        recent_date = self.faker.date_between(start_date='-30d', end_date='today')
        details.append(f"- Component Version: {product} v{self.faker.version()}")
        details.append(f"- API Version: {self.faker.version()}")
        details.append(f"- Last Deployment: {recent_date.strftime('%m/%d/%Y')}")
        details.append(f"- Infrastructure: {random.choice(['AWS', 'Azure', 'GCP'])} {random.choice(['East', 'West', 'Central'])} Region")
        details.append(f"- Current Load: {random.randint(50, 95)}% capacity")
        return "\n".join(details)

    def generate_environment_info(self, product):
        info = []
        info.append(f"- Product Version: {product} {self.faker.version()}")
        info.append(f"- Operating System: {random.choice(['Windows 11', 'Windows 10', 'macOS Sonoma', 'macOS Ventura', 'Ubuntu 22.04'])} {self.faker.version()}")
        info.append(f"- Browser: {random.choice(['Chrome', 'Firefox', 'Edge', 'Safari'])} {self.faker.version()}")
        info.append(f"- Screen Resolution: {random.randint(1024, 1920)}x{random.randint(768, 1080)}")
        info.append(f"- Network Type: {random.choice(['Corporate LAN', 'VPN', 'Direct Internet'])}")
        info.append(f"- Client IP Range: {self.faker.ipv4()}/24")
        return "\n".join(info)

    def generate_reproduction_steps(self, issue_type, product, title):
        base_steps = [
            f"Access {product} through {random.choice(['web interface', 'desktop client', 'mobile app'])}",
            "Authenticate using corporate credentials"
        ]
        
        if issue_type == "Product malfunction" and "not responding" in title:
            specific_steps = [
                f"Navigate to {random.choice(['dashboard', 'main menu', 'control panel'])}",
                "Attempt to perform any operation",
                "Observe system becomes unresponsive",
                "Check browser console for errors (F12)",
                "Document exact time of occurrence"
            ]
        elif issue_type == "Service interruption":
            specific_steps = [
                "Attempt to perform standard operation",
                f"Monitor response time using {random.choice(['built-in tools', 'browser developer console', 'monitoring dashboard'])}",
                "Document any error messages received",
                "Attempt to reproduce in different browser/device",
                "Record timestamp of each attempt"
            ]
        else:
            specific_steps = [
                "Perform standard operation",
                "Document any error messages",
                "Note exact time of issue occurrence"
            ]
        
        return base_steps + specific_steps

    def get_default_subject_id(self, server_url=None, cookie=None):
        server_url = server_url or SERVER_URL
        cookie = cookie or COOKIE
        
        query = {
            "$select": "subjectid",
            "$top": 1
        }
        print(f"[{get_timestamp()}] Attempting to fetch subjects from {server_url}/api/data/v9.0/subjects")
        try:
            response = requests.get(
                f"{server_url}/api/data/v9.0/subjects",
                params=query,
                headers={'Cookie': cookie}
            )
            print(f"[{get_timestamp()}] Response status code: {response.status_code}")
            
            if response.status_code == 200:
                results = response.json().get('value', [])
                print(f"[{get_timestamp()}] Found {len(results)} subjects")
                if results:
                    subject_id = results[0]['subjectid']
                    print(f"[{get_timestamp()}] Using subject ID: {subject_id}")
                    return subject_id
                else:
                    print(f"[{get_timestamp()}] No subjects found in response")
            else:
                print(f"[{get_timestamp()}] Error response: {response.text}")
                
            raise Exception("No subject found in the system. Please create at least one subject.")
        except requests.exceptions.RequestException as e:
            print(f"[{get_timestamp()}] Request error: {str(e)}")
            raise
        except Exception as e:
            print(f"[{get_timestamp()}] Unexpected error: {str(e)}")
            raise

    def create_case(self, title, description, subject_id, server_url=None, cookie=None, customer_id=None, randomize_days=0):
        server_url = server_url or SERVER_URL
        cookie = cookie or COOKIE
        customer_id = customer_id or CUSTOMER_ID
        randomize_days_to_use = randomize_days if randomize_days is not None else RANDOMIZE_DAYS
        
        case_id = str(uuid.uuid4())
        case_data = {
            "incidentid": case_id,
            "customerid_contact@odata.bind": f"/contacts({customer_id})",
            "title": title,
            "description": description,
            "prioritycode": random.randint(1, 3),
            "casetypecode": random.randint(1, 3),
            "caseorigincode": random.choice(CASE_ORIGIN_CODES),
            "subjectid@odata.bind": f"/subjects({subject_id})"
        }
        
        # Add overriddencreatedon if randomize_days > 0
        case_createdon_to_return = None
        if randomize_days_to_use > 0:
            past_date = generate_random_past_date(randomize_days_to_use)
            case_data["overriddencreatedon"] = past_date
            case_createdon_to_return = past_date # Store the date used
            print(f"[{get_timestamp()}] Case {case_id} overriddencreatedon set to: {past_date}")
        else:
            # If not randomized, use current time as the effective createdon
            case_createdon_to_return = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

        #print(f"[{get_timestamp()}] Creating case with data: {json.dumps(case_data, indent=2)}")
        
        response = requests.post(
            f"{server_url}/api/data/v9.0/incidents",
            json=case_data,
            headers={
                'Cookie': cookie,
                'Content-Type': 'application/json',
                'Accept': 'application/json'
            }
        )
        
        if response.status_code in [201, 204]:
            print(f"[{get_timestamp()}] Successfully created case with ID: {case_id}")
            return case_id, case_createdon_to_return # Return both ID and createdon date
        
        print(f"[{get_timestamp()}] Failed to create case. Status code: {response.status_code}")
        print(f"[{get_timestamp()}] Response body: {response.text}")
        return None, None # Return None for both if creation failed

    def close_case(self, case_id, case_createdon_str, server_url=None, cookie=None, randomize_days=0):
        server_url = server_url or SERVER_URL
        cookie = cookie or COOKIE
        randomize_days_to_use = randomize_days if randomize_days is not None else RANDOMIZE_DAYS
        
        resolution_data = {
            "subject": "Auto-resolved Case",
            "incidentid@odata.bind": f"/incidents({case_id})"
        }
        
        # Add overriddencreatedon if randomize_days > 0 and we have a valid case_createdon_str
        if randomize_days_to_use > 0 and case_createdon_str:
            resolution_date = generate_random_date_after(case_createdon_str)
            resolution_data["overriddencreatedon"] = resolution_date
            print(f"[{get_timestamp()}] IncidentResolution for case {case_id} overriddencreatedon set to: {resolution_date}")
            
        close_request = {
            "IncidentResolution": resolution_data,
            "Status": 5  # Problem Solved
        }
        
        print(f"[{get_timestamp()}] Closing case {case_id}")
        
        response = requests.post(
            f"{server_url}/api/data/v9.0/CloseIncident",
            json=close_request,
            headers={
                'Cookie': cookie,
                'Content-Type': 'application/json',
                'Accept': 'application/json'
            }
        )
        
        if response.status_code != 204:
            print(f"[{get_timestamp()}] Failed to close case {case_id}. Status code: {response.status_code}")
            print(f"[{get_timestamp()}] Response body: {response.text}")

def load_case_data():
    """Load case data from JSON file."""
    try:
        with open(CASE_DATA_JSON_PATH, 'r') as f:
            data = json.load(f)
            return data.get('cases', [])
    except Exception as e:
        print(f"[{get_timestamp()}] Error loading case data from {CASE_DATA_JSON_PATH}: {str(e)}")
        sys.exit(1)

def main():
    print(f"[{get_timestamp()}] Starting case generation...")
    
    generator = CaseGenerator()
    subject_id = generator.get_default_subject_id()
    created_case_ids = []
    
    if USE_CASE_DATA_JSON:
        # Load cases from JSON file
        cases = load_case_data()
        total_cases = len(cases)
        print(f"[{get_timestamp()}] Loaded {total_cases} cases from {CASE_DATA_JSON_PATH}")
        
        # Generate cases in batches
        for i in range(0, total_cases, BATCH_SIZE):
            current_batch = cases[i:i + BATCH_SIZE]
            current_batch_size = len(current_batch)
            print(f"[{get_timestamp()}] Processing batch {i//BATCH_SIZE + 1} of {(total_cases + BATCH_SIZE - 1)//BATCH_SIZE}")
            
            with concurrent.futures.ThreadPoolExecutor(max_workers=current_batch_size) as executor:
                futures = []
                for case in current_batch:
                    futures.append(executor.submit(
                        generator.create_case,
                        case['title'],
                        case['description'],
                        subject_id,
                        randomize_days=RANDOMIZE_DAYS
                    ))
                
                for future in concurrent.futures.as_completed(futures):
                    result = future.result()
                    case_id, case_createdon = result if result else (None, None)
                    if case_id:
                        created_case_ids.append((case_id, case_createdon)) # Store tuple
    else:
        # Original functionality - generate random cases
        for i in range(0, TOTAL_RECORDS, BATCH_SIZE):
            current_batch_size = min(BATCH_SIZE, TOTAL_RECORDS - i)
            print(f"[{get_timestamp()}] Processing batch {i//BATCH_SIZE + 1} of {(TOTAL_RECORDS + BATCH_SIZE - 1)//BATCH_SIZE}")
            
            with concurrent.futures.ThreadPoolExecutor(max_workers=current_batch_size) as executor:
                futures = []
                for _ in range(current_batch_size):
                    title = generator.generate_random_issue_title()
                    description = generator.generate_random_description(title)
                    futures.append(executor.submit(generator.create_case, title, description, subject_id, randomize_days=RANDOMIZE_DAYS))
                
                for future in concurrent.futures.as_completed(futures):
                    result = future.result()
                    case_id, case_createdon = result if result else (None, None)
                    if case_id:
                        created_case_ids.append((case_id, case_createdon)) # Store tuple
    
    print(f"[{get_timestamp()}] Created {len(created_case_ids)} cases. Starting case closure...")
    
    # Close cases in batches
    for i in range(0, len(created_case_ids), BATCH_SIZE):
        current_batch_size = min(BATCH_SIZE, len(created_case_ids) - i)
        print(f"[{get_timestamp()}] Closing batch {i//BATCH_SIZE + 1} of {(len(created_case_ids) + BATCH_SIZE - 1)//BATCH_SIZE}")
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=current_batch_size) as executor:
            futures = []
            for case_info in created_case_ids[i:i + current_batch_size]:
                case_id, case_createdon = case_info # Unpack tuple
                futures.append(executor.submit(generator.close_case, case_id, case_createdon, randomize_days=RANDOMIZE_DAYS)) # Pass createdon and randomize_days
            
            concurrent.futures.wait(futures)
    
    print(f"[{get_timestamp()}] Case generation and closure completed!")

if __name__ == "__main__":
    # Add dateutil to requirements if running directly
    try:
        import dateutil
    except ImportError:
        print("Package 'python-dateutil' not found. Please install it: pip install python-dateutil")
        sys.exit(1)
    main() 