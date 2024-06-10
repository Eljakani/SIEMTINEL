# SIEMTINEL: Cloud-Based SIEM System with ELK Stack

SIEMTINEL is a Security Information and Event Management (SIEM) system designed to enhance threat detection and response capabilities. This project leverages the ELK Stack (Elasticsearch, Logstash, Kibana) integrated with Suricata, Filebeat, and Kafka, deployed in a cloud environment. Suricata is utilized for network threat detection, Filebeat and Kafka for efficient log transportation, and the ELK Stack for powerful data processing and visualization.

## Features

- Real-time log collection and processing
- Network threat detection with Suricata IDS
- Scalable log transportation with Filebeat and Kafka
- Powerful data storage, indexing, and search with Elasticsearch
- Intuitive data visualization with Kibana dashboards
- Containerized deployment with Docker and Docker Compose
- Cloud-based infrastructure

## Architecture

The SIEMTINEL system follows a distributed architecture with the following components:

1. **Sensors**: Deployed on-site to capture network traffic and logs using Suricata and Filebeat.

2. **Controller**: A centralized node running the ELK Stack (Elasticsearch, Logstash, Kibana) for data processing, analysis, and visualization.

## Installation

1. Clone the repository: `git clone https://github.com/Eljakani/SIEMTINEL.git`
2. Navigate to the project directory: `cd SIEMTINEL`
3. Follow the installation instructions in the project documentation.

## Usage

1. Deploy the sensors on-site using the provided scripts.
2. Configure the controller node and ELK Stack components.
3. Access the Kibana dashboard for real-time monitoring and analysis of security events.

## Acknowledgments

We would like to express our gratitude to the National School of Applied Sciences (ENSA Marrakech) and our supervisor, Mr. Omar Achbarou, for their invaluable support and guidance throughout this project.