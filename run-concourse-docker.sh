#!/usr/bin/env bash

need_start=""
for X in concourse-db concourse-worker concourse-web;do
  if docker ps -a|grep ${X} >/dev/null;then
    docker start ${X}
  else
    need_start="${need_start} ${X}"
  fi
done

mkdir -p keys/web keys/worker

[[ ! -f ./keys/web/tsa_host_key ]] && ssh-keygen -t rsa -f ./keys/web/tsa_host_key -N ''
[[ ! -f ./keys/web/session_signing_key ]] && ssh-keygen -t rsa -f ./keys/web/session_signing_key -N ''
[[ ! -f ./keys/worker/worker_key ]] && ssh-keygen -t rsa -f ./keys/worker/worker_key -N ''

cp ./keys/worker/worker_key.pub ./keys/web/authorized_worker_keys
cp ./keys/web/tsa_host_key.pub ./keys/worker

mkdir -p ./db

export CONCOURSE_EXTERNAL_URL
CONCOURSE_EXTERNAL_URL=http://$(hostname -I|awk '{print $1}'):8080

echo "${need_start}"|grep concourse-db && docker run -d \
          -ePOSTGRES_DB=concourse \
          -ePOSTGRES_USER=concourse \
          -ePOSTGRES_PASSWORD=changeme \
          -ePGDATA=/database \
          -v"${PWD}/db":/database \
          --name concourse-db postgres:latest
echo "${need_start}"|grep concourse-worker && docker run -d \
          -eCONCOURSE_BASIC_AUTH_USERNAME=concourse \
          -eCONCOURSE_BASIC_AUTH_PASSWORD=changeme \
          -eCONCOURSE_EXTERNAL_URL="${CONCOURSE_EXTERNAL_URL}" \
					-e CONCOURSE_POSTGRES_DATA_SOURCE="postgres://concourse:changeme@concourse-db:5432/concourse?sslmode=disable" \
					--name concourse-web \
					--link concourse-db \
					-p8080:8080 \
          -v"${PWD}/keys/web:/concourse-keys" \
  				concourse/concourse web
echo "${need_start}"|grep concourse-web && docker run -d \
          -eCONCOURSE_TSA_HOST=concourse-web \
					--name concourse-worker \
					--link concourse-web \
					--privileged \
          -v"${PWD}/keys/worker:/concourse-keys" \
					concourse/concourse worker
