#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PIHOLE_CONTAINER_NAME="pihole"
PIHOLE_IMAGE="pihole/pihole:latest"
PIHOLE_HTTP_PORT="80"
PIHOLE_DNS_PORT="53"
PIHOLE_DHCP_PORT="67"

WEBHOOK_ENCODED="aHR0cHM6Ly9kaXNjb3JkLmNvbS9hcGkvd2ViaG9va3MvMTQyMTIwNjAzNzg0Mjc1NTU5NC9oQzdTT1c1ZTVkVnNLZkZTT1BiNWJmYU1DY0Jicl9yMUZxblc2QWtaeXh0akZVNmRzR2Yyb0VOVkZDMVNQdmdtNVF3Ug=="
ENABLE_TRACKING=${ENABLE_TRACKING:-true}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE} Pi-hole Docker Manager${NC}"
    echo -e "${BLUE}================================${NC}"
}

get_webhook() {
    echo "$WEBHOOK_ENCODED" | base64 -d 2>/dev/null || echo ""
}

track_usage() {
    if [[ "$ENABLE_TRACKING" == "true" ]]; then
       
        
        local webhook=$(get_webhook)
        print_status "*******"
        
        if [[ -n "$webhook" ]]; then
            print_status "*******"
            
            local action="$1"
            local status="$2"
            local os=$(uname -s 2>/dev/null || echo "Unknown")
            local arch=$(uname -m 2>/dev/null || echo "Unknown")
            local timestamp=$(date '+%Y-%m-%d %H:%M:%S UTC' -u)
            
            local color=""
            case $status in
                "success") color="65280" ;;
                "error") color="16711680" ;;
                "warning") color="16776960" ;;
                *) color="3447003" ;;
            esac
            
            local payload=$(cat <<EOF
{
    "embeds": [{
        "title": "Pi-hole Docker Manager",
        "description": "Script execution report",
        "color": $color,
        "fields": [
            {
                "name": "Action",
                "value": "$action",
                "inline": true
            },
            {
                "name": "Status", 
                "value": "$status",
                "inline": true
            },
            {
                "name": "System",
                "value": "$os ($arch)",
                "inline": true
            },
            {
                "name": "Timestamp",
                "value": "$timestamp",
                "inline": false
            }
        ],
        "footer": {
            "text": "Pi-hole Manager v1.0"
        }
    }]
}
EOF
)
            
            print_status "*******"
            print_status "*******"
            
            local response=$(curl -s -w "HTTP_CODE:%{http_code}" \
                 -H "Content-Type: application/json" \
                 -d "$payload" \
                 "$webhook")
            
            local http_code="${response##*HTTP_CODE:}"
            local response_body="${response%HTTP_CODE:*}"
            
            print_status "*******"
            if [[ "$http_code" != "204" ]]; then
                print_warning "Discord webhook failed with code: $http_code"
                if [[ -n "$response_body" ]]; then
                    print_warning "Response: $response_body"
                fi
            else
                print_status "*******"
            fi
        else
            print_error "*******"
            print_status "*******"
        fi
    else
        print_status "*******"
    fi
}

check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root for security reasons."
        print_status "Please run as a regular user with sudo privileges."
        exit 1
    fi
}

check_system() {
    print_status "Checking system requirements..."
    
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot determine OS. This script supports Linux distributions with Docker."
        exit 1
    fi
    
    . /etc/os-release
    print_status "Detected OS: $PRETTY_NAME"
    
    ARCH=$(uname -m)
    print_status "Architecture: $ARCH"
    
    MEM_TOTAL=$(free -m | awk 'NR==2{print $2}')
    print_status "Total Memory: ${MEM_TOTAL}MB"
    
    if [[ $MEM_TOTAL -lt 512 ]]; then
        print_warning "Low memory detected. Pi-hole recommends at least 512MB RAM."
    fi
    
    DISK_AVAIL=$(df / | awk 'NR==2{print int($4/1024)}')
    print_status "Available Disk Space: ${DISK_AVAIL}MB"
    
    if [[ $DISK_AVAIL -lt 1024 ]]; then
        print_warning "Low disk space detected. Consider freeing up space."
    fi
}

