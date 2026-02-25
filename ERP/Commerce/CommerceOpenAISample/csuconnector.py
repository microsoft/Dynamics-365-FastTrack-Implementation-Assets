"""This module contains functions to interact with the CSU Connector API."""
import os
import json
from datetime import datetime
from dotenv import load_dotenv
from restclient import RestAPIClient
from authenticationhelper import get_token_from_aad


class CSUConnector:
    """Class to interact with the CSU API."""

    _instance = None

    def __new__(cls, *args, **kwargs):
        if cls._instance is None:
            cls._instance = super().__new__(cls, *args, **kwargs)
            cls._instance.client = None
        return cls._instance

    def __init__(self):
        load_dotenv()
        self.client_url = os.getenv("CSU_URL")
        self.client_secret = os.getenv("CSU_CLIENT_SECRET")
        self.audience = os.getenv("CSU_AUDIENCE")
        self.tenant_id = os.getenv("CSU_TENANT_ID")
        self.oun = os.getenv("CSU_OUN")
        self.channelid = os.getenv("CSU_CHANNEL")
        self.catalogid = os.getenv("CSU_CATALOGID")
        self.client = RestAPIClient()
        self.token = get_token_from_aad()
        self.headers = {
            "Content-Type": "application/x-www-form-urlencoded",
            "Authorization": "id_token " + self.token,
            "OUN": self.oun
        }

    def search_product_text(self, search_text: str):
        """search for a product by text"""

        params = {
            "$top": "5",
            "api-version": "7.3",
            "@p1": f"\'{search_text}\'"
        }

        return self.client.send_request(
            "GET", self.client_url, f"Commerce/Products/SearchByText(channelId={
                self.channelid},catalogId={self.catalogid},searchText=@p1)",
            self.headers, params)

    def product_details(self, product_recordid: int):
        """Get the details of a product."""
        params = {
            "$top": "10",
            "api-version": "7.3"
        }
        return self.client.send_request(
            "GET", self.client_url, f"Commerce/Products({product_recordid})/GetById(channelId={
                self.channelid})",
            self.headers, params)

    def product_attributes(self, product_recordid):
        """Get the attributes of a product."""
        params = {
            "$top": "250",
            "$count": "true",
            "api-version": "7.3"
        }
        return self.client.send_request(
            "GET", self.client_url, f"Commerce/Products({product_recordid})/GetAttributeValues(channelId={
                self.channelid},catalogId={self.catalogid})",
            self.headers, params)
