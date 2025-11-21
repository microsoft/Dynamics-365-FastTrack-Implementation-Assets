**Code cell 1 : Get values from Key Vault**

from azure.identity import DeviceCodeCredential
from azure.keyvault.secrets import SecretClient

# Configuration - Update these values from Key Vault
TENANT_ID = ""
CLIENT_ID = ""
CLIENT_SECRET = ""

key_vault_url = "https://<yourvault>.vault.azure.net/"
credential = DeviceCodeCredential(additionally_allowed_tenants=["*"])
client = SecretClient(vault_url=key_vault_url, credential=credential)
secret_name = "<TenantId>"
TENANT_ID = client.get_secret(secret_name).value
secret_name = "<ClientId>"
CLIENT_ID = client.get_secret(secret_name).value
secret_name = "<ClientSecret>"
CLIENT_SECRET = client.get_secret(secret_name).value
print(f"✅ secrets loaded")

**Code cell 2 : Get token for FnO - Lake - Azure SQL** 

from azure.identity import ClientSecretCredential
from msal import ConfidentialClientApplication

#FnO environment - make sure app added to FnO as Entra App Id
ENVIRONMENT_URL = "https://<your fno environment>.sandbox.operations.dynamics.com"

def get_access_token (scope):
   credential = ClientSecretCredential(tenant_id=TENANT_ID, client_id=CLIENT_ID, client_secret=CLIENT_SECRET)
   token = credential.get_token(scope)
   return token.token 

fno_token = get_access_token(f"{ENVIRONMENT_URL}/.default")
lake_token = get_access_token("https://api.fabric.microsoft.com/.default")
sql_token = get_access_token("https://database.windows.net/.default")
print(f"✅ tokens created")

**Code cell 3 : Merge metadata from Lake with Finance and create Azure SQL tables**

# D365 F&O Metadata Extractor - Configuration
import requests
import json
import pandas as pd
import uuid
import struct
import pyodbc
from deltalake import DeltaTable

# Parameters
TABLE_LIST = '' #use empty string to get all tables in the lakehouse
DEBUG = False

#Lakehouse setting 
WORK_SPACE = "<your workspace>"
LAKE_HOUSE = "<your lakehouse>"

# Azure SQL details
server = "<your destination Azure SQL>.database.windows.net"
database = "<your destination database>"

# Service details
SERVICE_GROUP = "AthenaFinanceOperationsTableAdapterGroup"
SERVICE_NAME = "AthenaFinanceOperationsTableAdapterService"

LANGUAGE = "en-us"

# Helper Functions
def get_fno_metadata(table_name):
    """Get metadata for a specific table"""
    url = f"{ENVIRONMENT_URL}/api/services/{SERVICE_GROUP}/{SERVICE_NAME}/getTableMetadata"
    headers = {"Authorization": f"Bearer {fno_token}", "Content-Type": "application/json"}
    
    response = requests.post(
        url, 
        headers=headers, 
        json={"tableName": table_name, "localeList": LANGUAGE, "correlationId": str(uuid.uuid4())},
        timeout=60
    )
    response.raise_for_status()

    # Parse response
    raw_metadata = response.json()
    metadata = json.loads(raw_metadata) if isinstance(raw_metadata, str) else raw_metadata
    # Extract columns with required fields: table_name, column_name, data_type, string_length
    columns = []
    for attr in metadata.get("Attributes", []):
        columns.append({
            "table_name": metadata.get("PhysicalName", table_name),
            "column_name": attr.get("PhysicalName").lower(),
            "data_type": attr.get("FieldType"),
            "string_length": attr.get("MaxLength")})
    if DEBUG:
       print (f"fno {table_name} columns : {len(columns)}")
    return columns

def get_lake_table_list():
   #Use Fabric REST API
   endpoint = f"https://api.fabric.microsoft.com/v1/workspaces/{WORK_SPACE}/lakehouses/{LAKE_HOUSE}/tables"
   headers = {
      "Authorization": f"Bearer {lake_token}",
      "Content-Type": "application/json"
   }
   response = requests.get(endpoint, headers=headers)
      
   tables = []
   # Check response
   if response.status_code == 200:
      print(f"✅ Connected to lakehouse {LAKE_HOUSE}")
      responses = response.json().get("data", [])
      for table in responses:
          table_name = table.get("name")
          if TABLE_LIST == '' or table_name in (TABLE_LIST):
              tables.append({
                 "table_name" : table_name,
                 "location" : table.get("location")
              })
   else:
       print(f"Error: {response.status_code} - {response.text}")
   if DEBUG:
      print(f"table list : {tables}")
   return tables

