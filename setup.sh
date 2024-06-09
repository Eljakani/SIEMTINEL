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
    echo "[+] Installing prerequisites..."
    sudo apt install wget curl nano software-properties-common dirmngr apt-transport-https gnupg gnupg2 ca-certificates lsb-release ubuntu-keyring unzip -y >/dev/null 2>&1
    echo "[+] Adding Suricata repository..."
    sudo add-apt-repository ppa:oisf/suricata-stable -y >/dev/null 2>&1
    echo "[+] Updating package lists..."
    sudo apt-get update -y >/dev/null 2>&1
    echo "[+] Installing Suricata..."
    sudo apt-get install suricata -y >/dev/null 2>&1
    sudo systemctl enable suricata >/dev/null 2>&1
    sudo systemctl stop suricata >/dev/null 2>&1
    echo "[+] Configuring Suricata..."
    sudo sed -i 's/# community-id: false/community-id: true/g' /etc/suricata/suricata.yaml
    sudo sed -i 's/# pcap:/pcap:/g' /etc/suricata/suricata.yaml
    sudo sed -i "s/interface: eth0/interface: $interface/g" /etc/suricata/suricata.yaml
    sudo sed -i 's/# use-mmap: yes/use-mmap: yes/g' /etc/suricata/suricata.yaml
    sudo suricata-update >/dev/null 2>&1
    sudo suricata-update list-sources >/dev/null 2>&1
    sudo suricata-update enable-source tgreen/hunting >/dev/null 2>&1
    sudo suricata -T -c /etc/suricata/suricata.yaml -v >/dev/null 2>&1
    sudo systemctl start suricata >/dev/null 2>&1
    echo "[+] Suricata installation and configuration completed."
}

suricata_network_setup() {
    echo "[+] Setting up Suricata network interface..."
    sudo ip link set $interface multicast off >/dev/null 2>&1
    sudo ip link set $interface promisc on >/dev/null 2>&1
    sudo ip link set $interface up >/dev/null 2>&1
}

is_valid_interface() {
    local interface="$1"
    ip link show "$interface" >/dev/null 2>&1
}

sensor_setup_info() {
    interfaces=$(ip link show | awk -F': ' '/state UP/ {print $2}')
    echo "Available network interfaces:"
    select interface in $interfaces; do
        if is_valid_interface "$interface"; then
            echo "Interface chosen: $interface"
            break
        else
            echo "Invalid interface. Please try again."
        fi
    done

    if [ -n "$interface" ]; then
        echo "Continuing with interface: $interface"
    else
        echo "No valid interface selected. Exiting."
        exit 1
    fi
}

# Function to install Docker
install_docker() {
    DISTRO=$(detect_distro)
    case "$DISTRO" in
        "ubuntu" | "debian")
            echo "[+] Installing Docker..."
            sudo apt-get update -y >/dev/null 2>&1
            sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common >/dev/null 2>&1
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - >/dev/null 2>&1
            sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" -y >/dev/null 2>&1
            sudo apt-get update -y >/dev/null 2>&1
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose >/dev/null 2>&1
            echo "[+] Docker installation completed."
            ;;
        "centos" | "rhel")
            echo "[+] Installing Docker..."
            sudo yum install -y yum-utils >/dev/null 2>&1
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null 2>&1
            sudo yum install -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1
            echo "[+] Docker installation completed."
            ;;
        "fedora")
            echo "[+] Installing Docker..."
            sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo >/dev/null 2>&1
            sudo dnf install -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1
            echo "[+] Docker installation completed."
            ;;
        *)
            echo "Unsupported distribution: $DISTRO"
            exit 1
            ;;
    esac
}

install_latest_filebeat() {
    DISTRO=$(detect_distro)
    VERSION=$(grep ELASTIC_VERSION .env | cut -d '=' -f2)
    case "$DISTRO" in
        "ubuntu" | "debian")
            echo "[+] Installing Filebeat..."
            curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$VERSION-amd64.deb >/dev/null 2>&1
            sudo dpkg -i filebeat-$VERSION-amd64.deb >/dev/null 2>&1
            echo "[+] Filebeat installation completed."
            ;;
        "centos" | "rhel" | "fedora")
            echo "[+] Installing Filebeat..."
            curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$VERSION-x86_64.rpm >/dev/null 2>&1
            sudo rpm -vi filebeat-$VERSION-x86_64.rpm >/dev/null 2>&1
            echo "[+] Filebeat installation completed."
            ;;
        *)
            echo "Unsupported distribution: $DISTRO"
            exit 1
            ;;
    esac
}

