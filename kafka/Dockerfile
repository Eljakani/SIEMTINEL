# Use the official Bitnami Kafka image as the base image
FROM bitnami/kafka:latest

# Expose the Kafka port
EXPOSE 9092

# Define default environment variables
ENV KAFKA_CFG_BROKER_ID=1
ENV KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper:2181
ENV KAFKA_CFG_LISTENERS=PLAINTEXT://:9092
ENV KAFKA_CFG_ADVERTISED_LISTENERS=PLAINTEXT://localhost:9092
ENV KAFKA_CFG_LOG_DIRS=/bitnami/kafka/data

# Start Kafka server
CMD ["/opt/bitnami/scripts/kafka/run.sh"]
