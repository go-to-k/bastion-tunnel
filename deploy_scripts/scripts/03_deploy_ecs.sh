#!/bin/bash

set -eu

cd $(dirname $0) && cd ../../

trap 'echo Error Occurred!!! Exit...' ERR

CFN_TEMPLATE="./deploy_scripts/resources/ecs.yaml"
CONFIG_FILE_NAME="./deploy_scripts/ecs.config"

DEPLOYMODE="on"
PROFILE=""
APPNAME="Bastion"
REGION="ap-northeast-1"

VPC_ID="vpc-*****************"
SUBNET_ID1="subnet-*****************"
SUBNET_ID2="subnet-*****************"

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

function deployECS {
	local profileOption=""

	if [ -n "${1:-}" ]; then
		profileOption="--profile ${1}"
	fi

	local stackName="${APPNAME}-ECS"

	if ! [ -f "${CONFIG_FILE_NAME}" ]; then
		echo "====================================="
		echo "[${CONFIG_FILE_NAME}]ファイルがありません"
		echo "====================================="
		return 1
	fi

	source "${CONFIG_FILE_NAME}"

	if [ -z "${ECSTaskCPUUnit:-}" ] ||
		[ -z "${ECSTaskMemory:-}" ] ||
		[ -z "${ECSRestMemory:-}" ] ||
		[ -z "${ECSTaskDesiredCount:-}" ] ||
		[ -z "${TaskMinContainerCount:-}" ] ||
		[ -z "${TaskMaxContainerCount:-}" ] ||
		[ -z "${TaskMinContainerCountDuringOffPeakTime:-}" ] ||
		[ -z "${TaskMaxContainerCountDuringOffPeakTime:-}" ] ||
		[ -z "${OffPeakStartTimeCron:-}" ] ||
		[ -z "${OffPeakEndTimeCron:-}" ] ||
		[ -z "${ECSDeploymentMaximumPercent:-}" ] ||
		[ -z "${ECSDeploymentMinimumHealthyPercent:-}" ] ||
		[ -z "${ServiceScaleEvaluationPeriods:-}" ] ||
		[ -z "${ServiceCpuScaleOutThreshold:-}" ] ||
		[ -z "${ServiceCpuScaleInThreshold:-}" ]; then
		echo "コンフィグファイルに設定漏れがあります"

		echo "ECSTaskCPUUnit: ${ECSTaskCPUUnit:-}"
		echo "ECSTaskMemory: ${ECSTaskMemory:-}"
		echo "ECSRestMemory: ${ECSRestMemory:-}"
		echo "ECSTaskDesiredCount: ${ECSTaskDesiredCount:-}"
		echo "TaskMinContainerCount: ${TaskMinContainerCount:-}"
		echo "TaskMaxContainerCount: ${TaskMaxContainerCount:-}"
		echo "TaskMinContainerCountDuringOffPeakTime: ${TaskMinContainerCountDuringOffPeakTime:-}"
		echo "TaskMaxContainerCountDuringOffPeakTime: ${TaskMaxContainerCountDuringOffPeakTime:-}"
		echo "OffPeakStartTimeCron: ${OffPeakStartTimeCron:-}"
		echo "OffPeakEndTimeCron: ${OffPeakEndTimeCron:-}"
		echo "ECSDeploymentMaximumPercent: ${ECSDeploymentMaximumPercent:-}"
		echo "ECSDeploymentMinimumHealthyPercent: ${ECSDeploymentMinimumHealthyPercent:-}"
		echo "ServiceScaleEvaluationPeriods: ${ServiceScaleEvaluationPeriods:-}"
		echo "ServiceCpuScaleOutThreshold: ${ServiceCpuScaleOutThreshold:-}"
		echo "ServiceCpuScaleInThreshold: ${ServiceCpuScaleInThreshold:-}"

		return 1
	fi

	#### docker build & push
	local repositoryName=$(echo "${APPNAME}-ECR" | tr '[:upper:]' '[:lower:]')
	local accountId=$(aws sts get-caller-identity --query "Account" --output text ${profileOption})
	local repositoryEnddpoint="${accountId}.dkr.ecr.ap-northeast-1.amazonaws.com"
	local repositoryUri="${repositoryEnddpoint}/${repositoryName}"

	local ecrTag="$(git rev-parse HEAD)"

	#### parameters for ecs
	local ecsImageName="${repositoryUri}:${ecrTag}"
	local ecsAppTaskMemoryReservation=$(expr ${ECSTaskMemory} - ${ECSRestMemory})

	local s3BucketNameForECSExecLogs=$(echo "ecs-exec-logs-${APPNAME}-${accountId}" | tr '[:upper:]' '[:lower:]')

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
		VpcID="${VPC_ID}" \
		SubnetID1="${SUBNET_ID1}" \
		SubnetID2="${SUBNET_ID2}" \
		ECSTaskCPUUnit=${ECSTaskCPUUnit} \
		ECSTaskMemory=${ECSTaskMemory} \
		ECSAppTaskMemoryReservation=${ecsAppTaskMemoryReservation} \
		ECSImageName=${ecsImageName} \
		ECSTaskDesiredCount=${ECSTaskDesiredCount} \
		ECSDeploymentMaximumPercent=${ECSDeploymentMaximumPercent} \
		ECSDeploymentMinimumHealthyPercent=${ECSDeploymentMinimumHealthyPercent} \
		ServiceScaleEvaluationPeriods=${ServiceScaleEvaluationPeriods} \
		ServiceCpuScaleOutThreshold=${ServiceCpuScaleOutThreshold} \
		ServiceCpuScaleInThreshold=${ServiceCpuScaleInThreshold} \
		TaskMinContainerCount=${TaskMinContainerCount} \
		TaskMaxContainerCount=${TaskMaxContainerCount} \
		TaskMinContainerCountDuringOffPeakTime=${TaskMinContainerCountDuringOffPeakTime} \
		TaskMaxContainerCountDuringOffPeakTime=${TaskMaxContainerCountDuringOffPeakTime} \
		OffPeakStartTimeCron="${OffPeakStartTimeCron}" \
		OffPeakEndTimeCron="${OffPeakEndTimeCron}" \
		S3BucketNameForECSExecLogs=${s3BucketNameForECSExecLogs} \
		${profileOption}
}

deployECS "${PROFILE:-}"
