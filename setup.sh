#!/bin/bash

# Function to detect the Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    elif type lsb_release >/dev/null 2>&1; then
        DISTRO=$(lsb_release -si)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        DISTRO=$DISTRIB_ID
    elif [ -f /etc/debian_version ]; then
        DISTRO='Debian'
    else
        DISTRO='Unknown'
    fi
    echo $DISTRO
}

# Function to install Docker
install_docker() {
    DISTRO=$(detect_distro)
    case "$DISTRO" in
        "ubuntu" | "debian")
            sudo apt-get update
            sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
            sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io
            ;;
        "centos" | "rhel")
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io
            ;;
        "fedora")
            sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            sudo dnf install -y docker-ce docker-ce-cli containerd.io
            ;;
        *)
            echo "Unsupported distribution: $DISTRO"
            exit 1
            ;;
    esac
}

install_and_setup_suricata() {
    DISTRO=$(detect_distro)
    case "$DISTRO" in
        "ubuntu" | "debian")
            sudo apt-get update
            sudo add-apt-repository ppa:oisf/suricata-stable
            sudo apt-get install -y suricata
            sudo systemctl enable suricata
            sudo cp suricata/suricata.yaml /etc/suricata/suricata.yaml
            sudo suricata -T -c /etc/suricata/suricata.yaml -v
            ;;
        "centos" | "rhel")
            sudo yum install -y epel-release
            sudo yum install -y suricata
            sudo systemctl enable suricata
            sudo cp suricata/suricata.yaml /etc/suricata/suricata.yaml
            sudo suricata -T -c /etc/suricata/suricata.yaml -v
            ;;
        "fedora")
            sudo dnf install -y suricata
            sudo systemctl enable suricata
            sudo cp suricata/suricata.yaml /etc/suricata/suricata.yaml
            sudo suricata -T -c /etc/suricata/suricata.yaml -v
            ;;
        *)
            echo "Unsupported distribution: $DISTRO"
            exit 1
            ;;
    esac
}
install_latest_filebeat() {
    # get the version of filebeat from .env file 
    DISTRO=$(detect_distro)
    VERSION=$(grep ELASTIC_VERSION .env | cut -d '=' -f2)
    case "$DISTRO" in
        "ubuntu" | "debian")
            curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$VERSION-amd64.deb
            sudo dpkg -i filebeat-$VERSION-amd64.deb
            ;;
        "centos" | "rhel")
            curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$VERSION-x86_64.rpm
            sudo rpm -vi filebeat-$VERSION-x86_64.rpm
            ;;
        "fedora")
            curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$VERSION-x86_64.rpm
            sudo rpm -vi filebeat-$VERSION-x86_64.rpm
            ;;
        *)
            echo "Unsupported distribution: $DISTRO"
            exit 1
            ;;
    esac
}

interactive_setup_filebeat() {
    # ask for the ip address of the controller
    read -p "Enter the IP address of the controller: " CONTROLLER_IP
    # replace CONTROLLER_IP in filebeat/filebeat.yml with the actual IP address
    sed  "s/CONTROLLER_IP/$CONTROLLER_IP/g" filebeat/filebeat.yml > /etc/filebeat/filebeat.yml
    # enable and start the filebeat service
    sudo systemctl enable filebeat
<<<<<<< HEAD
    # enable the suricata module
    sudo filebeat modules enable suricata
    # setup the suricata module
    sudo filebeat setup
    # start the filebeat service
    sudo systemctl start filebeat

=======
    sudo systemctl start filebeat
>>>>>>> 64241f4 (finalee)
}

start_project() {
    docker compose up setup
    docker compose up -d
}

main() {
    choice=""
    while [[ "$choice" != "1" && "$choice" != "2" ]]; do
        echo "[+] Is this machine a controller or a sensor?"
        echo "1. Controller"
        echo "2. Sensor"
        read -p "Enter your choice: " choice
        case $choice in
            1)
                install_docker
                start_project
                ;;
            2)
                install_and_setup_suricata
                install_latest_filebeat
                interactive_setup_filebeat
                ;;
            *)
                echo "Invalid choice"
                ;;
        esac
    done
}

main