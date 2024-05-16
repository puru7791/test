##### Test case 4
import json
import requests

def extract_and_add_variable(source_json_url, project_variable_json, variable_names):
    if source_json_url.startswith("http"):
        source_data = requests.get(source_json_url).json()
    else:
        with open(source_json_url, 'r') as f:
            source_data = json.load(f)

    with open(project_variable_json, 'r') as f:
        dest_data = json.load(f)

    source_environment_list = source_data["ScopeValues"]["Environments"]
    dest_environment_list = dest_data["ScopeValues"]["Environments"]

    # Creating a dictionary to store environment names with their corresponding IDs
    dest_environment_dict = {env["Id"]: env["Name"] for env in dest_environment_list}

    for variable_name in variable_names:
        existing_variables = [variable for variable in dest_data["Variables"] if variable["Name"] == variable_name]
        if existing_variables:
            for existing_variable in existing_variables:
                existing_variable_value = existing_variable["Value"]
                existing_variable_environment_ids = existing_variable["Scope"]["Environment"]
                
                # Check if the existing environment IDs match the destination environment IDs
                if set(existing_variable_environment_ids) <= set(dest_environment_dict.keys()):
                    existing_variable_environment_names = [dest_environment_dict[env_id] for env_id in existing_variable_environment_ids]
                    existing_variable_environment_names = ", ".join(existing_variable_environment_names)
                    print(f"Variable '{variable_name}' already exists in the destination '{project_variable_json}' file with Value: {existing_variable_value} and Environments: {existing_variable_environment_names}")
                break  # Stop the loop when the matching environment is found

            continue
        
        print(f"Adding the '{variable_name}' Variable property block to the destination '{project_variable_json}' file")
        extracted_data = []
        for variable in source_data["Variables"]:
            if variable.get("Name") == variable_name:
                extracted_data.append(variable)

        dest_data["Variables"].extend(extracted_data)

    with open(project_variable_json, 'w') as f:
        json.dump(dest_data, f, indent=2)

# Read source data from file
with open("${{ inputs.global_ref_json }}", 'r') as f:
    source_data = json.load(f)

# Process each source data entry
for data_entry in source_data:
    source_json_url = data_entry["global_variable_json_url"]
    variable_names = data_entry["variable_names"]
    project_variable_json = "${{ inputs.project_variable_json }}"  # Assuming same destination JSON file for all sources

    # Call function to extract and add variables to destination JSON
    if data_entry.get("copy_all"):
        all_variables = requests.get(source_json_url).json()
        variable_names.extend(variable["Name"] for variable in all_variables)

    extract_and_add_variable(source_json_url.strip(), project_variable_json, variable_names)
