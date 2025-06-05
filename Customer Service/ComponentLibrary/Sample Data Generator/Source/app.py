import streamlit as st
import json
from conversation_transcript_generator import transcript_annotation, batch_create_liveworkitems, batch_create_transcripts, batch_create_annotations, batch_close_liveworkitems, load_config as load_transcript_config, batch_create_sessions, batch_create_session_participants, SessionParticipantData, get_timestamp
from case_generator import CaseGenerator, load_config as load_case_config
import concurrent.futures
import os
import requests

# Configuration
st.set_page_config(
    page_title="Customer Service Data Generator",
    page_icon="💬",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Initialize session state for stop button
if 'processing_stopped' not in st.session_state:
    st.session_state.processing_stopped = False
if 'use_multiple_contacts' not in st.session_state:
    st.session_state.use_multiple_contacts = False

# Initialize case generator config
try:
    case_config = load_case_config()
except Exception as e:
    case_config = {
        "batch_size": 10,
        "total_records": 100,
        "server_url": "",
        "cookie": "",
        "customer_id": "",
        "randomize_days": 0
    }

# Initialize transcript generator config
try:
    transcript_config = load_transcript_config()
except Exception as e:
    transcript_config = {
        "batch_size": 10,
        "server_url": "",
        "cookie": "",
        "workstream_id": "",
        "queue_id": "",
        "randomize_days": 0
    }

# Apply custom styling
st.markdown("""
    <style>
    .stApp {
        max-width: 1200px;
        margin: 0 auto;
    }
    .main > div {
        padding: 2rem;
        border-radius: 10px;
        background-color: transparent;
        margin-bottom: 2rem;
        /* fallback color if media queries aren't supported */
        color: #212529;
    }
    /* Light mode: dark-ish text */
    @media (prefers-color-scheme: light) {
      .main > div {
        color: #212529;
      }
    }
    /* Dark mode: light text */
    @media (prefers-color-scheme: dark) {
      .main > div {
        color: #ffffff;
      }
    }
    .stButton > button {
        width: 100%;
        margin-top: 1rem;
    }
    .sidebar .stTextInput > div > div > input,
    .sidebar .stTextArea > div > div > textarea {
        background-color: #ffffff;
    }
    .stop-button {
        margin-top: 1rem;
        background-color: #dc3545 !important;
        color: white !important;
        font-weight: bold !important;
    }
    </style>
    """, unsafe_allow_html=True)

# Sidebar for configuration
with st.sidebar:
    st.header("Configuration")
    
    # Server Configuration
    st.subheader("Environment Settings")
    server_url = st.text_input("Environment URL", case_config.get("server_url", ""), help="Enter the URL of the Dynamics 365 Customer Service environment you want to use. For example, https://yourorg.crm.dynamics.com")
    cookie = st.text_area("Cookie", case_config.get("cookie", ""), height=100, help="Enter the cookie for the Dynamics 365 Customer Service environment you want to use. The app will use the cookie to authenticate with the environment. The cookie can be obtained from the browser you use to access the environment. See the README for more information.")
    
    # Common Settings
    st.subheader("Common Settings")
    # Use case_config as the primary source, fallback to transcript_config if needed
    default_randomize_days = case_config.get("randomize_days", transcript_config.get("randomize_days", 0))
    randomize_days = st.number_input(
        "Randomize Created On (Last X Days)", 
        min_value=0, 
        max_value=365, 
        value=default_randomize_days, 
        help="Set the number of past days within which the 'createdon' date of records should be randomized. 0 means use the current time."
    )
    
    st.session_state.use_multiple_contacts = st.checkbox(
        "Use Multiple Random Contacts (up to 10 most recently modified)",
        value=st.session_state.get("use_multiple_contacts", False),
        help="If checked, the app will fetch up to 10 most recently modified contacts from D365 and distribute records among them, disabling the Customer ID field below."
    )
    
    customer_id_from_input = st.text_input(
        "Customer ID (Contact)", 
        case_config.get("customer_id", ""), 
        help="Enter the Contact ID for the Dynamics 365 Customer Service environment you want to use as the Customer lookup field for Cases and Conversations. The Contact ID can be found in the URL of the Contact you want to use. Used if 'Use Multiple Random Contacts' is unchecked.",
        disabled=st.session_state.use_multiple_contacts
    )

    # Transcript Generator Settings
    st.subheader("Conversation/Transcript Generator")
    workstreamid = st.text_input("Workstream ID", transcript_config.get("workstream_id", ""), help="Enter the Workstream ID for the Dynamics 365 Customer Service environment you want to use. The Workstream ID can be found in the URL of the Workstream you want to use.")
    queueid = st.text_input("Queue ID", transcript_config.get("queue_id", ""), help="Enter the Queue ID for the Dynamics 365 Customer Service environment you want to use. The Queue ID can be found in the URL of the Queue you want to use.")
    transcript_batch_size = st.number_input("Transcript Batch Size", min_value=1, max_value=100, value=transcript_config.get("batch_size", 10), help="Enter the number of transcripts to process in each batch. The default is 10.")
    
    # Case Generator Settings
    st.subheader("Case Generator")
    case_batch_size = st.number_input("Case Batch Size", min_value=1, max_value=100, value=case_config.get("batch_size", 10), help="Enter the number of cases to generate in each batch. The default is 10.")
    total_cases = st.number_input("Total Cases to Generate", min_value=1, max_value=1000, value=case_config.get("total_records", 100))
    
    # Save configuration button
    if st.button("Save Configuration"):
        # Read existing config file first
        config_path = "config.json"
        existing_config = {
            "case_generator": {},
            "conversation_transcript_generator": {}
        }
        
        if os.path.exists(config_path):
            try:
                with open(config_path, "r") as f:
                    existing_config = json.load(f)
            except json.JSONDecodeError:
                st.warning("Existing config file is invalid. Creating a new one with the proper schema.")
        
        # Update only specific values in case_generator section
        if "case_generator" in existing_config:
            existing_config["case_generator"]["server_url"] = server_url
            existing_config["case_generator"]["cookie"] = cookie
            existing_config["case_generator"]["customer_id"] = customer_id_from_input
            existing_config["case_generator"]["batch_size"] = case_batch_size
            existing_config["case_generator"]["total_records"] = total_cases
            existing_config["case_generator"]["randomize_days"] = randomize_days
        else:
            existing_config["case_generator"] = {
                "server_url": server_url,
                "cookie": cookie,
                "customer_id": customer_id_from_input,
                "batch_size": case_batch_size,
                "total_records": total_cases,
                "randomize_days": randomize_days
            }
        
        # Update transcript generator settings in its own section
        if "conversation_transcript_generator" in existing_config:
            existing_config["conversation_transcript_generator"]["server_url"] = server_url
            existing_config["conversation_transcript_generator"]["cookie"] = cookie
            existing_config["conversation_transcript_generator"]["customer_id"] = customer_id_from_input
            existing_config["conversation_transcript_generator"]["workstream_id"] = workstreamid
            existing_config["conversation_transcript_generator"]["queue_id"] = queueid
            existing_config["conversation_transcript_generator"]["batch_size"] = transcript_batch_size
            existing_config["conversation_transcript_generator"]["randomize_days"] = randomize_days
        else:
            existing_config["conversation_transcript_generator"] = {
                "server_url": server_url,
                "cookie": cookie,
                "customer_id": customer_id_from_input,
                "workstream_id": workstreamid,
                "queue_id": queueid,
                "batch_size": transcript_batch_size,
                "randomize_days": randomize_days
            }
        
        # Save the updated config back to file
        with open(config_path, "w") as f:
            json.dump(existing_config, f, indent=4)
            
        # Update session state
        st.session_state.config = existing_config["case_generator"]
        st.success("Configuration saved!")

# Main content area
st.title("Customer Service Data Generator")
st.markdown("""
This tool helps you generate customer service data in Dynamics 365 Customer Service:
- Upload JSON files to create Conversation records with chat transcripts
- Generate synthetic Case records with realistic data
""")

# Create tabs for different functionalities
transcript_tab, case_tab = st.tabs(["Conversation Generator", "Case Generator"])

# Helper function to fetch contact IDs
def fetch_d365_contact_ids(server_url, cookie, count=10):
    """Fetch up to 'count' most recently modified contact IDs from D365"""
    try:
        # OData query to get contact IDs, ordered by most recently modified first
        url = f"{server_url}/api/data/v9.0/contacts?$select=contactid&$orderby=modifiedon desc&$top={count}"
        response = requests.get(url, headers={'Cookie': cookie, 'Accept': 'application/json'})
        
        if response.status_code == 200:
            data = response.json()
            contact_ids = [contact['contactid'] for contact in data.get('value', [])]
            return contact_ids
        else:
            st.error(f"Failed to fetch contacts: HTTP {response.status_code}")
            return []
    except Exception as e:
        st.error(f"Error fetching contacts: {str(e)}")
        return []

def get_current_user_details(server_url: str, cookie: str):
    """Get current user ID and fullname using WhoAmI request"""
    try:
        response = requests.get(
            f"{server_url}/api/data/v9.0/WhoAmI",
            headers={'Cookie': cookie, 'Accept': 'application/json'}
        )
        if response.status_code == 200:
            whoami_data = response.json()
            user_id = whoami_data.get('UserId')
            
            if user_id:
                # Fetch user details to get fullname
                user_response = requests.get(
                    f"{server_url}/api/data/v9.0/systemusers({user_id})?$select=fullname",
                    headers={'Cookie': cookie, 'Accept': 'application/json'}
                )
                if user_response.status_code == 200:
                    user_data = user_response.json()
                    fullname = user_data.get('fullname', 'Unknown User')
                    return user_id, fullname
                    
        print(f"[{get_timestamp()}] Failed to get current user details: {response.status_code}")
        return None, None
    except Exception as e:
        print(f"[{get_timestamp()}] Error in WhoAmI request: {str(e)}")
        return None, None

# Function to handle stop button click
def stop_processing():
    st.session_state.processing_stopped = True
    
with transcript_tab:
    st.header("Upload Transcripts")
    
    # File uploader
    uploaded_files = st.file_uploader(
        "Upload JSON files containing chat transcripts",
        type=["json"],
        accept_multiple_files=True
    )

    if uploaded_files:
        st.write(f"Uploaded {len(uploaded_files)} files")
        
        # Process button
        col1, col2 = st.columns([3, 1])
        with col1:
            process_button = st.button("Process Transcripts")
        
        # Reset the stop flag when starting a new process
        if process_button:
            st.session_state.processing_stopped = False
            
        if process_button:
            actual_customer_ids_to_use = []
            customer_id_source_is_multiple = False

            if st.session_state.use_multiple_contacts:
                st.write("Attempting to fetch multiple contacts from D365...")
                fetched_contact_ids = fetch_d365_contact_ids(server_url, cookie)
                if fetched_contact_ids:
                    actual_customer_ids_to_use = fetched_contact_ids
                    customer_id_source_is_multiple = True
                    st.info(f"Using {len(actual_customer_ids_to_use)} contacts fetched from D365: {', '.join(actual_customer_ids_to_use)}")
                else:
                    st.error("Failed to fetch contacts or no contacts found. Please uncheck 'Use Multiple Random Contacts' and provide a Customer ID, or ensure contacts exist in D365.")
                    st.stop()
            else:
                if not customer_id_from_input:
                    st.error("Customer ID is not provided. Please enter a Customer ID in the sidebar or select 'Use Multiple Random Contacts'.")
                    st.stop()
                actual_customer_ids_to_use = [customer_id_from_input]

            with st.spinner("Processing transcripts..."):
                progress_bar = st.progress(0)
                status_text = st.empty()
                
                # Add stop button after processing starts
                stop_container = st.empty()
                with stop_container.container():
                    if st.button("Stop Processing", key="stop_transcripts", type="primary", help="Click to stop the current processing job"):
                        stop_processing()
                        st.warning("Processing will stop after completing the current batch...")
                
                total_files = len(uploaded_files)
                for idx, uploaded_file in enumerate(uploaded_files):
                    # Check if processing has been stopped
                    if st.session_state.processing_stopped:
                        status_text.warning("Processing stopped by user.")
                        break
                        
                    try:
                        # Read the uploaded file
                        chat_data = json.load(uploaded_file)
                        
                        # Skip header if needed
                        if len(chat_data) > 0 and isinstance(chat_data[0], dict) and 'header' in chat_data[0]:
                            chat_data = chat_data[1:]
                        
                        total_records = len(chat_data)
                        status_text.text(f"Processing {uploaded_file.name}: {total_records} records")
                        
                        # Process in batches
                        count = 0
                        while count < total_records and not st.session_state.processing_stopped:
                            current_batch_size = min(transcript_batch_size, total_records - count)
                            current_batch = chat_data[count:count + current_batch_size]
                            
                            # Process transcripts
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
                            
                            # Determine customer_ids for this API call batch
                            customer_ids_for_api_call = []
                            if customer_id_source_is_multiple and actual_customer_ids_to_use:
                                for i in range(current_batch_size):
                                    # 'count' is the starting index of the current_batch within the file
                                    # 'i' is the index within the current_batch
                                    item_absolute_index_in_file = count + i
                                    customer_id_for_item = actual_customer_ids_to_use[
                                        item_absolute_index_in_file % len(actual_customer_ids_to_use)
                                    ]
                                    customer_ids_for_api_call.append(customer_id_for_item)
                            elif actual_customer_ids_to_use: # Single customer_id_from_input was provided
                                customer_ids_for_api_call = [actual_customer_ids_to_use[0]] * current_batch_size
                            else:
                                # This case should ideally be prevented by earlier checks that stop processing
                                # if no customer_id is available (neither multiple nor single).
                                st.error("Critical error: No customer ID available for transcript processing. Stopping.")
                                st.session_state.processing_stopped = True # Stop further processing
                                break # Break from the while loop for the current file
                            
                            if st.session_state.processing_stopped: # Check again if the above error path was taken
                                break

                            # Create liveworkitems
                            liveworkitem_details = batch_create_liveworkitems( # Returns list of (id, createdon_date_str)
                                server_url, cookie, queueid, workstreamid, 
                                customer_ids_for_api_call, 
                                current_batch_size,        
                                randomize_days
                            )
                            
                            if not liveworkitem_details:
                                st.error(f"Failed to create live work items for a batch in {uploaded_file.name}. Stopping processing for this file.")
                                # Potentially log more details if the batch function provides them
                                break # Stop processing current file

                            liveworkitem_ids = [detail[0] for detail in liveworkitem_details]
                            liveworkitem_createdon_dates = [detail[1] for detail in liveworkitem_details]
                            # liveworkitem_subjects = [detail[2] for detail in liveworkitem_details] # Subjects are now available if needed elsewhere

                            # Create transcripts
                            # batch_create_transcripts expects a list of (id, createdon_date, subject) tuples
                            transcript_ids = batch_create_transcripts(server_url, cookie, liveworkitem_details, current_batch_size, randomize_days)
                            
                            if len(transcript_ids) != len(liveworkitem_ids):
                                st.warning(f"Mismatch in created live work items ({len(liveworkitem_ids)}) and transcripts ({len(transcript_ids)}) for a batch in {uploaded_file.name}.")
                                # Decide on recovery or stopping. For now, continue if some transcripts were made.
                            
                            if not transcript_ids:
                                st.error(f"Failed to create transcripts for a batch in {uploaded_file.name} (associated LWIs: {', '.join(liveworkitem_ids)}). Skipping annotations and sessions for this batch.")
                                # Continue to next batch or stop file processing if critical
                            else:
                                # Create sessions
                                if liveworkitem_details: # Ensure we have details to create sessions
                                    session_details_list = batch_create_sessions(
                                        server_url, cookie,
                                        liveworkitem_details, # Pass list of (id, createdon_date, subject) tuples
                                        current_batch_size,
                                        randomize_days
                                    )
                                    if len(session_details_list) != len(liveworkitem_ids):
                                        st.warning(f"Mismatch in created live work items ({len(liveworkitem_ids)}) and sessions ({len(session_details_list)}) for a batch in {uploaded_file.name}.")
                                    
                                    # Create session participants
                                    if session_details_list:
                                        # Get current user details for session participants
                                        current_user_id, current_user_fullname = get_current_user_details(server_url, cookie)
                                        if current_user_id and current_user_fullname:
                                            print(f"[{get_timestamp()}] Creating session participants for user {current_user_fullname} ({current_user_id})")
                                            participant_data_for_batch = [
                                                SessionParticipantData(
                                                    session_activity_id=sess_id, 
                                                    session_created_on=sess_createdon, 
                                                    agent_id=current_user_id, 
                                                    agent_fullname=current_user_fullname,
                                                    randomize_days=randomize_days 
                                                ) for sess_id, sess_createdon in session_details_list if sess_id and sess_createdon
                                            ]
                                            if participant_data_for_batch:
                                                participant_ids = batch_create_session_participants(server_url, cookie, participant_data_for_batch, len(participant_data_for_batch))
                                                print(f"[{get_timestamp()}] Created {len(participant_ids)} session participants")
                                            else:
                                                print(f"[{get_timestamp()}] No valid session details to create participants for.")
                                        else:
                                            print(f"[{get_timestamp()}] Could not get current user details for session participants creation.")
                                    else:
                                        print(f"[{get_timestamp()}] No sessions were created, skipping session participants creation.")

                                # Create annotations
                                # Pass liveworkitem_createdon_dates to batch_create_annotations
                                annotation_ids = batch_create_annotations(server_url, cookie, transcript_ids, annotation_contents, liveworkitem_createdon_dates, current_batch_size, randomize_days)
                                if len(annotation_ids) != len(transcript_ids):
                                     st.warning(f"Mismatch in created transcripts ({len(transcript_ids)}) and annotations ({len(annotation_ids)}) for a batch in {uploaded_file.name}.")


                            # Close liveworkitems
                            if liveworkitem_ids: # Only close if LWIs were created
                                batch_close_liveworkitems(server_url, cookie, liveworkitem_ids, current_batch_size)
                            
                            count += current_batch_size
                            progress = (idx + (count / total_records)) / total_files
                            progress_bar.progress(progress)
                            status_text.text(f"Processed {count} of {total_records} records in {uploaded_file.name}")
                        
                        if st.session_state.processing_stopped:
                            status_text.warning(f"Processing stopped after {count} records in {uploaded_file.name}")
                            break
                            
                    except Exception as e:
                        st.error(f"Error processing {uploaded_file.name}: {str(e)}")
                        continue
                
                # Clear the stop button
                stop_container.empty()
                
                if st.session_state.processing_stopped:
                    st.warning("Processing was stopped before completion.")
                else:
                    status_text.text("Processing complete!")
                    st.success("All files have been processed successfully!")

with case_tab:
    st.header("Generate Cases")
    
    # Initialize case generator
    case_generator = CaseGenerator()
    
    # Add radio button for data source
    data_source = st.radio(
        "Select Case Data Source",
        ["Generate Random Cases", "Use Predefined Cases"],
        help="Choose whether to generate random Cases via non-AI methods or use predefined AI-generated Cases from case_data.json"
    )
    
    # Load predefined cases if that option is selected
    predefined_cases = None
    if data_source == "Use Predefined Cases":
        try:
            with open("case_data.json", "r") as f:
                predefined_cases = json.load(f)
                st.success(f"Loaded {len(predefined_cases['cases'])} predefined cases from case_data.json")
        except Exception as e:
            st.error(f"Error loading case_data.json: {str(e)}")
            st.stop()
    
    # Create two columns for buttons
    col1, col2 = st.columns([3, 1])
    with col1:
        generate_button = st.button("Generate Cases")
    
    # Reset the stop flag when starting a new process
    if generate_button:
        st.session_state.processing_stopped = False
    
    if generate_button:
        actual_customer_ids_to_use = []
        customer_id_source_is_multiple = False

        if st.session_state.use_multiple_contacts:
            st.write("Attempting to fetch multiple contacts from D365...")
            fetched_contact_ids = fetch_d365_contact_ids(server_url, cookie)
            if fetched_contact_ids:
                actual_customer_ids_to_use = fetched_contact_ids
                customer_id_source_is_multiple = True
                st.info(f"Using {len(actual_customer_ids_to_use)} contacts fetched from D365: {', '.join(actual_customer_ids_to_use)}")
            else:
                st.error("Failed to fetch contacts or no contacts found. Please uncheck 'Use Multiple Random Contacts' and provide a Customer ID, or ensure contacts exist in D365.")
                st.stop()
        else:
            if not customer_id_from_input:
                st.error("Customer ID is not provided. Please enter a Customer ID in the sidebar or select 'Use Multiple Random Contacts'.")
                st.stop()
            actual_customer_ids_to_use = [customer_id_from_input]
            
        with st.spinner("Generating cases..."):
            progress_bar = st.progress(0)
            status_text = st.empty()
            
            # Add stop button after processing starts
            stop_container = st.empty()
            with stop_container.container():
                if st.button("Stop Processing", key="stop_cases", type="primary", help="Click to stop the current processing job"):
                    stop_processing()
                    st.warning("Processing will stop after completing the current batch...")
            
            try:
                # Get default subject ID
                subject_id = case_generator.get_default_subject_id(server_url, cookie)
                created_case_details = [] # Store tuples (id, createdon_str)
                
                # If using predefined cases, adjust total_cases if necessary
                if data_source == "Use Predefined Cases" and predefined_cases:
                    available_cases = len(predefined_cases['cases'])
                    if total_cases > available_cases:
                        st.warning(f"Requested {total_cases} cases but only {available_cases} predefined cases available. Will generate {available_cases} cases.")
                        total_cases = available_cases
                
                # Generate cases in batches
                case_index = 0
                for i in range(0, total_cases, case_batch_size):
                    # Check if processing has been stopped
                    if st.session_state.processing_stopped:
                        status_text.warning("Case generation stopped by user.")
                        break
                        
                    current_batch_size = min(case_batch_size, total_cases - i)
                    status_text.text(f"Processing batch {i//case_batch_size + 1} of {(total_cases + case_batch_size - 1)//case_batch_size}")
                    
                    with concurrent.futures.ThreadPoolExecutor(max_workers=current_batch_size) as executor:
                        futures = []
                        for item_in_batch_idx in range(current_batch_size):
                            customer_id_for_this_case = ""
                            if customer_id_source_is_multiple:
                                # Use overall_case_idx for cycling through customer IDs
                                overall_case_idx = i + item_in_batch_idx 
                                customer_id_for_this_case = actual_customer_ids_to_use[overall_case_idx % len(actual_customer_ids_to_use)]
                            else:
                                customer_id_for_this_case = actual_customer_ids_to_use[0]

                            if data_source == "Use Predefined Cases" and predefined_cases:
                                case_data = predefined_cases['cases'][case_index % len(predefined_cases['cases'])]
                                title = case_data['title']
                                description = case_data['description']
                                case_index += 1
                            else:
                                title = case_generator.generate_random_issue_title()
                                description = case_generator.generate_random_description(title)
                            
                            futures.append(executor.submit(
                                case_generator.create_case, 
                                title, 
                                description, 
                                subject_id, 
                                server_url, 
                                cookie, 
                                customer_id_for_this_case,
                                randomize_days
                            ))
                        
                        for future in concurrent.futures.as_completed(futures):
                            case_id, case_createdon = future.result() # Get both id and createdon
                            if case_id:
                                created_case_details.append((case_id, case_createdon)) # Store tuple
                            
                            # Update progress based on count of successfully processed futures in this batch
                            # This progress logic might need adjustment to reflect overall progress more accurately.
                            # For now, using length of created_case_details relative to total_cases.
                            progress = len(created_case_details) / total_cases
                            progress_bar.progress(progress)
                    
                    status_text.text(f"Generated {len(created_case_details)} of {total_cases} cases")
                
                # If we have cases to close and haven't been asked to stop, close them
                if created_case_details and not st.session_state.processing_stopped:
                    # Close cases in batches
                    status_text.text("Closing generated cases...")
                    total_to_close = len(created_case_details)
                    closed_count = 0
                    
                    for i in range(0, total_to_close, case_batch_size):
                        # Check if processing has been stopped
                        if st.session_state.processing_stopped:
                            status_text.warning(f"Case closing stopped after {closed_count} of {total_to_close} cases.")
                            break
                            
                        current_batch_size = min(case_batch_size, total_to_close - i)
                        
                        with concurrent.futures.ThreadPoolExecutor(max_workers=current_batch_size) as executor:
                            futures = []
                            for case_id, case_createdon in created_case_details[i:i + current_batch_size]: # Unpack tuple
                                futures.append(executor.submit(
                                    case_generator.close_case, 
                                    case_id,
                                    case_createdon, # Pass case createdon date
                                    server_url,
                                    cookie,
                                    randomize_days # Pass randomize_days setting
                                ))
                            
                            for future in concurrent.futures.as_completed(futures):
                                _ = future.result()  # Wait for completion
                                closed_count += 1
                                progress = closed_count / total_to_close
                                progress_bar.progress(progress)
                                status_text.text(f"Closed {closed_count} of {total_to_close} cases")
                
                # Clear the stop button
                stop_container.empty()
                
                if st.session_state.processing_stopped:
                    st.warning("Processing was stopped before completion.")
                    if created_case_details:
                        st.info(f"Generated {len(created_case_details)} cases before stopping.")
                else:
                    status_text.text("Case generation complete!")
                    st.success(f"Successfully generated and closed {len(created_case_details)} cases!")
                
            except Exception as e:
                # Clear the stop button on error
                stop_container.empty()
                st.error(f"Error generating cases: {str(e)}") 