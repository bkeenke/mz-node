#!/bin/bash
set -e

INSTALL_DIR="/opt"
if [ -z "$APP_NAME" ]; then
    APP_NAME="node"
fi
APP_DIR="$INSTALL_DIR/$APP_NAME"
DATA_DIR="/var/lib/$APP_NAME"
COMPOSE_FILE="$APP_DIR/docker-compose.yml"

colorized_echo() {
    local color=$1
    local text=$2
    
    case $color in
        "red")
        printf "\e[91m${text}\e[0m\n";;
        "green")
        printf "\e[92m${text}\e[0m\n";;
        "yellow")
        printf "\e[93m${text}\e[0m\n";;
        "blue")
        printf "\e[94m${text}\e[0m\n";;
        "magenta")
        printf "\e[95m${text}\e[0m\n";;
        "cyan")
        printf "\e[96m${text}\e[0m\n";;
        *)
            echo "${text}"
        ;;
    esac
}

check_running_as_root() {
    if [ "$(id -u)" != "0" ]; then
        colorized_echo red "This command must be run as root."
        exit 1
    fi
}
detect_os() {
    # Detect the operating system
    if [ -f /etc/lsb-release ]; then
        OS=$(lsb_release -si)
        elif [ -f /etc/os-release ]; then
        OS=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
        elif [ -f /etc/redhat-release ]; then
        OS=$(cat /etc/redhat-release | awk '{print $1}')
        elif [ -f /etc/arch-release ]; then
        OS="Arch"
    else
        colorized_echo red "Unsupported operating system"
        exit 1
    fi
}

detect_and_update_package_manager() {
    colorized_echo blue "Updating package manager"
    if [[ "$OS" == "Ubuntu"* ]] || [[ "$OS" == "Debian"* ]]; then
        PKG_MANAGER="apt-get"
        $PKG_MANAGER update
        elif [[ "$OS" == "CentOS"* ]]; then
        PKG_MANAGER="yum"
        $PKG_MANAGER update -y
        $PKG_MANAGER epel-release -y
        elif [ "$OS" == "Fedora"* ]; then
        PKG_MANAGER="dnf"
        $PKG_MANAGER update
        elif [ "$OS" == "Arch" ]; then
        PKG_MANAGER="pacman"
        $PKG_MANAGER -Sy
    else
        colorized_echo red "Unsupported operating system"
        exit 1
    fi
}

detect_compose() {
    # Check if docker compose command exists
    if docker compose >/dev/null 2>&1; then
        COMPOSE='docker compose'
        elif docker-compose >/dev/null 2>&1; then
        COMPOSE='docker-compose'
    else
        colorized_echo red "docker compose not found"
        exit 1
    fi
}

install_package () {
    if [ -z $PKG_MANAGER ]; then
        detect_and_update_package_manager
    fi
    
    PACKAGE=$1
    colorized_echo blue "Installing $PACKAGE"
    if [[ "$OS" == "Ubuntu"* ]] || [[ "$OS" == "Debian"* ]]; then
        $PKG_MANAGER -y install "$PACKAGE"
        elif [[ "$OS" == "CentOS"* ]]; then
        $PKG_MANAGER install -y "$PACKAGE"
        elif [ "$OS" == "Fedora"* ]; then
        $PKG_MANAGER install -y "$PACKAGE"
        elif [ "$OS" == "Arch" ]; then
        $PKG_MANAGER -S --noconfirm "$PACKAGE"
    else
        colorized_echo red "Unsupported operating system"
        exit 1
    fi
}

install_docker() {
    # Install Docker and Docker Compose using the official installation script
    colorized_echo blue "Installing Docker"
    curl -fsSL https://get.docker.com | sh
    colorized_echo green "Docker installed successfully"
}

configure_files() {
    
    mkdir -p "$DATA_DIR"
    mkdir -p "$APP_DIR/haproxy"
    mkdir -p "/var/lib/marzban-node"
    read -rp "Enter SNI (discordapp.com): " SNI
    read -rp "Enter VLESS-TCP Port(12000): " PORT

    echo
    colorized_echo blue "Editing haproxy.cfg"

    cat > $APP_DIR/haproxy/haproxy.cfg <<EOF
defaults
        timeout connect 5000
        timeout client  50000
        timeout server  50000

listen front
 mode tcp
 bind *:443
 
 tcp-request inspect-delay 5s
 tcp-request content accept if { req_ssl_hello_type 1 }

 use_backend reality if { req.ssl_sni -m end $SNI }
 
backend reality
 mode tcp
 server srv2 marzban-node:$PORT send-proxy
EOF
    colorized_echo green "Done"
    echo
    colorized_echo blue "Editing docker-compose.yml"

    cat > $APP_DIR/docker-compose.yml <<EOF
version: '3.7'
networks:
  node:
    ipam:
      config:
        - subnet: 10.20.30.0/24
services:
  marzban-node:
    image: gozargah/marzban-node:latest
    container_name: marzban-node
    restart: always
    ports:
      - "62050:62050"
      - "62051:62051"
    environment:
      SSL_CERT_FILE: "/var/lib/marzban-node/ssl_cert.pem"
      SSL_KEY_FILE: "/var/lib/marzban-node/ssl_key.pem"
      SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/ssl_client_cert.pem"
    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node
    networks:
      - node

  haproxy:
    image: haproxy:3.0-dev
    container_name: haproxy
    ports:
      - "443:443"
    volumes:
      - ./haproxy:/usr/local/etc/haproxy:rw
    restart: always
    networks:
      - node
EOF
    colorized_echo green "Done"
}

up_marzban_node() {
    echo
    colorized_echo blue "Starting Marzban-node"
    cd /opt/node
    $COMPOSE up -d
    colorized_echo green "Done"
}
is_node_installed() {
    if [ -d $APP_DIR ]; then
        return 0
    else
        return 1
    fi
}

install_command() {
    check_running_as_root
    if is_node_installed; then
        colorized_echo red "Marzban-node is already installed at $APP_DIR"
        exit 1
    fi
    detect_os
    if ! command -v git >/dev/null 2>&1; then
        install_package git
    fi
    if ! command -v socat >/dev/null 2>&1; then
        install_package socat
    fi
    if ! command -v docker >/dev/null 2>&1; then
        install_docker
    fi
    detect_compose
    configure_files
    up_marzban_node
}

case "$1" in
    install)
    shift; install_command "$@"
esac