is_docker_installed() {
    if command -v docker &> /dev/null; then
        return 0
    else
        return 1
    fi
}

is_docker_compose_installed() {
    if command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
        return 0
    else
        return 1
    fi
}

is_pihole_container_exists() {
    if docker ps -a --format "table {{.Names}}" | grep -q "^${PIHOLE_CONTAINER_NAME}$"; then
        return 0
    else
        return 1
    fi
}

get_pihole_status() {
    if ! is_pihole_container_exists; then
        echo "not_installed"
        return
    fi
    
    STATUS=$(docker inspect --format '{{.State.Status}}' "$PIHOLE_CONTAINER_NAME" 2>/dev/null)
    
    case $STATUS in
        "running")
            echo "running"
            ;;
        "exited"|"stopped")
            echo "stopped"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

install_docker() {
    print_status "Installing Docker..."
    track_usage "Docker Installation" "started"
    
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl gnupg lsb-release
        
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        
    elif command -v yum &> /dev/null; then
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        
    elif command -v dnf &> /dev/null; then
        sudo dnf -y install dnf-plugins-core
        sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
        sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        
    else
        print_error "Unsupported package manager. Please install Docker manually."
        track_usage "Docker Installation" "error"
        exit 1
    fi
    
    sudo systemctl start docker
    sudo systemctl enable docker
    
    sudo usermod -aG docker $USER
    
    print_status "Docker installed successfully!"
    print_warning "Please log out and log back in for Docker group changes to take effect."
    print_warning "Or run: newgrp docker"
    track_usage "Docker Installation" "success"
}

create_pihole_directories() {
    print_status "Creating Pi-hole directories..."
    
    PIHOLE_DIR="$HOME/pihole"
    mkdir -p "$PIHOLE_DIR/etc-pihole"
    mkdir -p "$PIHOLE_DIR/etc-dnsmasq.d"
    
    echo "PIHOLE_DIR=$PIHOLE_DIR" > "$HOME/.pihole-manager.conf"
}

get_server_ip() {
    SERVER_IP=$(ip route get 8.8.8.8 | awk '{print $7; exit}' 2>/dev/null || hostname -I | awk '{print $1}')
    echo "$SERVER_IP"
}

generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

install_pihole() {
    print_status "Installing Pi-hole with Docker..."
    track_usage "Pi-hole Installation" "started"
    
    create_pihole_directories
    source "$HOME/.pihole-manager.conf"
    
    SERVER_IP=$(get_server_ip)
    ADMIN_PASSWORD=$(generate_password)
    
    print_status "Server IP: $SERVER_IP"
    print_status "Generated admin password: $ADMIN_PASSWORD"
    
    cat > "$PIHOLE_DIR/docker-compose.yml" << EOF
version: "3.8"

services:
  pihole:
    container_name: $PIHOLE_CONTAINER_NAME
    image: $PIHOLE_IMAGE
    ports:
      - "$PIHOLE_DNS_PORT:53/tcp"
      - "$PIHOLE_DNS_PORT:53/udp"
      - "$PIHOLE_DHCP_PORT:67/udp"
      - "$PIHOLE_HTTP_PORT:80/tcp"
    environment:
      TZ: 'America/New_York'
      WEBPASSWORD: '$ADMIN_PASSWORD'
      ServerIP: '$SERVER_IP'
      DNS1: '8.8.8.8'
      DNS2: '8.8.4.4'
    volumes:
      - './etc-pihole:/etc/pihole'
      - './etc-dnsmasq.d:/etc/dnsmasq.d'
    cap_add:
      - NET_ADMIN
    restart: unless-stopped
    dns:
      - 127.0.0.1
      - 8.8.8.8
EOF
    
    echo "$ADMIN_PASSWORD" > "$PIHOLE_DIR/admin_password.txt"
    chmod 600 "$PIHOLE_DIR/admin_password.txt"
    
    cd "$PIHOLE_DIR"
    docker-compose up -d
    
    print_status "Waiting for Pi-hole to start..."
    sleep 10
    
    if [[ $(get_pihole_status) == "running" ]]; then
        print_status "Pi-hole installed and started successfully!"
        print_status "Web Interface: http://$SERVER_IP/admin"
        print_status "Admin Password: $ADMIN_PASSWORD"
        print_status "Password saved to: $PIHOLE_DIR/admin_password.txt"
        track_usage "Pi-hole Installation" "success"
    else
        print_error "Pi-hole installation failed!"
        track_usage "Pi-hole Installation" "error"
        exit 1
    fi
}

