#!/bin/bash

API_HOME=""
TOKEN_HOME=""
client_id=""
client_secret=""
template_webapp_id=""
console="on"

if (( $# > 1 )); then
	log_file_name=$2
else
    log_file_name="./copyWAF.log"	
fi

now=$(date +%Y%m%d%H%M%S)
export WAF_LOG_FILE=$log_file_name.$now

function log {
if [ "${console^^}" == "ON" ]; then
     printf '%s\n' "$1"
fi
     printf '%s\n' "$1">>${WAF_LOG_FILE}
}

function log_error {
     printf '%s\n' "$1"
	 printf '%s\n' "$1">>${WAF_LOG_FILE}
}

if (( $# > 0 )); then
	CONFIG_FILE=$1
	else
	CONFIG_FILE="./copyWAF.conf"
fi

if [ -f $CONFIG_FILE ]  
then 
	for line in $(<"$CONFIG_FILE"); do 
		declare $(echo ${line//[$'\t\r\n\" ']})
	done
else 
	log_error "No config file is found: $CONFIG_FILE"
fi

has_token="false"
has_template_webapp="false"
has_template_rules="false"

while [ "$has_token" == "false" ]; do
while [ "$client_id" == "" ]; do
	echo "Please enter your client_id"
	read client_id
done
while [ "$client_secret" == "" ]; do
	echo "Please enter your client_secret"
	read client_secret
done
while [ "$TOKEN_HOME" == "" ]; do
	echo "Please enter Token URL(sample: https://dojo-rc.zenedge.com/api/oauth/token )"
	read TOKEN_HOME
done

get_token="$(curl -sS -F client_id=$client_id -F client_secret=$client_secret -X POST $TOKEN_HOME )"
if [ "$?" -ne 0 ]; then 
	error_desc="curl command error" 
else
	token="$(printf '%s\n' "$get_token" | jq -r '.access_token')"
	error_desc="$(printf '%s\n' "$get_token" | jq -r '.error_description')"
	token=$(echo ${token//[$'\t\r\n']})
	error_desc=$(echo ${error_desc//[$'\t\r\n']})
fi

if [ "$token" == "null" ] || (( ${#token} == 0 )); then
	echo "Error occured: $error_desc"	
	echo "Do you want to try other client_id,client_secret or token_url? (Y)es/No, exit"
	read is_continue
	if [ "${is_continue^^}" != "Y" ]; then
		exit;
	else
		client_id=""
		client_secret=""
		TOKEN_HOME=""
		get_token=""
		token=""
	fi
else
  has_token="true"
fi
done


has_active_apps="false"
while [ "$has_active_apps" == "false" ]; do
	while [ "$API_HOME" == "" ]; do
		echo "Please enter API home url(sample: https://dojo-rc.zenedge.com/api/v2 )"
		read API_HOME
	done
apps_ids_req="$(curl -sS -X GET -H "Content-Type:application/json" -H "Authorization: Bearer $token" $API_HOME/webapps/)"
if [ "$?" -ne 0 ]; then 
	log_error "Couldn't take list of web applications, curl command error" 
else
	apps_ids=($(printf '%s\n' "$apps_ids_req" | jq -r '.[]|.id'))
	if [ ${#apps_ids[@]} == 0 ]; then
		log_error "No active web applications were found"
	else
		has_active_apps="true"
		if [ "$template_webapp_id" == "" ]; then
			echo "Do you want to see list of active applications? Y(es)/No"
			read show_app_list
				if [ "${show_app_list^^}" == "Y" ]; then
				printf '%s\n'  "Active web application list:"
				printf '%s\n'  "${apps_ids[@]}"
			fi
		fi
	fi		
fi
if [ "$has_active_apps" == "false" ]; then
echo "Do you want to try with other url parameter? (Y)es/No, exit"
	read is_continue
	if [ "${is_continue^^}" != "Y" ]; then
		exit;
	else
		API_HOME=""
		apps_ids_req=""
	fi
fi
done

while [ "$has_template_rules" == "false" ]; do
	while [ "$template_webapp_id" == "" ]; do
		echo "Please enter your template webapp_id"
		read template_webapp_id
	done

template_rules_req="$(curl -sS -X GET -H "Content-Type:application/json" -H "Authorization: Bearer $token" $API_HOME/webapps/$template_webapp_id/waf_rules)"
if [ "$?" -ne 0 ]; then 
	log_error "Couldn't take template rules for this web application, curl command error" 
else 
	error_desc="$(printf '%s\n' "$template_rules_req" | jq -r '.error_description?')"
	if [ "$error_desc" == "null" ] || (( ${#error_desc} == 0 )); then
		template_rules=($(printf '%s\n' "$template_rules_req" | jq -r '.[]|.id+";"+.value'))
		if [ ${#template_rules[@]} == 0 ]; then
			log_error "No WAF rules for web application were found"
		else
			has_template_rules="true"
		fi
	else
		log_error "API error occured with message: $error_desc"	
	fi
fi

if [ "$has_template_rules" == "false" ]; then
	echo "Do you want to try with other web aplication id? (Y)es/No, exit"
	read is_continue
	if [ "${is_continue^^}" != "Y" ]; then
		exit;
	else
		template_webapp_id=""
		template_rules_req=""
	fi
fi
done

log "+++ info: Starting update WAF by template webapp: $template_webapp_id"
for app_id in "${apps_ids[@]}"
do 
	app_id=$(echo ${app_id//[$'\t\r\n']})
    if [ "$app_id" == "$template_webapp_id" ]; then
		log "+++ info: Skip to update template webapp: $app_id"
    else
		log "+++ info: Start updating WAF rules for: $app_id"
		for rule in "${template_rules[@]}"
		do
			rule=$(echo ${rule//[$'\t\r\n']})
			rule_id=$(echo $rule | cut -d \; -f 1)
			rule_value=$(echo $rule | cut -d \; -f 2)
			update_waf_command="curl -sS --write-out ';http_code=%{http_code}' -X PUT -H \"Content-Type:application/json\" -H \"Authorization: Bearer $token\" --data-binary \"{\\\"value\\\": \\\"$rule_value\\\"}\" $API_HOME/webapps/$app_id/waf_rules/$rule_id"
			command_out="$(eval "$update_waf_command")"
			if [ "$?" -ne 0 ]; then 
				log_error  "--- err: Couldn't update WAF rule \"$rule_id\" for \"$app_id\", curl command error" 
			else 
				task_id=$(echo $command_out | cut -d \; -f 1)
				task_id="$(printf '%s\n' "$task_id" | jq -r '.task_id?')"
				task_id=$(echo ${task_id//[$'\t\r\n']})
				if [ "$task_id" == "null" ] || (( ${#task_id} == 0 )); then
					log_error "--- err: WAF rule \"$rule_id\" for \"$app_id\" was not updated!"
				    log_error "--- err: API error occured with message: $command_out"
				else
					log "WAF \"$rule_id\" updated with success."
					log "$command_out"
				fi
			fi
		done
		log "+++ info: Finish updating WAF rules for: $app_id"
	fi
done