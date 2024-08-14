#!/bin/bash

# Salesforce API version
apiVersion="v61.0"

# Salesforce APIs endpoints enumeration
data_endpoint="services/data/$apiVersion/"
sobject_endpoint="services/data/$apiVersion/sobjects"

exit_with_msg() {
    echo "$1"
    exit 1
}

is_installed() {
    if ! command -v "$1" > /dev/null 2>&1; then
        exit_with_msg "$1 is missing"
    fi
}

is_var_set() {
    [[ "$2" == "" ]] && exit_with_msg "$1 is empty"
}

is_env_ready() {
    is_installed "jq"
    is_installed "curl"
    
    is_var_set "SFDC_URL" "$SFDC_URL"
    is_var_set "TOKEN" "$TOKEN"
}

request_sfdc() {
    # Execute the curl command to call the Salesforce endpoint
    # -s: Silent mode (suppress progress output)
    # -H: Add custom headers (Content-Type and Authorization)
    response=$(curl -s "$SFDC_URL/$sobject_endpoint" \
        -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN")
    
    # Output the response
    echo "$response"
}

enumerate_accessible_sobjects() {
    res=$(request_sfdc | jq "
        .sobjects
        | map(
            select(.createable == true or .updateable == true or .deletable == true or .retrieveable == true)
            | {label: .label, name: .name, createable: .createable, updateable: .updateable, deletable: .deletable, retrieveable: .retrieveable}
        )")
    
    sobject_count=$(echo "$res" | jq 'length')
    
    echo "We found $sobject_count which are accessible by user"
    echo "Saving into accessible.txt"
    
    echo "$res" | jq '.[]' > "accesible.txt"
}

is_env_ready

//enumerate_accessible_sobjects

request_sfdc | jq ".sobjects"



