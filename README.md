# MongoDB Kafka Sync

## Overview
`setup-sync.sh` is a script that sets up a real-time data sync between two MongoDB instances using Kafka. The script automates the deployment of necessary Kafka components, registers MongoDB source and sink connectors, and ensures smooth data flow.

## Features
- Automates the setup of Kafka, Zookeeper, and Kafka Connect.
- Installs and configures MongoDB Kafka connectors.
- Registers source and sink connectors for real-time data replication.
- Supports error handling and logging.

## Prerequisites
Ensure the following dependencies are installed on your system:
- **Docker** & **Docker Compose**
- **jq** (for JSON processing)

## Installation
Clone the repository and navigate to the directory:
```bash
git clone https://github.com/SaraanshSharma/mongodb-kafka-sync.git
cd mongodb-kafka-sync
```

## Usage
Run the script:
```bash
chmod +x setup-sync.sh
./setup-sync.sh
```

### Required Inputs
The script will prompt for the following inputs:
- **Source MongoDB Connection String** (e.g., `mongodb://localhost:27017`)
- **Database Name** to watch for changes
- **Sink MongoDB Connection String** (e.g., `mongodb://localhost:27017`)
- **Source Identifier** (e.g., `store_id` for tracking changes)

### What the Script Does
1. Creates a `connect-plugins` directory with proper permissions.
2. Generates a `docker-compose.yml` file to set up Kafka, Zookeeper, and Kafka Connect.
3. Starts Kafka infrastructure using Docker Compose.
4. Waits until Kafka Connect is ready.
5. Generates and registers MongoDB source and sink connectors.
6. Displays connector status and provides useful `curl` commands for monitoring.

## Monitoring and Debugging
Check registered connectors:
```bash
curl -s http://localhost:8083/connectors | jq .
```
Check source connector status:
```bash
curl -s http://localhost:8083/connectors/mongodb-source-connector/status | jq .
```
Check sink connector status:
```bash
curl -s http://localhost:8083/connectors/mongodb-sink-connector/status | jq .
```

## Stopping and Cleaning Up
To stop and remove all containers:
```bash
sudo docker compose down
```

To remove registered connectors:
```bash
curl -X DELETE http://localhost:8083/connectors/mongodb-source-connector
curl -X DELETE http://localhost:8083/connectors/mongodb-sink-connector
```

## License
This project is licensed under the MIT License.

## Contribution
Feel free to submit issues and pull requests to improve this script.

## Author
[Saraansh Sharma](https://github.com/SaraanshSharma)

