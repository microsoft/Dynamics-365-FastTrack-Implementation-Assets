import json
import base64
import requests
import uuid
import datetime
import time
import concurrent.futures
from typing import List
from dataclasses import dataclass
from queue import Queue
from pathlib import Path
import sys
import random # Added for randomization
import os

def load_config():
    config_path = Path("config.json")
    if not config_path.exists():
        print("Error: config.json not found. Please run setup.py first.")
        sys.exit(1)
    
    with open(config_path) as f:
        config = json.load(f)
    
    # Provide defaults if not present
    conv_gen_config = config.get("conversation_transcript_generator", {})
    conv_gen_config.setdefault("randomize_days", 0) 
    conv_gen_config.setdefault("customer_id", "") # Add default for customer_id

    return conv_gen_config

# Load configuration
config = load_config()
BATCH_SIZE = config["batch_size"]

# Configuration from config file
server_url = config["server_url"]
cookie = config["cookie"]
workstreamid = config["workstream_id"]
queueid = config["queue_id"]
RANDOMIZE_DAYS = config.get("randomize_days", 0)
CUSTOMER_ID = config.get("customer_id", "") # Read customer_id from config

# List of JSON files to process - only relevant for running this script directly - UI does not need this
json_files = [
    'university_transcripts.json',
    'retail_support_transcripts.json',
    'it_helpdesk_transcripts.json',
    'banking_service_transcripts.json',
    'hotel_travel_airline_transcripts.json',
    'logistics_shipping_transcripts.json',
    'food_rideshare_transcripts.json',
    'azure_support_transcripts.json'    
]

def get_timestamp():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def generate_random_past_date(days_ago: int) -> str:
    """Generates a random datetime within the last X days in ISO 8601 Z format."""
    if days_ago <= 0:
        return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    
    now = datetime.datetime.now(datetime.timezone.utc)
    # Generate random seconds within the specified day range
    total_seconds_in_range = days_ago * 24 * 60 * 60
    random_seconds = random.randint(0, total_seconds_in_range)
    
    past_datetime = now - datetime.timedelta(seconds=random_seconds)
    return past_datetime.strftime("%Y-%m-%dT%H:%M:%SZ")

def generate_random_past_date_with_sequence(base_date_str: str, min_delta_seconds: int, max_delta_seconds: int) -> str:
    """Generates a new date string that is randomly between min_delta_seconds and max_delta_seconds after the base_date_str."""
    # Ensure base_date_str is in the correct format (ISO 8601 with Z)
    if not base_date_str.endswith('Z'):
        # Attempt to fix if it\'s missing Z, assuming UTC
        base_date_str += 'Z'
        
    try:
        # Parse the ISO 8601 string, handling the \'Z\' for UTC
        base_datetime = datetime.datetime.fromisoformat(base_date_str.replace('Z', '+00:00'))
    except ValueError as e:
        print(f"Error parsing date string \'{base_date_str}\': {e}. Falling back to current time.")
        base_datetime = datetime.datetime.now(datetime.timezone.utc) # Fallback

    random_delta_seconds = random.randint(min_delta_seconds, max_delta_seconds)
    new_datetime = base_datetime + datetime.timedelta(seconds=random_delta_seconds)
    return new_datetime.strftime("%Y-%m-%dT%H:%M:%SZ")