interactive_setup_filebeat() {
    echo "[+] Configuring Filebeat..."
    sudo cp filebeat/filebeat.yml /etc/filebeat/filebeat.yml
    sudo sed -i 's/# paths:/paths:/g' /etc/filebeat/filebeat.yml
    sudo sed -i 's/#   - \/var\/log\/*.log/   - \/var\/log\/suricata\/eve.json/g' /etc/filebeat/filebeat.yml
    sudo systemctl enable filebeat >/dev/null 2>&1
    sudo systemctl start filebeat >/dev/null 2>&1
    echo "[+] Filebeat configuration completed."
}

start_project() {
    echo "[+] Starting Docker project..."
    sudo docker compose up setup >/dev/null 2>&1
    sudo mkdir -p /etc/logstash/pipeline
    sudo cp logstash/pipeline/logstash.conf /etc/logstash/pipeline/logstash.conf
    sudo docker compose up -d >/dev/null 2>&1
    echo "[+] Docker project started."
}

install_kafka() {
    echo "[+] Installing Kafka..."
    sudo docker compose -f kafka/docker-compose.yml up -d >/dev/null 2>&1
    echo "[+] Kafka installation completed."
}

show_linking_instructions() {
    echo "To link the sensor to the controller, run the following command on the sensor:"
    echo "The IP address of the chosen interface is: $(ip -4 addr show $interface | grep -oP '(?<=inet\s)\d+(\.\d+){3}')"
}

pre_setup() {
    echo "[+] Setting up the environment..."
    # get the public IP address of the machine
    public_ip=$(curl -s ifconfig.me)
    # set the public IP address in the place of <your_host_ip> in the ./kafka/docker-compose.yml file and the ./filebeat/filebeat.yml file
    sudo sed -i "s/<your_host_ip>/$public_ip/g" kafka/docker-compose.yml
    sudo sed -i "s/<your_host_ip>/$public_ip/g" filebeat/filebeat.yml
    echo "[+] Environment setup completed."
}

install_logstash() {
    DISTRO=$(detect_distro)
    VERSION=$(grep ELASTIC_VERSION .env | cut -d '=' -f2)
    case "$DISTRO" in
        "ubuntu" | "debian")
            echo "[+] Installing Logstash..."
            curl -L -O https://artifacts.elastic.co/downloads/logstash/logstash-$VERSION-amd64.deb >/dev/null 2>&1
            sudo dpkg -i logstash-$VERSION-amd64.deb >/dev/null 2>&1
            echo "[+] Logstash installation completed."
            ;;
        "centos" | "rhel" | "fedora")
            echo "[+] Installing Logstash..."
            curl -L -O https://artifacts.elastic.co/downloads/logstash/logstash-$VERSION-x86_64.rpm >/dev/null 2>&1
            sudo rpm -vi logstash-$VERSION-x86_64.rpm >/dev/null 2>&1
            echo "[+] Logstash installation completed."
            ;;
        *)
            echo "Unsupported distribution: $DISTRO"
            exit 1
            ;;
    esac
}

configure_logstash() {
    echo "[+] Configuring Logstash..."
    sudo cp logstash/logstash.yml /etc/logstash/logstash.yml
    sudo cp logstash/logstash.conf /etc/logstash/pipeline.conf
    sudo systemctl enable logstash >/dev/null 2>&1
    sudo systemctl start logstash >/dev/null 2>&1
    echo "[+] Logstash configuration completed."
}
create_logstash_config_alias() {
    echo "[+] Creating Logstash config alias..."
    # copy the logstash_config.sh file to the /usr/local/bin directory
    sudo cp logstash_config.sh /usr/local/bin/logstash_config
    sudo chmod +x /usr/local/bin/logstash_config
    # create a simple alias for the logstash_config.sh script
    echo "alias siemcc='/usr/local/bin/logstash_config'" >> ~/.bashrc
    source ~/.bashrc
    echo "[+] Logstash config alias created. You can now use the 'siemcc' command."
}

main() {
    choice=$(whiptail --title "Machine Type" --menu "Is this machine a controller or a sensor?" 15 60 2 \
        "1" "Controller" \
        "2" "Sensor" \
        3>&1 1>&2 2>&3)
    case $choice in
        1)
            install_docker
            start_project
            create_logstash_config_alias
            ;;
        2)
            pre_setup
            sensor_setup_info
            install_suricata
            suricata_network_setup
            install_latest_filebeat
            interactive_setup_filebeat
            install_docker
            install_kafka
            show_linking_instructions
            ;;
        *)
            echo "Invalid choice"
            ;;
    esac
}

main
