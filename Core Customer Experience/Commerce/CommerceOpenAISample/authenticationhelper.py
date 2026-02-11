import os
import requests
from dotenv import load_dotenv
from tenacity import retry, wait_random_exponential, stop_after_attempt

load_dotenv()

csu_client_id = os.getenv("CSU_CLIENT_ID")
csu_client_secret = os.getenv("CSU_CLIENT_SECRET")
csu_audience = os.getenv("CSU_AUDIENCE")
csu_tenant_id = os.getenv("CSU_TENANT_ID")


@retry(wait=wait_random_exponential(multiplier=1, max=40), stop=stop_after_attempt(3))
def get_token_from_aad():
    """Get an access token from Azure Active Directory."""
    # Construct the request URL
    url = f"https://login.microsoftonline.com/{csu_tenant_id}/oauth2/token"

    # Set the request parameters
    data = {
        "grant_type": "client_credentials",
        "client_id": csu_client_id,
        "client_secret": csu_client_secret,
        "resource": csu_audience
    }

    # Send the request to AAD
    response = requests.post(url, data=data, timeout=10)

    # Check if the request was successful
    if response.status_code == 200:
        # Extract the token from the response
        token = response.json()["access_token"]
        return token
    else:
        # Handle the error
        raise ValueError(
            f"Failed to get token from AAD. Error: {response.text}")