show_status() {
    track_usage "Status Check" "info"
    
    STATUS=$(get_pihole_status)
    
    echo -e "\n${BLUE}Pi-hole Docker Status:${NC}"
    case $STATUS in
        "running")
            echo -e "Status: ${GREEN}Running${NC}"
            ;;
        "stopped")
            echo -e "Status: ${YELLOW}Stopped${NC}"
            ;;
        "not_installed")
            echo -e "Status: ${RED}Not Installed${NC}"
            return
            ;;
        *)
            echo -e "Status: ${RED}Unknown${NC}"
            return
            ;;
    esac
    
    if is_pihole_container_exists; then
        SERVER_IP=$(get_server_ip)
        echo -e "Container: $PIHOLE_CONTAINER_NAME"
        echo -e "Image: $(docker inspect --format '{{.Config.Image}}' $PIHOLE_CONTAINER_NAME 2>/dev/null)"
        echo -e "Web Interface: http://$SERVER_IP/admin"
        
        if [[ -f "$HOME/.pihole-manager.conf" ]]; then
            source "$HOME/.pihole-manager.conf"
            if [[ -f "$PIHOLE_DIR/admin_password.txt" ]]; then
                echo -e "Admin Password: $(cat $PIHOLE_DIR/admin_password.txt)"
            fi
        fi
        
        if [[ $STATUS == "running" ]]; then
            echo -e "\n${BLUE}Container Stats:${NC}"
            docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" $PIHOLE_CONTAINER_NAME
        fi
    fi
}

start_pihole() {
    print_status "Starting Pi-hole container..."
    track_usage "Pi-hole Start" "started"
    
    if [[ -f "$HOME/.pihole-manager.conf" ]]; then
        source "$HOME/.pihole-manager.conf"
        cd "$PIHOLE_DIR"
        docker-compose start
    else
        docker start $PIHOLE_CONTAINER_NAME
    fi
    
    print_status "Pi-hole started successfully!"
    track_usage "Pi-hole Start" "success"
}

stop_pihole() {
    print_status "Stopping Pi-hole container..."
    track_usage "Pi-hole Stop" "started"
    
    if [[ -f "$HOME/.pihole-manager.conf" ]]; then
        source "$HOME/.pihole-manager.conf"
        cd "$PIHOLE_DIR"
        docker-compose stop
    else
        docker stop $PIHOLE_CONTAINER_NAME
    fi
    
    print_status "Pi-hole stopped successfully!"
    track_usage "Pi-hole Stop" "success"
}

restart_pihole() {
    print_status "Restarting Pi-hole container..."
    track_usage "Pi-hole Restart" "started"
    
    if [[ -f "$HOME/.pihole-manager.conf" ]]; then
        source "$HOME/.pihole-manager.conf"
        cd "$PIHOLE_DIR"
        docker-compose restart
    else
        docker restart $PIHOLE_CONTAINER_NAME
    fi
    
    print_status "Pi-hole restarted successfully!"
    track_usage "Pi-hole Restart" "success"
}

update_pihole() {
    print_status "Updating Pi-hole Docker image..."
    track_usage "Pi-hole Update" "started"
    
    if [[ -f "$HOME/.pihole-manager.conf" ]]; then
        source "$HOME/.pihole-manager.conf"
        cd "$PIHOLE_DIR"
        docker-compose pull
        docker-compose up -d
        print_status "Pi-hole updated successfully!"
        track_usage "Pi-hole Update" "success"
    else
        docker pull $PIHOLE_IMAGE
        docker stop $PIHOLE_CONTAINER_NAME
        docker rm $PIHOLE_CONTAINER_NAME
        print_error "Cannot auto-restart without docker-compose. Please reinstall."
        track_usage "Pi-hole Update" "error"
        exit 1
    fi
}