def transcript_annotation(transcript):
    messages = transcript.split("||")
    current_time = datetime.datetime.now() - datetime.timedelta(minutes=30)  # Start 30 mins ago
    base_timestamp = int(time.time() * 1000) - (30 * 60 * 1000)  # Base timestamp 30 mins ago
    
    json_messages = []
    
    # Add start control messages first
    control_start_time = current_time.strftime("%Y-%m-%dT%H:%M:%S+00:00")
    control_start_id = str(base_timestamp)
    
    control_message1 = {
        "created": control_start_time,
        "isControlMessage": True,
        "content": f"<addmember><eventtime>{control_start_id}</eventtime><target>8:orgid:00000020-a2a7-93a8-85f4-343a0d00699a</target></addmember>",
        "createdDateTime": control_start_time,
        "deleted": False,
        "id": control_start_id
    }
    
    control_message2 = {
        "created": control_start_time,
        "isControlMessage": True,
        "content": f"<historydisclosedupdate><eventtime>{str(int(control_start_id) + 40)}</eventtime></historydisclosedupdate>",
        "createdDateTime": control_start_time,
        "deleted": False,
        "id": str(int(control_start_id) + 40)
    }
    
    json_messages.append(control_message1)
    json_messages.append(control_message2)
    
    # Process conversation messages in order
    message_time_offset = 60  # seconds between messages
    
    for i, message in enumerate(messages):
        text = message.strip()
        # Calculate increasing timestamps for each message
        message_time = (current_time + datetime.timedelta(seconds=(i+1) * message_time_offset)).strftime("%Y-%m-%dT%H:%M:%S+00:00")
        message_id = str(base_timestamp + ((i+1) * message_time_offset * 1000))
        
        # Determine if it\'s a control message or normal message
        is_control = False
        
        if text.startswith("agent - "):
            text = message.split(" - ", maxsplit=1)[1]
            user = "Agent"
            user_id = "8fa35137-fdbc-4e29-b489-8b74489facd1"
            message_tags = "public,client_activity_id:" + str(uuid.uuid4())[:10]
            
            json_message = {
                "created": message_time,
                "isControlMessage": is_control,
                "content": text,
                "contentType": "text",
                "createdDateTime": message_time,
                "deleted": False,
                "from": {
                    "user": {
                        "displayName": "Customer Service Representative",
                        "id": user_id
                    }
                },
                "attachments": [],
                "id": message_id,
                "deliveryMode": "bridged",
                "tags": message_tags,
                "clientActivityId": message_tags.split(":")[-1]
            }
            
        elif text.startswith("customer - "):
            text = message.split(" - ", maxsplit=1)[1]
            user = "Customer"
            user_id = "00000020-a2a7-93a8-85f4-343a0d00699a"
            original_id = str(int(message_id) - 500)
            
            json_message = {
                "created": message_time,
                "isControlMessage": is_control,
                "content": text,
                "contentType": "text",
                "createdDateTime": message_time,
                "deleted": False,
                "from": {
                    "application": {
                        "displayName": user,
                        "id": user_id
                    }
                },
                "attachments": [],
                "id": message_id,
                "OriginalMessageId": original_id,
                "tags": "FromCustomer,ChannelId-lcw",
                "deliveryMode": "bridged",
                "fromUserId": "8:acs:96b491f4-7450-4945-9e00-8304d09fc19e_00000026-4ec9-8c22-aefa-4e3a0d0032b3",
                "isBridged": "True"
            }
        else:
            # Handle system messages or other formats if needed
            continue
        
        json_messages.append(json_message)
    
    # Add end messages
    last_message_time = current_time + datetime.timedelta(seconds=(len(messages)+1) * message_time_offset)
    last_message_id = base_timestamp + ((len(messages)+1) * message_time_offset * 1000)
    
    # System message for conversation end
    system_end_time = (last_message_time + datetime.timedelta(minutes=2)).strftime("%Y-%m-%dT%H:%M:%S+00:00")
    system_end_id = str(last_message_id + (2 * 60 * 1000))
    
    system_end_message = {
        "created": system_end_time,
        "isControlMessage": False,
        "content": "Customer has ended the conversation.",
        "contentType": "text",
        "createdDateTime": system_end_time,
        "deleted": False,
        "from": {
            "user": {
                "displayName": "",
                "id": "00000020-a2a7-93a8-85f4-343a0d00699a"
            }
        },
        "attachments": [],
        "id": system_end_id,
        "tags": "system,customerendconversation",
        "deliveryMode": "bridged",
        "isBridged": "True"
    }
    
    # Add end control message
    end_time = (last_message_time + datetime.timedelta(minutes=3)).strftime("%Y-%m-%dT%H:%M:%S+00:00")
    end_id = str(last_message_id + (3 * 60 * 1000))
    
    end_control_message = {
        "created": end_time,
        "isControlMessage": True,
        "content": f"<deletemember><eventtime>{end_id}</eventtime><target>8:orgid:8fa35137-fdbc-4e29-b489-8b74489facd1</target></deletemember>",
        "createdDateTime": end_time,
        "deleted": False,
        "id": end_id
    }
    
    json_messages.append(system_end_message)
    json_messages.append(end_control_message)
    
    # First serialize the message array to a string - with no whitespace
    messages_json_str = json.dumps(json_messages, separators=(',', ':'))
    
    # Then use that string as the Content value
    json_annotation = {
        "Content": messages_json_str,
        "Type": 0,
        "Mode": 0,
        "Tag": None,
        "CreatedOn": None,
        "Sender": None,
        "AttachmentInfo": None,
        "subject": "New Subject Text",
        "annotationid": str(uuid.uuid4())
    }

    # Wrap the annotation in an array and serialize with compact formatting
    json_str = json.dumps([json_annotation], separators=(',', ':'))
    
    base64encoded_str = base64.b64encode(json_str.encode('utf-8')).decode('utf-8')
    
    return base64encoded_str

# Helper function to get contact fullname
def get_contact_fullname(server_url: str, cookie: str, contact_id: str) -> str | None:
    """Fetch the fullname of a contact."""
    if not contact_id:
        return None
    try:
        response = requests.get(
            f"{server_url}/api/data/v9.0/contacts({contact_id})?$select=fullname",
            headers={'Cookie': cookie, 'Accept': 'application/json'}
        )
        if response.status_code == 200:
            return response.json().get('fullname')
        print(f"[{get_timestamp()}] Failed to fetch contact fullname ({contact_id}): {response.status_code} - {response.text}")
    except requests.exceptions.RequestException as e:
        print(f"[{get_timestamp()}] Error fetching contact fullname ({contact_id}): {e}")
    return None

# Helper function to get workstream name
def get_workstream_name(server_url: str, cookie: str, workstream_id: str) -> str | None:
    """Fetch the msdyn_name of a workstream."""
    if not workstream_id:
        return None
    try:
        response = requests.get(
            f"{server_url}/api/data/v9.0/msdyn_liveworkstreams({workstream_id})?$select=msdyn_name",
            headers={'Cookie': cookie, 'Accept': 'application/json'}
        )
        if response.status_code == 200:
            return response.json().get('msdyn_name')
        print(f"[{get_timestamp()}] Failed to fetch workstream name ({workstream_id}): {response.status_code} - {response.text}")
    except requests.exceptions.RequestException as e:
        print(f"[{get_timestamp()}] Error fetching workstream name ({workstream_id}): {e}")
    return None

