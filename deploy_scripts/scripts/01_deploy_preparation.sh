#!/bin/bash

set -eu

cd $(dirname $0) && cd ../../

trap 'echo Error Occurred!!! Exit...' ERR

CFN_TEMPLATE="./deploy_scripts/resources/preparation.yaml"
SESSION_MANAGER_RUN_SHELL_CONTENT_PATH="./deploy_scripts/sessionManagerRunShell.json"

DEPLOYMODE="on"
PROFILE=""
APPNAME="Bastion"
REGION="ap-northeast-1"

while getopts p:d: OPT; do
	case $OPT in
		p)
			PROFILE="$OPTARG"
			;;
		d)
			DEPLOYMODE="$OPTARG"
			;;
	esac
done

if [ "${DEPLOYMODE}" != "on" -a "${DEPLOYMODE}" != "off" ]; then
	echo "required DEPLOYMODE"
	echo "[-p (profile)](option): aws profile name"
	echo "[-d on|off](option): deploy mode (off=change set mode)"
	exit 0
fi

function deployPreparation {
	local profileOption=""

	if [ -n "${1:-}" ]; then
		profileOption="--profile ${profile}"
	fi

	local repositoryName=$(echo "${APPNAME}-ECR" | tr '[:upper:]' '[:lower:]')
	local stackName="${APPNAME}-Preparation"


	local changesetOption="--no-execute-changeset"

	if [ "${DEPLOYMODE}" == "on" ]; then
		echo "deploy mode"
		changesetOption=""
	fi

	aws cloudformation deploy \
		--stack-name ${stackName} \
		--region ${REGION} \
		--template-file ${CFN_TEMPLATE} \
		--capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
		--no-fail-on-empty-changeset \
		${changesetOption} \
		--parameter-overrides \
		AppName=${APPNAME} \
		RepositoryName=${repositoryName} \
		${profileOption}

	if [ "${DEPLOYMODE}" == "on" ]; then
		local accountId=$(aws sts get-caller-identity --query "Account" --output text ${profileOption})
		local settingId="arn:aws:ssm:${REGION}:${accountId}:servicesetting/ssm/managed-instance/activation-tier"
		local settingValue=$(aws ssm get-service-setting --setting-id ${settingId} ${profileOption} | jq -r .ServiceSetting.settingValue)
		if [ "${settingValue}" == "standard" ]; then
			aws ssm update-service-setting \
				--setting-id ${settingId} \
				--setting-value advanced \
				${profileOption}
		fi

		local documentCount=$( \
			aws ssm list-documents \
				--filters Key=Name,Values=SSM-SessionManagerRunShell \
				${profileOption} \
			| jq '.DocumentIdentifiers|length' \
		)

		if [ ${documentCount} -eq 0 ]; then
			aws ssm create-document \
				--name "SSM-SessionManagerRunShell" \
				--content "file://${SESSION_MANAGER_RUN_SHELL_CONTENT_PATH}" \
				--document-type "Session" \
				${profileOption} > /dev/null
		else
			local currentSessionManagerRunShellDocument=$( \
				aws ssm get-document \
					--name "SSM-SessionManagerRunShell" \
					--document-version \$LATEST \
					${profileOption} \
				| jq -r .Content \
				| jq -c . \
			)
			local newSessionManagerRunShellDocument=$( \
				cat "${SESSION_MANAGER_RUN_SHELL_CONTENT_PATH}" \
				| jq -c '.' \
			)

			if [ "${currentSessionManagerRunShellDocument}" != "${newSessionManagerRunShellDocument}" ]; then
				aws ssm update-document \
					--name "SSM-SessionManagerRunShell" \
					--content "file://${SESSION_MANAGER_RUN_SHELL_CONTENT_PATH}" \
					--document-version "\$LATEST" \
					${profileOption} > /dev/null
			fi
		fi
	fi
}

deployPreparation "${PROFILE:-}"
