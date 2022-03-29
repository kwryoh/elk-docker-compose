#!/bin/bash

set -euxo pipefail

#IFS=$'\n\t'

# Check exist password value
while read -r varname value; do
  if [[ -z ${value}]]; then
    echo "Set the ${varname} environment variable in the .env file";
    exit 1;
  fi
done <<___EOL___
ELASTIC_PASSWORD ${ELASTIC_PASSWORD}
KIBANA_PASSWORD ${KIBANA_PASSWORD}
LOGSTASH_PASSWORD ${LOGSTASH_PASSWORD}
BEATS_PASSWORD ${BEATS_PASSWORD}
REMOTE_MONITORING_PASSWORD ${REMOTE_MONITORING_PASSWORD}
___EOL___

# Create CA certificates
if [[ ! -f certs/ca.zip ]]; then
  echo "Creating CA";
  bin/elasticsearch-certutil ca --silent --pem -out config/certs/ca.zip;
  unzip config/certs/ca.zip -d config/certs;
fi;

# Create elasticsearch certs
if [[ ! -f certs/certs.zip ]]; then
  echo "Creating certs";
  cat <<___EOL__ > config/certs/instances.yml;
instances:
  - name: ${ES_NAME}
    dns:
      - ${ES_NAME}
      - localhost
    ip:
      - 127.0.0.1
___EOL__

  bin/elasticsearch-certutil cert --silent --pem -out config/certs/certs.zip --in config/certs/instances.yml --ca-cert config/certs/ca/ca.crt --ca-key config/certs/ca/ca.key;
  unzip config/certs/certs.zip -d config/certs;
fi;

echo "Setting file permissions"
chown -R root:root config/certs;
find . -type d -exec chmod 750 {} \;;
find . -type f -exec chmod 640 {} \;;

echo "Waiting for Elasticsearch availability";
until curl -s --cacert config/certs/ca/ca.crt https://${ES_NAME}:9200 \
  | grep -q "missing authentication credentials"; do sleep 30; done;

while read -r username password; do
  echo "Setting ${username} password";
  until \
    curl -s \
      -X POST \
      --cacert config/certs/ca/ca.crt \
      -u elastic:${ELASTIC_PASSWORD} \
      -H "Content-Type: application/json" \
      -d "{\"password\":\"${password}\"}" \
      https://${ES_NAME}:9200/_security/user/${username}/_password \
    | grep -q "^{}"; do
      sleep 10;
    done;
done <<___EOL___
kibana_system ${KIBANA_PASSWORD}
logstash_system ${LOGSTASH_PASSWORD}
beats_system ${BEATS_PASSWORD}
remote_monitoring_user ${REMOTE_MONITORING_PASSWORD}
___EOL___

echo "All done!";
