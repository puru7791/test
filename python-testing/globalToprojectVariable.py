import json
import requests
import os

def fetch_json_from_api(url, token=None):
    headers = {}
    if token:
        headers['Authorization'] = f'token {token}'
    try:
        response = requests.get(url, headers=headers)
        response.raise_for_status()
        return response.json()
    except requests.RequestException as e:
        print(f"Error fetching JSON from API URL '{url}': {e}")
        return None

def extract_and_add_variable(source_json_url, project_variable_json, variable_names, token=None):
    source_data = fetch_json_from_api(source_json_url, token)
    if not source_data:
        print(f"Error fetching JSON from API URL '{source_json_url}'")
        return

    with open(project_variable_json, 'r') as f:
        dest_data = json.load(f)

    dest_environment_list = dest_data["ScopeValues"]["Environments"]
    dest_environment_dict = {env["Id"]: env["Name"] for env in dest_environment_list}

    for variable_name in variable_names:
        existing_variables = [variable for variable in dest_data["Variables"] if variable["Name"] == variable_name]
        if existing_variables:
            print(f"Variable '{variable_name}' already exists in the destination '{project_variable_json}' file.")
        else:
            print(f"Adding the '{variable_name}' variable property block to the destination '{project_variable_json}' file")
            extracted_data = [variable for variable in source_data if variable.get("Name") == variable_name]
            dest_data["Variables"].extend(extracted_data)

    with open(project_variable_json, 'w') as f:
        json.dump(dest_data, f, indent=2)

# Read source data from file
global_ref_json_path = os.path.join(os.getenv("GITHUB_WORKSPACE"), "${{ inputs.global_ref_json }}")
project_variable_json_path = os.path.join(os.getenv("GITHUB_WORKSPACE"), "${{ inputs.project_variable_json }}")
github_token = os.getenv("GITHUB_TOKEN")

try:
    with open(global_ref_json_path, 'r') as f:
        source_data = json.load(f)
except FileNotFoundError:
    print(f"Source data file '{global_ref_json_path}' not found.")
    exit(1)
except json.JSONDecodeError as e:
    print(f"Error decoding JSON from source data file '{global_ref_json_path}': {e}")
    exit(1)

# Process each source data entry
for data_entry in source_data:
    source_json_url = data_entry["global_variable_json_url"]
    variable_names = data_entry.get("variable_names", [])
    project_variable_json = project_variable_json_path

    # Call function to extract and add variables to destination JSON
    if data_entry.get("copy_all"):
        all_variables = fetch_json_from_api(source_json_url, github_token)
        if all_variables:
            variable_names.extend(variable["Name"] for variable in all_variables.get("Variables", []))

    extract_and_add_variable(source_json_url.strip(), project_variable_json, variable_names, github_token)