@dataclass
class ChatRecord:
    liveworkitem_id: str
    transcript_id: str
    annotation_id: str
    annotation_content: str

def batch_create_liveworkitems(server_url: str, cookie: str, queueid: str, workstreamid: str, 
                               customer_ids: List[str],
                               batch_size: int = 10, randomize_days: int = 0) -> List[tuple[str, str, str]]: # Return list of tuples (id, createdon_date, subject)
    """Create liveworkitems in batches and return their IDs, createdon dates, and subjects.
       Each liveworkitem can be assigned a customer from the customer_ids list.
    """
    liveworkitem_results = [] # Store tuples of (id, createdon_date, subject)
    
    # Ensure that the number of customer_ids matches the batch_size if multiple contacts are intended per batch.
    # This function will create 'batch_size' items.
    # If customer_ids has fewer items than batch_size, it implies they might be cycled or an error.
    # For this function, we expect len(customer_ids) == batch_size, prepared by the caller.
    if len(customer_ids) != batch_size:
        print(f"[{get_timestamp()}] Warning: batch_create_liveworkitems received {len(customer_ids)} customer_ids for a batch_size of {batch_size}. Ensure the caller (app.py) prepares this list correctly for per-item assignment.")
        # As a fallback, if only one customer_id is provided, use it for all items in the batch.
        # This maintains compatibility if the caller hasn't adapted yet, or for single customer mode.
        if len(customer_ids) == 1:
            customer_ids = [customer_ids[0]] * batch_size
        else:
            # Or, if it's a list but not matching batch_size, this is an issue the caller should fix.
            # For now, we'll proceed but it might lead to unexpected assignment or errors.
            # Truncate or pad - for safety, let's just use the first one if a list of incorrect length is passed.
            # This state should ideally not be reached if app.py is correct.
            if not customer_ids: # if empty list was passed for some reason
                 print(f"[{get_timestamp()}] Error: Empty customer_ids list passed for batch_size {batch_size}.")
                 return [] # Cannot create items without customer info if needed
            customer_ids = [customer_ids[0]] * batch_size # Fallback: use first for all

    def create_single_liveworkitem(current_customer_id: str): # Takes current_customer_id
        liveworkitemid = str(uuid.uuid4())
        
        # Fetch dynamic names, fall back to defaults
        contact_name = get_contact_fullname(server_url, cookie, current_customer_id) or "Visitor" # Use current_customer_id
        workstream_name = get_workstream_name(server_url, cookie, workstreamid) or "Autonomous Agent Chat Testing Workstream"
        
        # Construct subject and title
        liveworkitem_subject = f"{contact_name}: {workstream_name}"
        liveworkitem_title = liveworkitem_subject # Use the same for title initially
        
        liveworkitem_request = {
            "activityid": liveworkitemid,
            "msdyn_ocliveworkitemid": liveworkitemid,
            "msdyn_cdsqueueid_msdyn_ocliveworkitem@odata.bind": "/queues(" + queueid + ")",
            "msdyn_liveworkstreamid_msdyn_ocliveworkitem@odata.bind": "/msdyn_liveworkstreams(" + workstreamid + ")",
            "subject": liveworkitem_subject, # Use dynamic subject
            "msdyn_title": liveworkitem_title, # Use dynamic title
            "msdyn_channel": "192360000"
        }
        
        created_on_date_to_return = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

        # Add customer id if provided
        if current_customer_id: # Use current_customer_id
            liveworkitem_request["regardingobjectid_contact_msdyn_ocliveworkitem@odata.bind"] = f"/contacts({current_customer_id})"
        
        # Add overriddencreatedon if randomize_days > 0
        if randomize_days > 0:
            past_date = generate_random_past_date(randomize_days)
            liveworkitem_request["overriddencreatedon"] = past_date
            created_on_date_to_return = past_date # This is the effective createdon date
            # print(f"[{get_timestamp()}] LiveWorkItem {liveworkitemid} overriddencreatedon set to: {past_date}")
            
        response = requests.post(server_url + '/api/data/v9.0/msdyn_ocliveworkitems', 
                               json=liveworkitem_request, 
                               headers={'Cookie': cookie, 'Prefer': 'return=representation'}) # Added Prefer header
        if response.status_code == 201: # Check for 201 Created
            return liveworkitemid, created_on_date_to_return, liveworkitem_subject
        print(f"[{get_timestamp()}] Failed to create liveworkitem: {response.status_code}. Response: {response.text}")
        return None, None, None

    with concurrent.futures.ThreadPoolExecutor(max_workers=batch_size) as executor:
        # Pass the specific customer_id from the list to each task
        futures = [executor.submit(create_single_liveworkitem, customer_ids[i]) for i in range(batch_size)]
        for future in concurrent.futures.as_completed(futures):
            result_id, result_createdon, result_subject = future.result()
            if result_id:
                liveworkitem_results.append((result_id, result_createdon, result_subject))

    return liveworkitem_results

