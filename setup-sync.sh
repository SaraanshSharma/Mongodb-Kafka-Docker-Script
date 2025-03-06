#!/bin/bash

mkdir -p connect-plugins

echo "Starting Kafka infrastructure..."
docker-compose up -d

echo "Waiting for Kafka Connect to be ready..."
until $(curl --output /dev/null --silent --head --fail http://localhost:8083/connectors); do
  printf '.'
  sleep 5
done
echo "Kafka Connect is ready!"

echo "Registering MongoDB source connector..."
curl -X POST -H "Content-Type: application/json" --data @source-connector-config.json http://localhost:8083/connectors

echo "Registering MongoDB sink connector..."
curl -X POST -H "Content-Type: application/json" --data @sink-connector-config.json http://localhost:8083/connectors

echo "MongoDB connectors registered successfully!"
echo "Checking connector status:"
curl -s http://localhost:8083/connectors | jq .

echo "For detailed status on a connector, use:"
echo "curl -s http://localhost:8083/connectors/mongodb-source-connector/status | jq ."
echo "curl -s http://localhost:8083/connectors/mongodb-sink-connector/status | jq ."