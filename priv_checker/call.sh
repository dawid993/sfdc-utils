#!/bin/bash

# Salesforce API version
apiVersion="v61.0"

# Salesforce APIs endpoints enumeration
data_endpoint="services/data/$apiVersion/"
sobject_endpoint="services/data/$apiVersion/sobjects"
query_endpoint="services/data/$apiVersion/query/?q="

objects_filename='sObjects_access.txt'
records_filename='records_access.txt'

soql_query="SELECT+count()+FROM+"

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
    is_var_set "ADMIN_TOKEN" "$ADMIN_TOKEN"
    is_var_set "TOKEN" "$TOKEN"
}

request_sfdc() {
    local endpoint="$1"
    local authToken="$2"

    echo $(
        curl -s -w "%{http_code}" "$SFDC_URL/$endpoint" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $authToken"
    )
}

# Because calling salesforce endpoint with curl we use -w parameter 
# we append status at the end of body. 
# That function retrieves that parameter
get_resp_status() {
    echo "${1: - 3}"
}


# Because calling salesforce endpoint with curl we use -w parameter 
# we append status at the end of body. 
# This function retrieves body
get_resp_body() {
    echo "${1%???}"
}

request_query_endpoint() {
    local token="$1"
    local request_endpoint="$2"
    query_resp=$(request_sfdc "$request_endpoint" "$ADMIN_TOKEN")
    
    http_status=$(get_resp_status "$query_resp")
    http_body=$(get_resp_body "$query_resp")

    if (( http_status == 200 )); then 
        echo "$http_body"
        return 0
    else
        echo "Cannot query $request_endpoint: $http_body"
        return 1
    fi
}

enumerate_accessible_sobjects() {
    sfdc_response=$(request_sfdc "$sobject_endpoint" "$ADMIN_TOKEN")
    http_status=$(get_resp_status "$sfdc_response")
    http_body=$(get_resp_body "$sfdc_response")

    if (( http_status != 200 )); then
        exit_with_msg "Cannot enumarete sObjects: $http_body"
    else
        res=$(echo "$http_body" | jq "
        .sobjects
        | map(
            select(
                .createable     == true or 
                .updateable     == true or 
                .deletable      == true or 
                .retrieveable   == true
                )
            | {
                label: .label,
                name: .name,
                createable: .createable, 
                updateable: .updateable,
                deletable: .deletable,
                retrieveable: .retrieveable
            }
        )")
    
        sobject_count=$(echo "$res" | jq 'length')
        
        echo "We found $sobject_count which are accessible by user"
        echo "Saving into $objects_filename"
        
        echo "$res" | jq '[.[]]' > $objects_filename
    fi     
}

check_record_access() {
    if [[ ! -f $objects_filename ]]; then
        exit_with_msg "$objects_filename not found"
    fi

    echo '[' >> $records_filename

    for row in $(cat $objects_filename | jq -r '.[] | .name'); do
        request_endpoint="$query_endpoint$soql_query$row"

        admin_resp=$(request_query_endpoint "$ADMIN_TOKEN" "$request_endpoint")

        if [[ $? -eq 1 ]]; then
            echo "$admin_resp"
            continue
        fi

        admin_resp=$(echo "$admin_resp" | jq '.totalSize')
        user_resp=$(request_query_endpoint "$TOKEN" "$request_endpoint" | jq '.totalSize')

        is_diff_found=0

        if (( admin_resp != user_resp)); then
            is_diff_found=1
            printf '{\n"sObject": "%s",\n "admin": %s,\n"user": %s\r},\n' "$row" "$admin_resp" "$user_resp" >> "$records_filename"
        fi

        if ((is_diff_found == 1)); then
            echo "Found differences in record count"
        fi
    done

    echo ']' >> $records_filename
}

is_env_ready

echo "Removing files from previous run -- you have 10 seconds to cancel action"

sleep 2

rm $objects_filename $records_filename 2> /dev/null

enumerate_accessible_sobjects
check_record_access