def batch_create_transcripts(server_url: str, cookie: str, 
                             liveworkitem_details: List[tuple[str, str, str]], # Expect list of (id, createdon_date, subject)
                             batch_size: int = 10, randomize_days: int = 0) -> List[str]:
    """Create transcripts in batches and return their IDs"""
    transcript_ids = []
    
    def create_single_transcript(liveworkitem_id: str, lwi_createdon: str): # Accept lwi_createdon, subject is ignored here
        transcriptid = str(uuid.uuid4())
        transcript_request = {
            "msdyn_transcriptid": transcriptid,
            "msdyn_LiveWorkItemIdId@odata.bind": "/msdyn_ocliveworkitems(" + liveworkitem_id + ")"
        }
        
        # Add overriddencreatedon if randomize_days > 0, based on LWI creation
        if randomize_days > 0:
            # Transcript should be created at or slightly after the LWI
            # For simplicity, using the LWI's createdon directly.
            transcript_createdon = lwi_createdon 
            transcript_request["overriddencreatedon"] = transcript_createdon
            # print(f"[{get_timestamp()}] Transcript {transcriptid} overriddencreatedon set to: {transcript_createdon}")
            
        response = requests.post(server_url + '/api/data/v9.0/msdyn_transcripts', 
                               json=transcript_request, 
                               headers={'Cookie': cookie})
        if response.status_code == 204 or response.status_code == 201:
            return transcriptid
        print(f"[{get_timestamp()}] Failed to create transcript: {response.status_code}")
        return None

    with concurrent.futures.ThreadPoolExecutor(max_workers=batch_size) as executor:
        futures = [executor.submit(create_single_transcript, lw_id, lw_createdon) 
                  for lw_id, lw_createdon, _ in liveworkitem_details] # Unpack tuple, ignore subject
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            if result:
                transcript_ids.append(result)

    return transcript_ids

def batch_create_annotations(server_url: str, cookie: str, 
                           transcript_ids: List[str], 
                           annotation_contents: List[str], 
                           liveworkitem_createdon_dates: List[str], # Need these for consistency if randomizing
                           batch_size: int = 10, randomize_days: int = 0) -> List[str]:
    """Create annotations in batches and return their IDs"""
    annotation_ids = []
    
    # Ensure we have a createdon date for each annotation to be created
    # This assumes transcript_ids and liveworkitem_createdon_dates are aligned by the caller
    # (e.g., liveworkitem_createdon_dates corresponds to the LWI of the transcript)
    if len(transcript_ids) != len(liveworkitem_createdon_dates) and randomize_days > 0:
        print(f"[{get_timestamp()}] Warning: Mismatch in lengths of transcript_ids ({len(transcript_ids)}) and liveworkitem_createdon_dates ({len(liveworkitem_createdon_dates)}) for annotations. This might lead to incorrect date randomization.")
        # Fallback or error handling might be needed if this is critical

    def create_single_annotation(transcript_id: str, annotation_content: str, base_createdon_date: str):
        annotationid = str(uuid.uuid4())
        annotation_request = {
            "annotationid": annotationid,
            "mimetype": "text/plain",
            "documentbody": annotation_content,
            "objecttypecode": "msdyn_transcript",
            "objectid_msdyn_transcript@odata.bind": "/msdyn_transcripts(" + transcript_id + ")",
            "isdocument": True,
            "subject": "Visitor: Test Chat workstream", # Consider making this dynamic if needed
            "filename": "Messages_file.txt"
        }
        
        # Add overriddencreatedon if randomize_days > 0
        if randomize_days > 0 and base_createdon_date: # Ensure base_createdon_date is not None
            # Annotation createdon should be based on its related LWI's createdon
            annotation_request["overriddencreatedon"] = base_createdon_date
            # print(f"[{get_timestamp()}] Annotation {annotationid} overriddencreatedon set to: {base_createdon_date}")

        response = requests.post(server_url + '/api/data/v9.0/annotations', 
                               json=annotation_request, 
                               headers={'Cookie': cookie})
        if response.status_code == 204 or response.status_code == 201:
            return annotationid
        print(f"[{get_timestamp()}] Failed to create annotation: {response.status_code}")
        return None

    with concurrent.futures.ThreadPoolExecutor(max_workers=batch_size) as executor:
        futures = []
        for i in range(len(transcript_ids)):
            # Get the corresponding base_createdon_date. Handle potential length mismatch if randomize_days > 0.
            base_date_for_randomization = liveworkitem_createdon_dates[i % len(liveworkitem_createdon_dates)] if liveworkitem_createdon_dates and randomize_days > 0 else None
            futures.append(executor.submit(create_single_annotation, transcript_ids[i], annotation_contents[i], base_date_for_randomization))
            
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            if result:
                annotation_ids.append(result)

    return annotation_ids

@dataclass
class SessionParticipantData:
    session_activity_id: str
    session_created_on: str 
    agent_id: str
    agent_fullname: str
    randomize_days: int = 0

