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
# Function to install suricata and copy the suricata.yml file
install_suricata() {
    DISTRO=$(detect_distro)
    sudo apt install wget curl nano software-properties-common dirmngr apt-transport-https gnupg gnupg2 ca-certificates lsb-release ubuntu-keyring unzip -y
    sudo add-apt-repository ppa:oisf/suricata-stable -y
    sudo apt-get update
    sudo apt-get install suricata -y
    sudo systemctl enable suricata
    sudo systemctl stop suricata
    # community-id: true in /etc/suricata/suricata.yaml
    sudo sed -i 's/# community-id: true/community-id: true/g' /etc/suricata/suricata.yaml
    # find the line pcap: and under it, set the value of the variable interface to the device name for your system
    sudo sed -i 's/# pcap:/pcap:/g' /etc/suricata/suricata.yaml
    sudo sed -i 's/#   interface: eth0/interface: eth0/g' /etc/suricata/suricata.yaml
    # #use-mmap: yes
    sudo sed -i 's/# use-mmap: yes/use-mmap: yes/g' /etc/suricata/suricata.yaml
    # enable capture-settings
    sudo suricata-update
    sudo suricata-update list-sources
    sudo suricata-update enable-source tgreen/hunting
    sudo suricata -T -c /etc/suricata/suricata.yaml -v
    sudo systemctl start suricata
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
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose
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
    # ask for the username of the controller and the password
    read -p "Enter the username of the controller: " CONTROLLER_USERNAME
    read -p "Enter the password of the controller: " CONTROLLER_PASSWORD
    # replace CONTROLLER_IP in filebeat/filebeat.yml with the actual IP address
    sudo cp filebeat/filebeat.yml /etc/filebeat/filebeat.yml

    sudo sed -i "s/CONTROLLER_IP/$CONTROLLER_IP/g" /etc/filebeat/filebeat.yml
    # replace CONTROLLER_USERNAME in filebeat/filebeat.yml with the actual username
    sudo sed -i "s/CONTROLLER_USERNAME/$CONTROLLER_USERNAME/g" /etc/filebeat/filebeat.yml
    # replace CONTROLLER_PASSWORD in filebeat/filebeat.yml with the actual password
    sudo sed -i "s/CONTROLLER_PASSWORD/$CONTROLLER_PASSWORD/g" /etc/filebeat/filebeat.yml
    # add /var/log/suricata/eve.json to the paths in filebeat/filebeat.yml
    sudo sed -i 's/# paths:/paths:/g' /etc/filebeat/filebeat.yml
    sudo sed -i 's/#   - \/var\/log\/*.log/   - \/var\/log\/suricata\/eve.json/g' /etc/filebeat/filebeat.yml
    # enable and start the filebeat service
    sudo systemctl enable filebeat
    # enable the suricata module
    sudo filebeat modules enable suricata
    # setup the suricata module
    sudo filebeat setup
    # start the filebeat service
    sudo systemctl start filebeat

}

start_project() {
    sudo docker compose up setup
    sudo docker compose up -d
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
                install_suricata
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