def get_lake_metadata (table):
   #Load Delta table
   dt = DeltaTable(table["location"])
   schema = dt.schema()
   columns = []
   for field in schema.fields:
        # Retrieve schema (column names, types, nullable info)
        columns.append({
            "table_name": table["table_name"].lower(),
            "column_name": field.name,
            "data_type": str(field.type).replace('PrimitiveType("', '').replace('")', ''),
            "nullable" : field.nullable
        })
   if DEBUG:
      print (f"lakehouse {table['table_name']} columns : {len(columns)}")
   return columns 

def get_sql_connection ():
   token_bytes = sql_token.encode("utf-16-le")
   token_struct = struct.pack("<I", len(token_bytes)) + token_bytes

   # Connection string
   conn_str = (
      f"Driver={{ODBC Driver 18 for SQL Server}};"
      f"Server=tcp:{server},1433;"
      f"Database={database};"
      f"Encrypt=yes;TrustServerCertificate=no;"
   )    

   #Connect and query
   conn = pyodbc.connect(conn_str, attrs_before={1256: token_struct})
   print(f"✅ Connected to {server}")

   return conn

def generate_sql_metadata(table):
   table_name = table["table_name"]
   fno_definition = pd.DataFrame(get_fno_metadata(table_name))
   lake_definition = pd.DataFrame(get_lake_metadata(table))
   try:
       sql_definition = pd.merge(lake_definition,fno_definition,on='column_name',how='left')
       print (f"Create metadata : {table_name}")
       if DEBUG:
          display (sql_definition)
   except:
      sql_definition = pd.DataFrame()
      print (f"Skipped table : {table_name}")

   return sql_definition

def get_fno_definition (field,length):
   if field in ("Enum","Integer") : 
      str = " integer null"
   elif field == "Int64" : 
       str = " bigint null"
   elif field in ("String","VarString"): 
       str = " nvarchar(" 
       if length == 0:
          str += "MAX) null"
       else:
          str += f"{int(length)}) null" 
   elif field == "UtcDateTime" : 
      str= " datetime null"      
   else:
      str = f" {field}"
   return str 

def get_lake_definition(field,data_type):
   if field == "Id":
      str = " uniqueidentifier null"
   elif field == "PartitionId":
      str = " varchar(20) null"
   elif data_type == "boolean":
      str = " bit null"
   elif data_type == "long":
      str = " bigint null"
   elif data_type == "timestamp":
      str = " datetime null"
   elif data_type == "string":
      str = " nvarchar(MAX) null"
   else:
      str = f" {data_type}"
   return str

def generate_sql_create_command (table_name,sql_definition):
   sql_cmd = "IF (EXISTS(SELECT object_id FROM sys.tables where name = '" + table_name + "'))\n"
   sql_cmd += "   DROP TABLE " + table_name + "\n"
   sql_cmd += "CREATE TABLE " + table_name + " (\n"
  
   for idx,row in sql_definition.iterrows(): 
       if idx > 0:
          sql_cmd += ",\n"
       sql_cmd += f"   {row.column_name}"
       if pd.isnull(row.table_name_y):
          sql_cmd += get_lake_definition(row.column_name,row.data_type_x)
       else:
          sql_cmd += get_fno_definition(row.data_type_y,row.string_length)
   sql_cmd += ' \n)\n'
   if DEBUG:
      print (sql_cmd)
   return sql_cmd

def generate_fno_tables():
   tables = get_lake_table_list()
   sql_commands = []
   for idx,table in enumerate(tables):
      try:
         sql_definition = generate_sql_metadata(table) 
         if not sql_definition.empty:
            try:
               sql_command = generate_sql_create_command (table["table_name"],sql_definition) 
               sql_commands.append(sql_command)
            except:
               print (f"  ✗ Error: table creation {table['table_name']} failed")
               continue
      except:
         continue
   return sql_commands

def create_fno_tables(sql_commands):
   conn = get_sql_connection()
   cursor = conn.cursor()
   for idx, sql_command in enumerate(sql_commands):
      try:
          cursor.execute (sql_command)
          cursor.commit()
      except:
          print (f" ✗ Error: table creation {sql_command} failed")
          continue
   cursor.close
   conn.close()
   print("✅ SQL tables created")
   return 

sql_commands = generate_fno_tables()
if not DEBUG:
   create_fno_tables(sql_commands)
