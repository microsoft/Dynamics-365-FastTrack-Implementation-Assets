import streamlit as st
import openai
from langchain.agents import create_sql_agent
from langchain_community.agent_toolkits import SQLDatabaseToolkit
from langchain.agents.agent_types import AgentType
from langchain.chat_models import AzureChatOpenAI
from langchain.sql_database import SQLDatabase
from langchain.prompts.chat import ChatPromptTemplate
from langchain.callbacks import StreamlitCallbackHandler
from sqlalchemy import create_engine
from decouple import config
import os
from dotenv import load_dotenv, find_dotenv

# Load environment variables from the .env file
load_dotenv(find_dotenv())

openai.api_type = "azure"
openai.api_base = os.getenv("AZURE_OPENAI_ENDPOINT")
openai.api_key = os.getenv("AZURE_OPENAI_API_KEY")
openai.api_version = os.getenv("OPENAI_API_VERSION")


st.title("💬 ChatD365")
st.caption("🚀 A chatbot to chat with Dynamics 365 data using OpenAI")

if "messages" not in st.session_state:
    st.session_state["messages"] = [{"role": "assistant", "content": "How can I help you?"}]

for msg in st.session_state.messages:
    st.chat_message(msg["role"]).write(msg["content"])



##########################

#create sql connection

driver = '{ODBC Driver 17 for SQL Server}'

odbc_str = 'mssql+pyodbc:///?odbc_connect=' \
                'Driver='+driver+ \
                ';Server=tcp:' + config("SQL_SERVER")+';PORT=1433' + \
                ';DATABASE=' + config("SQL_DB") + \
                ';Uid=' + config("SQL_USERNAME")+ \
                ';Pwd=' + config("SQL_PWD") + \
                ';Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;'

CUSTGROUP = "custgroup"
RETAILSTORETABLE = "retailstoretable"
RETAILTRANSACTIONTABLE = "retailtransactiontable"
RETAILTRANSACTIONSALESTRANS = "retailtransactionsalestrans"

#db_engine = create_engine(odbc_str)
#db=SQLDatabase(db_engine)

db=SQLDatabase.from_uri(odbc_str, 
                        include_tables = [CUSTGROUP, 
                                            RETAILSTORETABLE, 
                                            RETAILTRANSACTIONTABLE,
                                            RETAILTRANSACTIONSALESTRANS ], 
                        sample_rows_in_table_info=1,)


##########################

# langchain

llm = AzureChatOpenAI(deployment_name="salabcommerce-gpt35", 
                      temperature=0)

sql_toolkit=SQLDatabaseToolkit(db=db,llm=llm)
sql_toolkit.get_tools()

prompt1 = ChatPromptTemplate.from_messages(
    [
        ("system", 
         """
         You are a helpful AI assistant expert in querying SQL Database to find answers to user's question about customers, products and orders and then querying SQL Database to find answer.
         Use following context to create the SQL query. Context:
         dataareaid means the company.
         custgroup table contains information about customer groups.
         do not use tables retailsalestable and retailsalesline.
         retailtransactiontable table contains information about retail sales.
         retailtransactionsalestrans table contains information about retail sales lines and can be joined with table retailtransactiontable.
         retailtransactiontable table custaccount field means customer.
         retailtransactiontable table netamount field is sales total for the transaction.
         retailstoretable has details on retail stores.
        """
         ),
        ("user", "{question}\n ai: "),
    ]

)

agent=create_sql_agent(llm=llm,
                       toolkit=sql_toolkit,
                       agent_type=AgentType.ZERO_SHOT_REACT_DESCRIPTION,
                       verbose=True,
                       max_execution_time=100,
                       max_iterations=1000)


if prompt := st.chat_input():
    st.chat_message("user").write(prompt)    
    with st.chat_message("assistant"):
        st_callback = StreamlitCallbackHandler(st.container())
        response = agent.run(prompt1.format_prompt(question=prompt), callbacks=[st_callback])
        st.write(response)