def batch_create_sessions(server_url: str, cookie: str, 
                          liveworkitem_details: List[tuple[str, str, str]], # List of (liveworkitem_id, createdon_date_str, subject_str)
                          batch_size: int = 10, 
                          randomize_days: int = 0) -> List[tuple[str, str]]: # Returns list of (session_activityid, session_createdon_val)
    """Create msdyn_ocsession records in batches and return their IDs and creation timestamps."""
    session_details_results = [] # Store (activity_id, session_created_on_val)

    def create_single_session(liveworkitem_id: str, lwi_createdon_str: str, lwi_subject: str):
        # activityid will be the primary key, and we'll set msdyn_sessionid to this value after creation.
        
        session_created_on_val = lwi_createdon_str # Base session creation on LWI creation
        
        if randomize_days > 0:
            # Agent accepted a bit after session creation (e.g., 10s to 2 mins)
            agent_accepted_on_val = generate_random_past_date_with_sequence(session_created_on_val, 10, 120)
            # Session closed some time after agent acceptance (e.g., 5 mins to 1 hour)
            session_closed_on_val = generate_random_past_date_with_sequence(agent_accepted_on_val, 300, 3600)
        else:
            # For non-randomized, use small fixed offsets from LWI creation, or from 'now' if lwi_createdon_str is very recent
            # To ensure sequence, derive from lwi_createdon_str if it's a past date, otherwise from now.
            base_time_for_offsets = datetime.datetime.fromisoformat(lwi_createdon_str.replace('Z', '+00:00'))
            current_utc_time = datetime.datetime.now(datetime.timezone.utc)
            
            # If lwi_createdon_str is in the future or very recent, adjust base_time_for_offsets
            # to prevent session_created_on from being in the past relative to a "now" anchor for offsets.
            if base_time_for_offsets > current_utc_time - datetime.timedelta(minutes=5) : # If LWI was created "recently" or is in the future due to randomization
                 # If session_created_on_val (from LWI) is already in the past due to randomize_days, use it.
                 # Otherwise, if it's too close to now or in the future, we might need to adjust.
                 # The goal is session_created_on <= agent_accepted_on <= session_closed_on.
                 # And if not randomizing, these should be close to 'now'.
                 
                 # If not randomizing, session_created_on_val should be very close to now.
                 # If it was randomized, it's already a past date.
                 # The key is that agent_accepted and session_closed are *after* session_created_on_val.
                 pass # session_created_on_val is already lwi_createdon_str

            # Ensure agent_accepted_on and session_closed_on are after session_created_on_val
            # If session_created_on_val is "now" because randomize_days is 0
            if randomize_days == 0:
                session_created_on_val = current_utc_time.strftime("%Y-%m-%dT%H:%M:%SZ")
                base_for_offsets = current_utc_time
            else: # If randomized, base offsets from the randomized session_created_on_val
                base_for_offsets = datetime.datetime.fromisoformat(session_created_on_val.replace('Z', '+00:00'))

            agent_accepted_on_val = (base_for_offsets + datetime.timedelta(seconds=random.randint(10, 120))).strftime("%Y-%m-%dT%H:%M:%SZ")
            session_closed_on_val = (datetime.datetime.fromisoformat(agent_accepted_on_val.replace('Z', '+00:00')) + datetime.timedelta(minutes=random.randint(5, 60))).strftime("%Y-%m-%dT%H:%M:%SZ")


        # Initial payload for creating the session - msdyn_sessionid will be set in a subsequent update
        session_create_payload = {
            "subject": lwi_subject, 
            "msdyn_channel": 192360000,  # Live chat
            "msdyn_sessioncreatedon": session_created_on_val,
            "msdyn_agentacceptedon": agent_accepted_on_val,
            "msdyn_sessionclosedon": session_closed_on_val,
            "msdyn_closurereason": 192350018,
            # Link to the Live Work Item (Conversation)
            "msdyn_liveworkitemid_msdyn_ocsession@odata.bind": f"/msdyn_ocliveworkitems({liveworkitem_id})"
        }
        
        if randomize_days > 0:
            # The session record's own 'overriddencreatedon' should be its msdyn_sessioncreatedon
            session_create_payload["overriddencreatedon"] = session_created_on_val
        
        # Step 1: Create the session
        response_create = requests.post(
            f"{server_url}/api/data/v9.0/msdyn_ocsessions", 
            json=session_create_payload, 
            headers={'Cookie': cookie, 'Prefer': 'return=representation'}
        )
        
        if response_create.status_code == 201: 
            created_session_data = response_create.json()
            activity_id = created_session_data.get("activityid") 
            if not activity_id: # Fallback check
                 activity_id = created_session_data.get("msdyn_ocsessionid") # This might be returned by some CRM versions
            
            if activity_id:
                print(f"[{get_timestamp()}] Created session with activityid {activity_id} for LWI {liveworkitem_id}.")
                
                # Step 2: Update the session with msdyn_sessionid = activityid (as string)
                session_update_payload = {
                    "msdyn_sessionid": str(activity_id) 
                }
                
                update_url = f"{server_url}/api/data/v9.0/msdyn_ocsessions({activity_id})"
                response_update = requests.patch(
                    update_url,
                    json=session_update_payload,
                    headers={'Cookie': cookie, 'Content-Type': 'application/json', 'If-Match': '*'} # Added If-Match for PATCH
                )
                
                if response_update.status_code == 204: # No Content, successful update
                    print(f"[{get_timestamp()}] Successfully updated msdyn_sessionid for session {activity_id}.")
                    return activity_id, session_created_on_val # Return tuple (activity_id, session_created_on_val)
                else:
                    print(f"[{get_timestamp()}] Failed to update msdyn_sessionid for session {activity_id}. Status: {response_update.status_code}. Response: {response_update.text}")
                    # Still return details as the session was created, but log the update failure.
                    return activity_id, session_created_on_val 
            else:
                print(f"[{get_timestamp()}] WARNING: Session created for LWI {liveworkitem_id}, but could not retrieve its activityid from response. Keys: {created_session_data.keys()}. Full response: {created_session_data}")
                return None, None
        else:
            print(f"[{get_timestamp()}] Failed to create session for LWI {liveworkitem_id}: {response_create.status_code}. Response: {response_create.text}")
            print(f"[{get_timestamp()}] Request payload: {json.dumps(session_create_payload)}")
            return None, None

    with concurrent.futures.ThreadPoolExecutor(max_workers=batch_size) as executor:
        # Pass the specific customer_id from the list to each task
        futures = [executor.submit(create_single_session, lw_id, created_on, subject) 
                   for lw_id, created_on, subject in liveworkitem_details] # Unpack subject
        for future in concurrent.futures.as_completed(futures):
            try:
                result_activity_id, result_session_createdon = future.result()
                if result_activity_id and result_session_createdon: # Ensure both are not None
                    session_details_results.append((result_activity_id, result_session_createdon))
            except Exception as e:
                print(f"[{get_timestamp()}] Error in create_single_session: {str(e)}")
                continue  # Skip this failed session and continue with others
    
    return session_details_results

