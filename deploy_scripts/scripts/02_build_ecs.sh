#!/bin/bash

set -eu

cd $(dirname $0) && cd ../../

trap 'echo Error Occurred!!! Exit...' ERR

PROFILE=""
APPNAME="Bastion"
REGION="ap-northeast-1"

while getopts p: OPT; do
	case $OPT in
	p)
		PROFILE="$OPTARG"
		;;
	esac
done

function buildECS {
	local profileOption=""

	if [ -n "${1:-}" ]; then
		profileOption="--profile ${1}"
	fi

	#### docker build & push
	local repositoryName=$(echo "${APPNAME}-ECR" | tr '[:upper:]' '[:lower:]')
	local accountId=$(aws sts get-caller-identity --query "Account" --output text ${profileOption})
	local repositoryEnddpoint="${accountId}.dkr.ecr.ap-northeast-1.amazonaws.com"
	local repositoryUri="${repositoryEnddpoint}/${repositoryName}"

	local ecrTag="$(git rev-parse HEAD)"

	local ecrTagPrevious=$(aws ecr describe-images --repository-name ${repositoryName} \
		--query "reverse(sort_by(imageDetails[*], &imagePushedAt))[0].imageTags[0]" \
		${profileOption} |
		sed -e 's/"//g')

	docker build \
		--cache-from ${ecrTagPrevious} \
		--build-arg BUILDKIT_INLINE_CACHE=1 \
		-t ${repositoryName} \
		.

	docker tag ${repositoryName}:latest ${repositoryUri}:${ecrTag}

	### Dockle
	local dockleVersion=$(
		curl --silent "https://api.github.com/repos/goodwithtech/dockle/releases/latest" |
			grep '"tag_name":' |
			sed -E 's/.*"v([^"]+)".*/\1/'
	)

	docker run \
		--rm \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v $(pwd)/.dockleignore:/.dockleignore \
		-e AWS_DEFAULT_REGION=${REGION} \
		goodwithtech/dockle:v${dockleVersion} \
		--exit-code 1 \
		--exit-level "FATAL" \
		${repositoryUri}:${ecrTag}

	aws ecr get-login-password --region ${REGION} ${profileOption} |
		docker login --username AWS --password-stdin ${repositoryEnddpoint}

	docker push ${repositoryUri}:${ecrTag}
}

buildECS "${PROFILE:-}"
