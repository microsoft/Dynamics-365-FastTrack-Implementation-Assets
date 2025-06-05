import os
import json
import sys
from pathlib import Path

def create_config_file():
    config = {
        "case_generator": {
            "server_url": "",
            "cookie": "",
            "customer_id": "",
            "total_records": 1000,
            "batch_size": 10
        },
        "conversation_transcript_generator": {
            "server_url": "",
            "cookie": "",
            "workstream_id": "",
            "queue_id": "",
            "batch_size": 10
        }
    }
    
    config_path = Path("config.json")
    if config_path.exists():
        print("Config file already exists. Do you want to overwrite it? (y/n)")
        if input().lower() != 'y':
            return
    
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=4)
    print(f"Created config.json. Please edit it with your settings.")

def check_python_version():
    if sys.version_info < (3, 7):
        print("Error: Python 3.7 or higher is required.")
        sys.exit(1)

def main():
    print("Setting up Customer Service Data Generator...")
    
    # Check Python version
    check_python_version()
    
    # Create config file
    create_config_file()
    
    print("\nSetup complete! Next steps:")
    print("1. Install required packages by running: pip install -r requirements.txt")
    print("2. To start the application, run: streamlit run app.py")

if __name__ == "__main__":
    main() 