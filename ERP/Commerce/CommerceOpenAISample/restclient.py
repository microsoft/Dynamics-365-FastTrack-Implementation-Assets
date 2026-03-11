"""Rest API client class."""
import requests
from requests.adapters import HTTPAdapter
from urllib3.util import Retry


class RestAPIClient:
    """Class to interact with a REST API."""

    def send_request(self, method, base_url, endpoint, headers, params, payload=None):
        """Send a request to the API with retry logic."""
        # Define the retry strategy
        retry_strategy = Retry(
            total=3,  # Maximum number of retries
            backoff_factor=1,  # Exponential backoff factor
            # HTTP status codes to retry on
            status_forcelist=[500, 502, 503, 504]
        )

        # Create a session with the retry strategy
        session = requests.Session()
        session.mount(base_url, HTTPAdapter(max_retries=retry_strategy))

        # Send the request with retry logic
        if method == "GET":
            response = session.get(base_url + endpoint, params=params,
                                   headers=headers, json=payload)
        elif method == "POST":
            response = session.post(base_url + endpoint, params=params,
                                    headers=headers, json=payload)

        # Check the response status code
        if response.status_code == 200 or response.status_code == 204:
            # Request was successful
            if response.text:
                data = response.json()
            else:
                data = None

        else:
            # Request failed
            print("Request failed with status code:", response.status_code)
            raise ValueError("Request failed")
        return data
