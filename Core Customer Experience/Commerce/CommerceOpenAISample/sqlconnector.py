"""SQL connector module."""

import os
import struct
from itertools import chain, repeat
import pyodbc
from azure.identity import ClientSecretCredential
from dotenv import load_dotenv


class SQLConnector:
    """SQL connector class."""
    _instance = None

    def __init__(self):
        load_dotenv()
        self.server = os.getenv("FABRIC_SERVER_NAME")
        self.database = os.getenv("FABRIC_DATABASE")
        self.tenantid = os.getenv("FABRIC_TENANTID")
        self.serviceprincipal = os.getenv("FABRIC_SERVICEPRINCIPAL")
        self.serviceprincipalsecret = os.getenv(
            "FABRIC_SERVICEPRINCIPAL_SECRET")
        self._connection = None

    def __new__(cls, *args, **kwargs):
        if cls._instance is None:
            cls._instance = super().__new__(cls, *args, **kwargs)
            cls._instance._connection = None
        return cls._instance

    def connect(self):
        """Connect to the database."""
        try:
            credential = ClientSecretCredential(
                tenant_id=self.tenantid,
                client_id=self.serviceprincipal,
                client_secret=self.serviceprincipalsecret,
            )

            conn_str = (
                f"DRIVER={{ODBC Driver 18 for SQL Server}};"
                f"SERVER={self.server};"
                f"DATABASE={self.database};"
                f"SCHEMA=dbo;"
                f"Encrypt=Yes;"
                f"TrustServerCertificate=No;"
            )

            # prepare the access token

            # Retrieve an access token valid to connect to SQL databases
            token_object = credential.get_token(
                "https://database.windows.net//.default")
            # Convert the token to a UTF-8 byte string
            token_as_bytes = bytes(token_object.token, "UTF-8")
            # # Encode the bytes to a Windows byte string
            encoded_bytes = bytes(chain.from_iterable(
                zip(token_as_bytes, repeat(0))))
            # # Package the token into a bytes object
            token_bytes = struct.pack("<i", len(encoded_bytes)) + encoded_bytes
            # # Attribute pointing to SQL_COPT_SS_ACCESS_TOKEN to pass access token to the driver
            attrs_before = {1256: token_bytes}

            # # build the connection

            self._connection = pyodbc.connect(
                conn_str, attrs_before=attrs_before)

        except pyodbc.Error as e:
            print(f"Error connecting to Azure SQL database: {str(e)}")
            return None

    def disconnect(self):
        """Disconnect from the database."""
        try:
            if self._connection is not None:
                self._connection.close()
                self._connection = None
        except pyodbc.Error as e:
            print(f"Error disconnecting from Azure SQL database: {str(e)}")

    def execute(self, query, params=None):
        """
        Execute a SQL query on the database.
        """
        if self._connection is None:
            print("Error: database connection not established")
            return None

        cursor = self._connection.cursor()
        cursor.execute(query, params)
        result = cursor.fetchall()
        cursor.close()
        return result
