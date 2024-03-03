IMAGE_NAME_NO_VER:="cthelight/snapclient"
IMAGE_NAME:=${IMAGE_NAME_NO_VER}:${TAG}


all:
	docker build -t ${IMAGE_NAME_NO_VER} .

multiarch_build_tag:
	@if [ -z ${TAG} ]; then 1>&2 echo "TAG variable not set. Aborting..."; exit 1; fi
	docker buildx build --platform linux/arm/v7,linux/arm64/v8,linux/amd64 --tag ${IMAGE_NAME} .

multiarch_build_tag_push:
	@echo -n "Are you sure (Tagging as ${IMAGE_NAME})? [y/N] " && read ans && if ! [ $${ans:-'N'} = 'y' ]; then 1>&2 echo "Aborting..."; exit 1; fi
	@if [ -z ${TAG} ]; then 1>&2 echo "TAG variable not set. Aborting..."; exit 1; fi 
	docker buildx build --platform linux/arm/v7,linux/arm64/v8,linux/amd64 --tag ${IMAGE_NAME} --push .
