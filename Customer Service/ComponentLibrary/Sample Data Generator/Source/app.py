import streamlit as st
import json
from conversation_transcript_generator import transcript_annotation, batch_create_liveworkitems, batch_create_transcripts, batch_create_annotations, batch_close_liveworkitems, load_config as load_transcript_config
from case_generator import CaseGenerator, load_config as load_case_config
import concurrent.futures
import os

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
    customer_id = st.text_input("Customer ID (Contact)", case_config.get("customer_id", ""), help="Enter the Contact ID for the Dynamics 365 Customer Service environment you want to use as the Customer lookup field for Cases and Conversations. The Contact ID can be found in the URL of the Contact you want to use.")

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
            existing_config["case_generator"]["customer_id"] = customer_id
            existing_config["case_generator"]["batch_size"] = case_batch_size
            existing_config["case_generator"]["total_records"] = total_cases
            existing_config["case_generator"]["randomize_days"] = randomize_days
        else:
            existing_config["case_generator"] = {
                "server_url": server_url,
                "cookie": cookie,
                "customer_id": customer_id,
                "batch_size": case_batch_size,
                "total_records": total_cases,
                "randomize_days": randomize_days
            }
        
        # Update transcript generator settings in its own section
        if "conversation_transcript_generator" in existing_config:
            existing_config["conversation_transcript_generator"]["server_url"] = server_url
            existing_config["conversation_transcript_generator"]["cookie"] = cookie
            existing_config["conversation_transcript_generator"]["customer_id"] = customer_id
            existing_config["conversation_transcript_generator"]["workstream_id"] = workstreamid
            existing_config["conversation_transcript_generator"]["queue_id"] = queueid
            existing_config["conversation_transcript_generator"]["batch_size"] = transcript_batch_size
            existing_config["conversation_transcript_generator"]["randomize_days"] = randomize_days
        else:
            existing_config["conversation_transcript_generator"] = {
                "server_url": server_url,
                "cookie": cookie,
                "customer_id": customer_id,
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
                            
                            # Create liveworkitems
                            liveworkitem_ids = batch_create_liveworkitems(server_url, cookie, queueid, workstreamid, customer_id, current_batch_size, randomize_days)
                            
                            # Create transcripts
                            transcript_ids = batch_create_transcripts(server_url, cookie, liveworkitem_ids, current_batch_size, randomize_days)
                            
                            # Create annotations
                            annotation_ids = batch_create_annotations(server_url, cookie, transcript_ids, annotation_contents, current_batch_size, randomize_days)
                            
                            # Close liveworkitems
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
        if not customer_id:
            st.error("Please provide a Customer ID in the sidebar configuration.")
            st.stop()
            
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
                        for _ in range(current_batch_size):
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
                                customer_id,
                                randomize_days
                            ))
                        
                        for future in concurrent.futures.as_completed(futures):
                            case_id, case_createdon = future.result() # Get both id and createdon
                            if case_id:
                                created_case_details.append((case_id, case_createdon)) # Store tuple
                            
                            # Update progress based on count of successfully created cases
                            progress = (i + len(created_case_details) % current_batch_size) / total_cases
                            progress_bar.progress(progress)
                    
                    status_text.text(f"Generated {len(created_case_details)} cases")
                
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