"""Module to generate AI responses."""
import os
import json
from dotenv import load_dotenv
from openai import AzureOpenAI
from products import ProductsModel


class AIResponseGenerator:
    """Class to generate responses."""
    _instance = None

    def __new__(cls, session_messages, *args, **kwargs):
        if cls._instance is None:
            cls._instance = super().__new__(cls, *args, **kwargs)
        return cls._instance

    def __init__(self, session_messages=None):
        load_dotenv()
        self.api_key = os.getenv("AZURE_OPENAI_API_KEY")
        self.api_endpoint = os.getenv("AZURE_OPENAI_ENDPOINT")
        self.api_version = os.getenv("AZURE_OPENAI_ENDPOINT")
        self.deployment_name = os.getenv("DEPLOYMENT_NAME")

        if self.api_endpoint is None:
            raise ValueError(
                "Please set the AZURE_OPENAI_ENDPOINT environment variable.")

        if self.api_key is None:
            raise ValueError(
                "Please set the AZURE_OPENAI_API_KEY environment variable.")

        if self.api_version is None:
            raise ValueError(
                "Please set the AZURE_OPENAI_VERSION environment variable.")

        if self.deployment_name is None:
            raise ValueError(
                "Please set the DEPLOYMENT_NAME environment variable.")

        self.client = AzureOpenAI(
            api_key=self.api_key,
            api_version="2024-02-01",
            azure_endpoint=self.api_endpoint)

        self.model = ProductsModel()
        self.messages = []
        self.messages.append(
            {"role": "system", "content": """Don't make assumptions about what values
            to plug into functions.Ask for clarification if a user request is ambiguous.
            Your tone should be friendly, helpful, cheerful, and expressive.
            Always greet users warmly and use a smiley emoji.Use positive language.
            Offer your help proactively.Use emojis and exclamation marks for cheerfulness.
            Keep the conversation engaging with expressive language.
            End conversations positively."""})

        for item in session_messages:
            self.messages.append(item)

    def generate(self):
        """Generate AI response."""
        response = self.client.chat.completions.create(
            model=self.deployment_name, messages=self.messages,
            tool_choice="auto",
            tools=self.functionschema(),
            temperature=0.5
        )

        tool_calls = response.choices[0].message.tool_calls

        if tool_calls:
            available_functions = {
                self.model.search_product_text.__name__: self.model.search_product_text,
                self.model.product_details.__name__: self.model.product_details,
                self.model.product_attributes.__name__: self.model.product_attributes,
                self.model.get_product_variant_details.__name__:
                self.model.get_product_variant_details
            }
            function_response = []
            for tool_call in tool_calls:
                function_name = tool_call.function.name
                function_to_call = available_functions[function_name]
                if function_to_call is None:
                    raise ValueError(
                        f"Function {function_name} is not available.Operation is not supported")
                function_args = json.loads(
                    tool_call.function.arguments)
                result = function_to_call(
                    **function_args
                )
                tool_response = {"role": "function", "tool_call_id": tool_call.id,
                                 "name": function_name, "content": result}
                self.messages.append(tool_response)
                function_response.append(tool_response)
            return function_response
        else:
            return response.choices[0].message.content

    def extractsummary(self):
        """Extract the summary from the response."""
        response = self.client.chat.completions.create(
            model=self.deployment_name, messages=self.messages,
            temperature=0.5
        )
        return response.choices[0].message.content

    def functionschema(self):
        """Get the schema for the functions."""

        functions = [
            {
                "type": "function",
                "function": {"name": f"{self.model.search_product_text.__name__}",
                             "description": f"{self.model.search_product_text.__doc__}",
                             "parameters": {
                    "type": "object",
                    "properties": {
                        "search_text": {
                            "type": "string",
                            "description": "The text used to search products by name"
                        }
                    },
                    "required": ["search_text"],
                }
                }
            },
            {
                "type": "function",
                "function": {"name": f"{self.model.product_details.__name__}",
                             "description": f"{self.model.product_details.__doc__}",
                             "parameters": {
                    "type": "object",
                    "properties": {
                        "product_recordid": {
                            "type": "string",
                            "description": "The product record id. The product record id is the unique identifier for the product."
                        }
                    },
                    "required": ["product_recordid"],
                }
                }
            },
            {
                "type": "function",
                "function": {"name": f"{self.model.product_attributes.__name__}",
                             "description": f"{self.model.product_attributes.__doc__}",
                             "parameters": {
                    "type": "object",
                    "properties": {
                        "product_recordid": {
                            "type": "string",
                            "description": "The product record id. The product record id is the unique identifier for the product."
                        }
                    },
                    "required": ["product_recordid"],
                }
                }
            },
            {
                "type": "function",
                "function": {"name": f"{self.model.get_product_variant_details.__name__}",
                             "description": f"{self.model.get_product_variant_details.__doc__}",
                             "parameters": {
                    "type": "object",
                    "properties": {
                        "product_recordid": {
                            "type": "string",
                            "description": "The product record id. The product record id is the unique identifier for the product."
                        }
                    },
                    "required": ["product_recordid"],
                }
                }
            }
        ]
        return functions
