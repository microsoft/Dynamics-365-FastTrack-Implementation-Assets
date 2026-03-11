"""Helper functions for the project."""
import json
import pandas as pd


def json_to_dataframe(json_data):
    """Convert JSON object to DataFrame."""
    # Convert JSON object to DataFrame
    df = pd.DataFrame(json_data)

    return df


def pyodbc_rowlist_to_json(rowlist):
    """Convert pyodbc row list to JSON."""
    # Convert pyodbc row list to JSON
    json_data = []
    for row in rowlist:
        json_data.append(list(row))

    return json.dumps(json_data)