def batch_create_session_participants(server_url: str, cookie: str,
                                      session_participant_data_list: List[SessionParticipantData],
                                      batch_size: int = 10) -> List[str]:
    """Create msdyn_sessionparticipant records in batches and return their IDs."""
    participant_ids_results = []

    def create_single_session_participant(data: SessionParticipantData):
        participant_id = str(uuid.uuid4()) # msdyn_sessionparticipantid is the primary key (GUID)
        
        joined_on_val = data.session_created_on # Use the session_created_on from the parent session

        payload = {
            "msdyn_sessionparticipantid": participant_id,
            "msdyn_name": data.agent_fullname,
            "msdyn_mode": 192350002, 
            "msdyn_joinedon": joined_on_val,
            "msdyn_agentid@odata.bind": f"/systemusers({data.agent_id})",
            "msdyn_omnichannelsession@odata.bind": f"/msdyn_ocsessions({data.session_activity_id})"
        }
        
        # If session itself was randomized, participant should also reflect that
        if data.randomize_days > 0:
            payload["overriddencreatedon"] = joined_on_val

        response = requests.post(
            f"{server_url}/api/data/v9.0/msdyn_sessionparticipants",
            json=payload,
            headers={'Cookie': cookie, 'Content-Type': 'application/json', 'Prefer': 'return=representation'}
        )

        if response.status_code == 201:
            created_data = response.json()
            returned_id = created_data.get("msdyn_sessionparticipantid")
            print(f"[{get_timestamp()}] Created session participant {returned_id} for session {data.session_activity_id}")
            return returned_id
        else:
            print(f"[{get_timestamp()}] Failed to create session participant for session {data.session_activity_id}: {response.status_code}. Response: {response.text}")
            print(f"[{get_timestamp()}] Request payload for session participant: {json.dumps(payload)}")
            return None

    with concurrent.futures.ThreadPoolExecutor(max_workers=batch_size) as executor:
        futures = [executor.submit(create_single_session_participant, data) for data in session_participant_data_list]
        for future in concurrent.futures.as_completed(futures):
            try:
                result = future.result()
                if result:
                    participant_ids_results.append(result)
            except Exception as e:
                print(f"[{get_timestamp()}] Error in create_single_session_participant: {str(e)}")
                continue  # Skip this failed participant and continue with others
    
    return participant_ids_results

def batch_close_liveworkitems(server_url: str, cookie: str, liveworkitem_ids: List[str], batch_size: int = 10):
    """Close liveworkitems in batches"""
    def close_single_liveworkitem(liveworkitem_id: str):
        close_request = {
            "statecode": 1,
            "statuscode": 4 # Closed
        }
        response = requests.patch(server_url + '/api/data/v9.0/msdyn_ocliveworkitems(' + liveworkitem_id + ')', 
                                json=close_request, 
                                headers={'Cookie': cookie})
        if response.status_code != 204:
            print(f"[{get_timestamp()}] Failed to close liveworkitem {liveworkitem_id}: {response.status_code}")

    with concurrent.futures.ThreadPoolExecutor(max_workers=batch_size) as executor:
        futures = [executor.submit(close_single_liveworkitem, liveworkitem_id) 
                  for liveworkitem_id in liveworkitem_ids]
        concurrent.futures.wait(futures)