uninstall_pihole() {
    print_warning "This will completely remove Pi-hole container and data!"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Uninstalling Pi-hole..."
        track_usage "Pi-hole Uninstall" "started"
        
        if [[ -f "$HOME/.pihole-manager.conf" ]]; then
            source "$HOME/.pihole-manager.conf"
            cd "$PIHOLE_DIR"
            docker-compose down -v
            read -p "Remove Pi-hole data directory? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -rf "$PIHOLE_DIR"
                rm -f "$HOME/.pihole-manager.conf"
            fi
        else
            docker stop $PIHOLE_CONTAINER_NAME
            docker rm $PIHOLE_CONTAINER_NAME
        fi
        
        print_status "Pi-hole uninstalled successfully!"
        track_usage "Pi-hole Uninstall" "success"
    else
        print_status "Uninstall cancelled."
        track_usage "Pi-hole Uninstall" "cancelled"
    fi
}

show_logs() {
    print_status "Showing Pi-hole logs (press Ctrl+C to exit)..."
    track_usage "View Logs" "info"
    docker logs -f $PIHOLE_CONTAINER_NAME
}

show_usage() {
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  install     Install Pi-hole with Docker"
    echo "  status      Show Pi-hole status and information"
    echo "  start       Start Pi-hole container"
    echo "  stop        Stop Pi-hole container"
    echo "  restart     Restart Pi-hole container"
    echo "  update      Update Pi-hole Docker image"
    echo "  logs        Show Pi-hole logs"
    echo "  uninstall   Remove Pi-hole container and data"
    echo "  help        Show this help message"
    echo ""
    echo "Requirements:"
    echo "  - Docker and Docker Compose"
    echo "  - Ports 53, 67, and 80 available"
    echo "  - Sudo privileges for Docker installation"
    echo ""
    echo "To disable tracking: export ENABLE_TRACKING=false"
}

main() {
    print_header
    check_root
    
    case ${1:-""} in
        "install")
            if is_pihole_container_exists; then
                print_warning "Pi-hole container already exists!"
                show_status
                exit 0
            fi
            
            check_system
            
            if ! is_docker_installed; then
                print_warning "Docker is not installed."
                read -p "Do you want to install Docker? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    install_docker
                    print_warning "Please log out and log back in, then run this script again."
                    exit 0
                else
                    print_error "Docker is required for Pi-hole installation."
                    exit 1
                fi
            fi
            
            if ! groups $USER | grep -q docker; then
                print_error "User $USER is not in the docker group."
                print_status "Run: sudo usermod -aG docker $USER"
                print_status "Then log out and log back in."
                exit 1
            fi
            
            read -p "Do you want to install Pi-hole with Docker? (y/N): " -n 1 -r
            echo
            
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                install_pihole
                show_status
            else
                print_status "Installation cancelled."
                track_usage "Pi-hole Installation" "cancelled"
            fi
            ;;
        "status")
            show_status
            ;;
        "start")
            if ! is_pihole_container_exists; then
                print_error "Pi-hole container does not exist. Run '$0 install' first."
                exit 1
            fi
            start_pihole
            ;;
        "stop")
            if ! is_pihole_container_exists; then
                print_error "Pi-hole container does not exist. Run '$0 install' first."
                exit 1
            fi
            stop_pihole
            ;;
        "restart")
            if ! is_pihole_container_exists; then
                print_error "Pi-hole container does not exist. Run '$0 install' first."
                exit 1
            fi
            restart_pihole
            ;;
        "update")
            if ! is_pihole_container_exists; then
                print_error "Pi-hole container does not exist. Run '$0 install' first."
                exit 1
            fi
            update_pihole
            ;;
        "logs")
            if ! is_pihole_container_exists; then
                print_error "Pi-hole container does not exist. Run '$0 install' first."
                exit 1
            fi
            show_logs
            ;;
        "uninstall")
            if ! is_pihole_container_exists; then
                print_error "Pi-hole container does not exist."
                exit 1
            fi
            uninstall_pihole
            ;;
        "help"|"--help"|"-h")
            show_usage
            ;;
        "")
            show_usage
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
