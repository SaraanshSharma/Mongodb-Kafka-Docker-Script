#!/bin/bash

read -p "Enter Source MongoDB Connection String (e.g., mongodb://localhost:27017): " MONGO_URI_SOURCE
read -p "Enter Source Database Name to Watch: " DB_NAME
read -p "Enter Sink MongoDB Connection String (e.g., mongodb://localhost:27017): " MONGO_URI_SINK
read -p "Enter Source Information (e.g., store_id): " SOURCE

mkdir -p connect-plugins
sleep 1
sudo chmod 777 connect-plugins

echo "Starting Kafka infrastructure..."
sudo docker compose up -d

echo "Waiting for Kafka Connect to be ready..."
until $(curl --output /dev/null --silent --head --fail http://localhost:8083/connectors); do
  printf '.'
  sleep 5
done
echo "Kafka Connect is ready!"

sleep 4

echo "Generating Source Connector Config..."
echo '{
  "name": "mongodb-source-connector",
  "config": {
    "connector.class": "com.mongodb.kafka.connect.MongoSourceConnector",
    "connection.uri": "'$MONGO_URI_SOURCE'",
    "database":  "'$DB_NAME'",
    "topic.prefix": "mongodb",
    "poll.max.batch.size": 1000,
    "poll.await.time.ms": 5000,
    "output.format.value": "json",
    "output.format.key": "json",
    "pipeline": "[{\"$addFields\": {\"fullDocument.source\": \"'$SOURCE'\"}},{\"$match\": {\"operationType\": {\"$ne\": \"delete\"}}}]",
    "copy.existing": true,
    "copy.existing.pipeline": "[]",
    "copy.existing.queue.size": 16384,
    "errors.tolerance": "all",
    "errors.log.enable": true
  }
}' > source-connector-config.json

sleep 4

echo "Generating Sink Connector Config..."
echo '{
  "name": "mongodb-sink-connector",
  "config": {
    "connector.class": "com.mongodb.kafka.connect.MongoSinkConnector",
    "connection.uri":"'$MONGO_URI_SINK'",
    "database": "'$DB_NAME'",
    "topics.regex": "mongodb\\.'$DB_NAME'\\..*",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",
    "transforms": "extractPayload",
    "transforms.extractPayload.type": "org.apache.kafka.connect.transforms.ExtractField$Value",
    "transforms.extractPayload.field": "payload",
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "false",
    "namespace.mapper": "com.mongodb.kafka.connect.sink.namespace.mapping.FieldPathNamespaceMapper",
    "namespace.mapper.value.collection.field": "ns.coll",
    "document.id.strategy": "com.mongodb.kafka.connect.sink.processor.id.strategy.ProvidedInKeyStrategy",
    "write.strategy": "com.mongodb.kafka.connect.sink.writemodel.strategy.ReplaceOneDefaultStrategy",
    "max.num.retries": 3,
    "retries.defer.timeout": 5000,
    "change.data.capture.handler": "com.mongodb.kafka.connect.sink.cdc.mongodb.ChangeStreamHandler",
    "delete.on.null.values": true,
    "errors.tolerance": "all",
    "namespace.mapper.error.if.invalid": false,
    "errors.log.enable": true
  }
}' > sink-connector-config.json

sleep 4

echo "Removing any existing connectors..."
curl -X DELETE http://localhost:8083/connectors/mongodb-source-connector 2>/dev/null || true
curl -X DELETE http://localhost:8083/connectors/mongodb-sink-connector 2>/dev/null || true
sleep 6

echo "Registering MongoDB Source Connector..."
curl -X POST -H "Content-Type: application/json" --data @source-connector-config.json http://localhost:8083/connectors

sleep 6
echo "Registering MongoDB Sink Connector..."
curl -X POST -H "Content-Type: application/json" --data @sink-connector-config.json http://localhost:8083/connectors

echo "MongoDB connectors registered successfully!"
echo "Checking connector status:"
curl -s http://localhost:8083/connectors | jq .

echo "For detailed status on a connector, use:"
echo "curl -s http://localhost:8083/connectors/mongodb-source-connector/status | jq ."
echo "curl -s http://localhost:8083/connectors/mongodb-sink-connector/status | jq ."