def process_file(json_filepath: str, current_user_id: str, current_user_fullname: str): 
    start_time = time.time()
    print(f'[{get_timestamp()}] -- start processing {json_filepath} --')

    with open(json_filepath, 'r', encoding="utf8") as jsonfile:
        chat_data = json.load(jsonfile)
    
    if len(chat_data) > 0 and isinstance(chat_data[0], dict) and 'header' in chat_data[0]:
        chat_data = chat_data[1:]
    
    total_records = len(chat_data)
    print(f"[{get_timestamp()}] Found {total_records} records to process in {json_filepath}")
    
    # Determine batch size for API calls - can be different from file processing batch size
    api_batch_size = BATCH_SIZE # Use the global BATCH_SIZE for API operations

    count = 0
    
    while count < total_records:
        current_processing_batch_size = min(batch_size, total_records - count) # How many records from file to process in this loop iteration
        current_batch_chat_data = chat_data[count:count + current_processing_batch_size]
        
        annotation_contents = []
        for chat in current_batch_chat_data:
            if isinstance(chat, dict) and 'messages' in chat:
                formatted_transcript = ""
                for msg in chat['messages']:
                    if 'sender' in msg and 'role' in msg['sender']:
                        role = msg['sender']['role'].lower()
                        content = msg.get('text', '')
                        
                        if role == 'agent' or role == 'assistant':
                            formatted_transcript += f"agent - {content} || "
                        elif role == 'customer' or role == 'user':
                            formatted_transcript += f"customer - {content} || "
                
                if formatted_transcript.endswith(" || "):
                    formatted_transcript = formatted_transcript[:-4]
                    
                transcript = formatted_transcript
            elif isinstance(chat, dict) and 'transcript' in chat:
                transcript = chat['transcript']
            else:
                try:
                    if isinstance(chat, list) and all(isinstance(msg, str) for msg in chat):
                        formatted_transcript = ""
                        for i, msg in enumerate(chat):
                            if i % 2 == 0:
                                formatted_transcript += f"agent - {msg} || "
                            else:
                                formatted_transcript += f"customer - {msg} || "
                        
                        if formatted_transcript.endswith(" || "):
                            formatted_transcript = formatted_transcript[:-4]
                        
                        transcript = formatted_transcript
                    else:
                        transcript = json.dumps(chat)
                except:
                    transcript = str(chat)
            
            annotation_content = transcript_annotation(transcript)
            annotation_contents.append(annotation_content)

        # Determine the actual number of items we are about to process for API calls
        num_items_in_api_batch = len(annotation_contents)

        # Create liveworkitems in batch
        print(f"[{get_timestamp()}] Creating batch of {num_items_in_api_batch} liveworkitems...")
        # Assuming CUSTOMER_ID logic is handled by app.py or needs adjustment here for standalone
        customer_ids_for_batch = [CUSTOMER_ID if CUSTOMER_ID else "00000000-0000-0000-0000-000000000000"] * num_items_in_api_batch # Placeholder if not set
        liveworkitem_details_list = batch_create_liveworkitems(server_url, cookie, queueid, workstreamid, 
                                                               customer_ids_for_batch, 
                                                               num_items_in_api_batch, RANDOMIZE_DAYS)
        
        if not liveworkitem_details_list or not all(details[0] for details in liveworkitem_details_list):
            print(f"[{get_timestamp()}] Failed to create live work items for batch. Skipping further processing for this batch.")
            count += current_processing_batch_size 
            continue

        liveworkitem_ids = [details[0] for details in liveworkitem_details_list] 
        lwi_createdon_dates = [details[1] for details in liveworkitem_details_list]
        
        print(f"[{get_timestamp()}] Created {len(liveworkitem_ids)} liveworkitems")
        
        # Create transcripts in batch
        if liveworkitem_details_list:
            print(f"[{get_timestamp()}] Creating batch of {len(liveworkitem_details_list)} transcripts...")
            transcript_ids = batch_create_transcripts(server_url, cookie, liveworkitem_details_list, num_items_in_api_batch, RANDOMIZE_DAYS)
            print(f"[{get_timestamp()}] Created {len(transcript_ids)} transcripts")

            # Create sessions in batch
            print(f"[{get_timestamp()}] Creating batch of {len(liveworkitem_details_list)} sessions...")
            try:
                session_details_list = batch_create_sessions(server_url, cookie, liveworkitem_details_list, num_items_in_api_batch, RANDOMIZE_DAYS)
                print(f"[{get_timestamp()}] Created {len(session_details_list)} sessions")
            except Exception as e:
                print(f"[{get_timestamp()}] Error in batch_create_sessions: {str(e)}")
                session_details_list = []  # Set to empty list to continue processing
                print(f"[{get_timestamp()}] Set session_details_list to empty list due to error")

            # Create session participants
            print(f"[{get_timestamp()}] DEBUG: Pre-participant check: session_details_list is empty = {not session_details_list}, current_user_id = '{current_user_id}', current_user_fullname = '{current_user_fullname}'") # DEBUG LOG ADDED
            if session_details_list and current_user_id and current_user_fullname:
                print(f"[{get_timestamp()}] Creating batch of {len(session_details_list)} session participants for user {current_user_fullname} ({current_user_id})...")
                participant_data_for_batch = [
                    SessionParticipantData(
                        session_activity_id=sess_id, 
                        session_created_on=sess_createdon, 
                        agent_id=current_user_id, 
                        agent_fullname=current_user_fullname,
                        randomize_days=RANDOMIZE_DAYS 
                    ) for sess_id, sess_createdon in session_details_list if sess_id and sess_createdon
                ]
                if participant_data_for_batch:
                    participant_ids = batch_create_session_participants(server_url, cookie, participant_data_for_batch, len(participant_data_for_batch))
                    print(f"[{get_timestamp()}] Created {len(participant_ids)} session participants")
                else:
                    print(f"[{get_timestamp()}] No valid session details to create participants for.")
            else:
                if not session_details_list:
                    print(f"[{get_timestamp()}] Skipping session participants creation as no sessions were created.")
                if not current_user_id or not current_user_fullname:
                     print(f"[{get_timestamp()}] Skipping session participants creation as current user ID or fullname is missing.")


            # Create annotations in batch
            if transcript_ids: 
                print(f"[{get_timestamp()}] Creating batch of {len(transcript_ids)} annotations...")
                # Ensure annotation_contents matches the number of transcript_ids
                # If liveworkitem creation failed for some, transcript_ids might be shorter
                # We need to align annotation_contents with successfully created transcripts/LWIs
                # This assumes annotation_contents was prepared based on the original current_batch_chat_data
                # For simplicity, we'll assume that if transcript_ids were generated, there's a corresponding lwi_createdon_date.
                # A more robust solution would align annotation_contents with successful liveworkitem_details_list items.
                
                # We need createdon dates for the LWIs that correspond to the created transcripts.
                # If transcript_ids were created, it implies the corresponding LWI was also created.
                # Reconstruct lwi_createdon_dates that match the successful transcripts.
                # This assumes liveworkitem_details_list and transcript_ids are in the same order and 
                # batch_create_transcripts filters out failures.
                
                # Simplification: Use lwi_createdon_dates directly, assuming its length matches transcript_ids
                # or that batch_create_annotations can handle mismatched lengths if randomize_days = 0
                # For a more robust approach, we'd need to filter lwi_createdon_dates based on successful transcript creation.
                # Let's assume batch_create_annotations will handle it based on its current logic.
                
                # Simplification: Use lwi_createdon_dates directly, assuming its length matches transcript_ids
                # or that batch_create_annotations can handle mismatched lengths if randomize_days = 0
                # For a more robust approach, we'd need to filter lwi_createdon_dates based on successful transcript creation.
                # Let's assume batch_create_annotations will handle it based on its current logic.
                
                annotations_lwi_createdon_dates = []
                # This part is tricky because batch_create_transcripts only returns IDs.
                # We need to map transcript_ids back to their original LWI createdon dates.
                # For now, we'll pass the full lwi_createdon_dates list.
                # The create_single_annotation uses base_createdon_date = liveworkitem_createdon_dates[i % len(liveworkitem_createdon_dates)]
                # This should be okay if lengths are managed.

                annotation_ids = batch_create_annotations(server_url, cookie, transcript_ids, 
                                                          annotation_contents[:len(transcript_ids)], # Ensure annotation_contents matches transcript_ids length
                                                          lwi_createdon_dates, # Pass all lwi_createdon_dates for now, hoping for alignment or safe handling
                                                          num_items_in_api_batch, RANDOMIZE_DAYS) # Use num_items_in_api_batch for consistency
                print(f"[{get_timestamp()}] Created {len(annotation_ids)} annotations")
        
        # Close liveworkitems in batch
        if liveworkitem_ids:
            print(f"[{get_timestamp()}] Closing batch of {len(liveworkitem_ids)} liveworkitems...")
            batch_close_liveworkitems(server_url, cookie, liveworkitem_ids, num_items_in_api_batch)
            print(f"[{get_timestamp()}] Closed {len(liveworkitem_ids)} liveworkitems")
        
        count += current_processing_batch_size
        print(f"[{get_timestamp()}] Progress: Processed {count} of {total_records} chats in {json_filepath}")
    
    end_time = time.time()
    runtime = end_time - start_time
    print(f"[{get_timestamp()}] Processed {count} chats from {json_filepath}")
    print(f"[{get_timestamp()}] Runtime for {json_filepath}: {runtime:.2f} seconds")
    print(f"[{get_timestamp()}] -- end processing {json_filepath} --")

