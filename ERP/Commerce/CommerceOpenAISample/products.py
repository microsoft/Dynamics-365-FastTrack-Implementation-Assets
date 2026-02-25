"""This module contains functions to interact with products."""
import os
import json
from functools import lru_cache
from dotenv import load_dotenv
from csuconnector import CSUConnector
from sqlconnector import SQLConnector
from helper import json_to_dataframe, pyodbc_rowlist_to_json


class ProductsModel:
    """Products model class."""

    def __init__(self):
        load_dotenv()
        self.image_base_url = os.getenv("IMAGE_BASE_URL")
        self.csuconnector = CSUConnector()
        self.sqlconnector = SQLConnector()

    @lru_cache(maxsize=128)
    def search_product_text(self, search_text):
        """Get product for given search text. Example search text is shoes, shirts,speakers etc.
        Returns list of products with ItemId,RecordId,Name, Description and other details.
        RecordId is the unique identifier for the product."""
        responsejson = self.csuconnector.search_product_text(search_text)[
            'value']
        df = json_to_dataframe(responsejson)
        df['PrimaryImageUrl'] = self.image_base_url + df['PrimaryImageUrl'] + \
            "&w=200&h=200&q=80&m=6&f=jpg&cropfocalregion=true"
        return df.to_json()

    @lru_cache(maxsize=128)
    def product_details(self, product_recordid):
        """Get the details of a product. The details include the product ItemId,Name, Description, Price.
        The RecordId is the unique identifier for the product.
        The RecordId is returned from the search_product_text function."""
        # Code to get product details
        return json.dumps(self.csuconnector.product_details(product_recordid))

    @lru_cache(maxsize=128)
    def product_attributes(self, product_recordid):
        """Get the attributes of a product.
        For example the product has an attribute of winterwear or summerwear as true."""
        # Code to get product availability
        return json.dumps(self.csuconnector.product_attributes(product_recordid))

    @lru_cache(maxsize=128)
    def get_product_variant_details(self, product_recordid):
        """Gets the top 5 product variant details. 
        The product variant details include the size, color ,style and configuration. 
        For example a product can have multiple color variants like pink,blue,red etc."""
        self.sqlconnector.connect()
        rows = self.sqlconnector.execute(
            "SELECT top 10 * FROM dbo.VARIANTINFOVIEW where PRODUCT=  ?", product_recordid
        )
        self.sqlconnector.disconnect()
        return pyodbc_rowlist_to_json(rows)
