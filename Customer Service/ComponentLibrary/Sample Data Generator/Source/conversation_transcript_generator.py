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
        
        # Determine if it's a control message or normal message
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

def batch_create_liveworkitems(server_url: str, cookie: str, queueid: str, workstreamid: str, customer_id: str, batch_size: int = 10, randomize_days: int = 0) -> List[str]:
    """Create liveworkitems in batches and return their IDs"""
    liveworkitem_ids = []
    
    def create_single_liveworkitem():
        liveworkitemid = str(uuid.uuid4())
        
        # Fetch dynamic names, fall back to defaults
        contact_name = get_contact_fullname(server_url, cookie, customer_id) or "Visitor"
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
        
        # Add customer id if provided
        if customer_id:
            liveworkitem_request["regardingobjectid_contact_msdyn_ocliveworkitem@odata.bind"] = f"/contacts({customer_id})"
        
        # Add overriddencreatedon if randomize_days > 0
        if randomize_days > 0:
            past_date = generate_random_past_date(randomize_days)
            liveworkitem_request["overriddencreatedon"] = past_date
            # print(f"[{get_timestamp()}] LiveWorkItem {liveworkitemid} overriddencreatedon set to: {past_date}")
            
        response = requests.post(server_url + '/api/data/v9.0/msdyn_ocliveworkitems', 
                               json=liveworkitem_request, 
                               headers={'Cookie': cookie})
        if response.status_code == 204 or response.status_code == 201:
            return liveworkitemid
        print(f"[{get_timestamp()}] Failed to create liveworkitem: {response.status_code}. Response: {response.text}")
        return None

    with concurrent.futures.ThreadPoolExecutor(max_workers=batch_size) as executor:
        futures = [executor.submit(create_single_liveworkitem) for _ in range(batch_size)]
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            if result:
                liveworkitem_ids.append(result)

    return liveworkitem_ids

def batch_create_transcripts(server_url: str, cookie: str, liveworkitem_ids: List[str], batch_size: int = 10, randomize_days: int = 0) -> List[str]:
    """Create transcripts in batches and return their IDs"""
    transcript_ids = []
    
    def create_single_transcript(liveworkitem_id: str):
        transcriptid = str(uuid.uuid4())
        transcript_request = {
            "msdyn_transcriptid": transcriptid,
            "msdyn_LiveWorkItemIdId@odata.bind": "/msdyn_ocliveworkitems(" + liveworkitem_id + ")"
        }
        
        # Add overriddencreatedon if randomize_days > 0
        if randomize_days > 0:
            # Use the same random date logic, potentially link it or ensure consistency if needed
            past_date = generate_random_past_date(randomize_days) 
            transcript_request["overriddencreatedon"] = past_date
            # print(f"[{get_timestamp()}] Transcript {transcriptid} overriddencreatedon set to: {past_date}")
            
        response = requests.post(server_url + '/api/data/v9.0/msdyn_transcripts', 
                               json=transcript_request, 
                               headers={'Cookie': cookie})
        if response.status_code == 204 or response.status_code == 201:
            return transcriptid
        print(f"[{get_timestamp()}] Failed to create transcript: {response.status_code}")
        return None

    with concurrent.futures.ThreadPoolExecutor(max_workers=batch_size) as executor:
        futures = [executor.submit(create_single_transcript, liveworkitem_id) 
                  for liveworkitem_id in liveworkitem_ids]
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            if result:
                transcript_ids.append(result)

    return transcript_ids

def batch_create_annotations(server_url: str, cookie: str, 
                           transcript_ids: List[str], 
                           annotation_contents: List[str], 
                           batch_size: int = 10, randomize_days: int = 0) -> List[str]:
    """Create annotations in batches and return their IDs"""
    annotation_ids = []
    
    def create_single_annotation(transcript_id: str, annotation_content: str):
        annotationid = str(uuid.uuid4())
        annotation_request = {
            "annotationid": annotationid,
            "mimetype": "text/plain",
            "documentbody": annotation_content,
            "objecttypecode": "msdyn_transcript",
            "objectid_msdyn_transcript@odata.bind": "/msdyn_transcripts(" + transcript_id + ")",
            "isdocument": True,
            "subject": "Visitor: Test Chat workstream",
            "filename": "Messages_file.txt"
        }
        
        # Add overriddencreatedon if randomize_days > 0
        if randomize_days > 0:
            past_date = generate_random_past_date(randomize_days)
            annotation_request["overriddencreatedon"] = past_date
            # print(f"[{get_timestamp()}] Annotation {annotationid} overriddencreatedon set to: {past_date}")

        response = requests.post(server_url + '/api/data/v9.0/annotations', 
                               json=annotation_request, 
                               headers={'Cookie': cookie})
        if response.status_code == 204 or response.status_code == 201:
            return annotationid
        print(f"[{get_timestamp()}] Failed to create annotation: {response.status_code}")
        return None

    with concurrent.futures.ThreadPoolExecutor(max_workers=batch_size) as executor:
        futures = [executor.submit(create_single_annotation, transcript_id, content) 
                  for transcript_id, content in zip(transcript_ids, annotation_contents)]
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            if result:
                annotation_ids.append(result)

    return annotation_ids

