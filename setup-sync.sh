#!/bin/bash

read -p "Enter Source MongoDB Connection String (e.g., mongodb://localhost:27017): " MONGO_URI_SOURCE
read -p "Enter Source Database Name to Watch: " DB_NAME
read -p "Enter Sink MongoDB Connection String (e.g., mongodb://localhost:27017): " MONGO_URI_SINK
read -p "Enter Source Information (e.g., store_id): " SOURCE

mkdir -p connect-plugins
sleep 1
sudo chmod 777 connect-plugins

sleep 1
echo 'services:
  zookeeper:
    image: confluentinc/cp-zookeeper:latest
    container_name: zookeeper
    ports:
      - "2181:2181"
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
    network_mode: host
    restart: always
  kafka:
    image: confluentinc/cp-kafka:latest
    container_name: kafka
    ports:
      - "9092:9092"
    depends_on:
      - zookeeper
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: localhost:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://localhost:9092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
    network_mode: host
    restart: always
    healthcheck:
      test: ["CMD", "kafka-topics", "--list", "--bootstrap-server", "localhost:9092"]
      interval: 10s
      retries: 10
  kafka-connect:
    image: confluentinc/cp-kafka-connect:latest
    container_name: kafka-connect
    dns:
      - 8.8.8.8
      - 1.1.1.1
    depends_on:
      kafka:
        condition : service_healthy
    ports:
      - "8083:8083"
    restart: always
    healthcheck:
      test: ["CMD", "kafka-topics", "--list", "--bootstrap-server", "localhost:9092"]
      interval: 10s
      retries: 10
    environment:
      CONNECT_BOOTSTRAP_SERVERS: localhost:9092
      CONNECT_REST_PORT: 8083
      CONNECT_REST_ADVERTISED_HOST_NAME: "localhost"
      CONNECT_GROUP_ID: "connect-cluster"
      CONNECT_CONFIG_STORAGE_TOPIC: "connect-configs"
      CONNECT_OFFSET_STORAGE_TOPIC: "connect-offsets"
      CONNECT_STATUS_STORAGE_TOPIC: "connect-status"
      CONNECT_MAX_REQUEST_SIZE: 10485760  
      CONNECT_PRODUCER_BATCH_SIZE: 65536
      CONNECT_FETCH_MIN_BYTES: 1048576
      CONNECT_FETCH_MAX_WAIT_MS: 500
      CONNECT_CONSUMER_MAX_POLL_RECORDS: 500
      CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_STATUS_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_KEY_CONVERTER: "org.apache.kafka.connect.json.JsonConverter"
      CONNECT_VALUE_CONVERTER: "org.apache.kafka.connect.json.JsonConverter"
      CONNECT_INTERNAL_KEY_CONVERTER: "org.apache.kafka.connect.json.JsonConverter"
      CONNECT_INTERNAL_VALUE_CONVERTER: "org.apache.kafka.connect.json.JsonConverter"
      CONNECT_PLUGIN_PATH: "/usr/share/java,/usr/share/confluent-hub-components"
      CONNECT_LOG4J_ROOT_LOGLEVEL: INFO
    volumes:
      - ./connect-plugins:/usr/share/confluent-hub-components
    network_mode: host
    command:
      - bash
      - -c
      - |
        echo "Installing MongoDB connectors..."
        confluent-hub install --no-prompt mongodb/kafka-connect-mongodb:latest
        #
        echo "Launching Kafka Connect worker..."
        /etc/confluent/docker/run
' >docker-compose.yml
sleep 2
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
}' >source-connector-config.json

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
}' >sink-connector-config.json

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