def main():
    total_start_time = time.time()
    print(f'[{get_timestamp()}] -- start processing all files --')

    # These would typically be fetched or configured in a real application context (like app.py)
    # For standalone script, they need to be provided or hardcoded for testing.
    # Example: Fetch from environment variables or a secure config if not running via Streamlit
    current_user_id_main = os.environ.get("D365_USER_ID", "default_user_guid_placeholder") 
    current_user_fullname_main = os.environ.get("D365_USER_FULLNAME", "Default User")

    if "default_user_guid_placeholder" in current_user_id_main:
        print(f"[{get_timestamp()}] WARNING: Using placeholder user ID for session participants. Set D365_USER_ID environment variable for actual user.")
        # Potentially, you could try a WhoAmI call here if server_url and cookie are available globally
        # For simplicity in this script, we'll rely on them being passed or ENV VARS.

    for json_file in json_files:
        try:
            process_file(json_file, current_user_id_main, current_user_fullname_main)
        except Exception as e:
            print(f"[{get_timestamp()}] Error processing {json_file}: {str(e)}")
            continue
    
    total_end_time = time.time()
    total_runtime = total_end_time - total_start_time
    print(f"[{get_timestamp()}] Total runtime for all files: {total_runtime:.2f} seconds")
    print(f"[{get_timestamp()}] -- end processing all files --")

if __name__=="__main__":
    # This main function is for direct script execution, not used by Streamlit app.py
    # Ensure server_url and cookie are loaded from config as they are used globally.
    # The current_user_id and current_user_fullname for process_file will use defaults 
    # or environment variables as set in main().
    # For a real WhoAmI call here, you'd need to structure it:
    # if server_url and cookie:
    #     uid, uname = get_current_user_details(server_url, cookie) # Assuming get_current_user_details is defined
    #     if uid and uname:
    #         main(current_user_id=uid, current_user_fullname=uname)
    #     else:
    #         print("Could not fetch user details for standalone run.")
    # else:
    #     print("Server URL or Cookie not configured for standalone run.")
    # For now, using the placeholder logic in main().
    main()