def batch_close_liveworkitems(server_url: str, cookie: str, liveworkitem_ids: List[str], batch_size: int = 10):
    """Close liveworkitems in batches"""
    def close_single_liveworkitem(liveworkitem_id: str):
        close_request = {
            "statecode": 1,
            "statuscode": 4
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

def process_file(json_filepath: str):
    """Process a single JSON file"""
    start_time = time.time()
    print(f'[{get_timestamp()}] -- start processing {json_filepath} --')

    # Load the JSON file
    with open(json_filepath, 'r', encoding="utf8") as jsonfile:
        chat_data = json.load(jsonfile)
    
    # Skip header if needed
    if len(chat_data) > 0 and isinstance(chat_data[0], dict) and 'header' in chat_data[0]:
        chat_data = chat_data[1:]
    
    total_records = len(chat_data)
    print(f"[{get_timestamp()}] Found {total_records} records to process in {json_filepath}")
    
    # Process chats in batches
    batch_size = 100  # Adjust this based on your needs
    count = 0
    processed_chats = []
    
    while count < total_records:
        current_batch_size = min(batch_size, total_records - count)
        current_batch = chat_data[count:count + current_batch_size]
        
        # Process transcripts for current batch
        annotation_contents = []
        for chat in current_batch:
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
        
        # Create liveworkitems in batch
        print(f"[{get_timestamp()}] Creating batch of {current_batch_size} liveworkitems...")
        liveworkitem_ids = batch_create_liveworkitems(server_url, cookie, queueid, workstreamid, CUSTOMER_ID, current_batch_size, RANDOMIZE_DAYS)
        print(f"[{get_timestamp()}] Created {len(liveworkitem_ids)} liveworkitems")
        
        # Create transcripts in batch
        print(f"[{get_timestamp()}] Creating batch of {len(liveworkitem_ids)} transcripts...")
        transcript_ids = batch_create_transcripts(server_url, cookie, liveworkitem_ids, current_batch_size, RANDOMIZE_DAYS)
        print(f"[{get_timestamp()}] Created {len(transcript_ids)} transcripts")
        
        # Create annotations in batch
        print(f"[{get_timestamp()}] Creating batch of {len(transcript_ids)} annotations...")
        annotation_ids = batch_create_annotations(server_url, cookie, transcript_ids, annotation_contents, current_batch_size, RANDOMIZE_DAYS)
        print(f"[{get_timestamp()}] Created {len(annotation_ids)} annotations")
        
        # Close liveworkitems in batch
        print(f"[{get_timestamp()}] Closing batch of {len(liveworkitem_ids)} liveworkitems...")
        batch_close_liveworkitems(server_url, cookie, liveworkitem_ids, current_batch_size)
        print(f"[{get_timestamp()}] Closed {len(liveworkitem_ids)} liveworkitems")
        
        count += current_batch_size
        print(f"[{get_timestamp()}] Progress: Processed {count} of {total_records} chats in {json_filepath}")
    
    end_time = time.time()
    runtime = end_time - start_time
    print(f"[{get_timestamp()}] Processed {count} chats from {json_filepath}")
    print(f"[{get_timestamp()}] Runtime for {json_filepath}: {runtime:.2f} seconds")
    print(f"[{get_timestamp()}] -- end processing {json_filepath} --")

def main():
    total_start_time = time.time()
    print(f'[{get_timestamp()}] -- start processing all files --')
    
    # Process each file
    for json_file in json_files:
        try:
            process_file(json_file)
        except Exception as e:
            print(f"[{get_timestamp()}] Error processing {json_file}: {str(e)}")
            continue
    
    total_end_time = time.time()
    total_runtime = total_end_time - total_start_time
    print(f"[{get_timestamp()}] Total runtime for all files: {total_runtime:.2f} seconds")
    print(f"[{get_timestamp()}] -- end processing all files --")

if __name__=="__main__":
    main()