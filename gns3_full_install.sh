#!/bin/bash
# gns3_full_install.sh - Полная установка GNS3 с Dynamips, uBridge и IOS образом
# Автоматическая установка и настройка для Debian/Ubuntu

set -e  # Остановка при ошибках

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Логирование
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Проверка root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен запускаться от root!"
        exit 1
    fi
    log_info "Запуск от root пользователя"
}

# Шаг 1: Обновление системы и установка базовых пакетов
step1_update_system() {
    log_step "1. Обновление системы и установка базовых пакетов"
    
    log_info "Обновление списка пакетов..."
    apt-get update
    
    log_info "Обновление системы..."
    apt-get upgrade -y
    
    log_info "Установка Python и зависимостей..."
    apt-get install -y git python3-setuptools python3-pip python3.11-venv wget curl
    
    log_info "Проверка версии Python..."
    python3 -V
}

# Шаг 2: Установка GNS3 сервера
step2_install_gns3() {
    log_step "2. Установка GNS3 сервера"
    
    log_info "Клонирование репозитория GNS3 сервера..."
    if [ ! -d "gns3-server" ]; then
        git clone https://github.com/GNS3/gns3-server.git
    fi
    
    cd gns3-server/
    
    log_info "Создание виртуального окружения Python..."
    python3 -m venv venv
    
    log_info "Активация виртуального окружения..."
    source venv/bin/activate
    
    log_info "Установка зависимостей Python..."
    python3 -m pip install --upgrade pip
    python3 -m pip install -r requirements.txt
    
    log_info "Установка GNS3 сервера..."
    python3 -m pip install .
    
    log_info "Возврат в корневую директорию..."
    cd ..
}

# Шаг 3: Установка и компиляция Dynamips
step3_install_dynamips() {
    log_step "3. Установка и компиляция Dynamips"
    
    log_info "Установка зависимостей для компиляции..."
    apt-get install -y build-essential cmake libpcap-dev libelf-dev
    
    log_info "Клонирование репозитория Dynamips..."
    if [ ! -d "dynamips" ]; then
        git clone https://github.com/GNS3/dynamips.git
    fi
    
    cd dynamips/
    
    log_info "Компиляция Dynamips..."
    mkdir -p build
    cd build
    cmake ..
    make -j$(nproc)
    
    log_info "Установка Dynamips в систему..."
    # Поиск скомпилированного бинарника
    if [ -f "stable/dynamips_amd64_stable" ]; then
        cp stable/dynamips_amd64_stable /usr/local/bin/dynamips
    elif [ -f "dynamips" ]; then
        cp dynamips /usr/local/bin/dynamips
    else
        DYNAMIPS_BIN=$(find . -name "*dynamips*" -type f -executable | head -1)
        if [ -n "$DYNAMIPS_BIN" ]; then
            cp "$DYNAMIPS_BIN" /usr/local/bin/dynamips
        else
            log_error "Не найден скомпилированный файл dynamips!"
            exit 1
        fi
    fi
    
    chmod +x /usr/local/bin/dynamips
    
    log_info "Проверка установки Dynamips..."
    which dynamips
    dynamips --version | head -3
    
    log_info "Возврат в корневую директорию..."
    cd ../..
}

# Шаг 4: Установка и компиляция uBridge
step4_install_ubridge() {
    log_step "4. Установка и компиляция uBridge"
    
    log_info "Клонирование репозитория uBridge..."
    if [ ! -d "ubridge" ]; then
        git clone https://github.com/GNS3/ubridge.git
    fi
    
    cd ubridge/
    
    log_info "Компиляция uBridge..."
    make
    
    log_info "Установка uBridge в систему..."
    if [ -f "ubridge" ]; then
        cp ubridge /usr/local/bin/
        chmod +x /usr/local/bin/ubridge
    else
        log_error "Файл ubridge не найден после компиляции!"
        exit 1
    fi
    
    log_info "Проверка установки uBridge..."
    which ubridge
    if ubridge --help >/dev/null 2>&1; then
        log_info "uBridge успешно установлен"
    else
        log_warn "uBridge не отвечает на --help, но установлен"
    fi
    
    log_info "Возврат в корневую директорию..."
    cd ..
}

# Шаг 5: Загрузка IOS образа
step5_download_ios() {
    log_step "5. Загрузка IOS образа Cisco 7200"
    
    IOS_URL="https://192.168.104.115/cisco//Cisco_7200//c7200-adventerprisek9-mz.124-24.T5.image"
    IOS_FILENAME="c7200-adventerprisek9-mz.124-24.T5.image"
    
    log_info "Создание директорий для GNS3..."
    mkdir -p ~/.config/GNS3/2.2/
    mkdir -p ~/GNS3/{images/IOS,projects,appliances,configs}
    
    log_info "Загрузка IOS образа..."
    if [ ! -f "~/GNS3/images/IOS/$IOS_FILENAME" ]; then
        wget --no-check-certificate "$IOS_URL" -O ~/GNS3/images/IOS/"$IOS_FILENAME"
        
        if [ $? -eq 0 ]; then
            log_info "IOS образ успешно загружен: ~/GNS3/images/IOS/$IOS_FILENAME"
            ls -lh ~/GNS3/images/IOS/"$IOS_FILENAME"
        else
            log_warn "Не удалось загрузить IOS образ. Загрузите его вручную в ~/GNS3/images/IOS/"
        fi
    else
        log_info "IOS образ уже существует: ~/GNS3/images/IOS/$IOS_FILENAME"
    fi
}

# Шаг 6: Настройка конфигурации GNS3
step6_configure_gns3() {
    log_step "6. Настройка конфигурации GNS3"
    
    log_info "Создание конфигурационного файла GNS3..."
    cat > ~/.config/GNS3/2.2/gns3_server.conf << 'EOF'
[Server]
host = 0.0.0.0
port = 3080
images_path = /root/GNS3/images
projects_path = /root/GNS3/projects
appliances_path = /root/GNS3/appliances
configs_path = /root/GNS3/configs
report_errors = True

[Dynamips]
allocate_hypervisor_tcp_ports = True
mmap_support = True
sparse_memory_support = True
ghost_ios_support = True
dynamips_path = /usr/local/bin/dynamips

[Ubridge]
ubridge_path = /usr/local/bin/ubridge

[IOU]
enable = False

[Qemu]
enable = False

[VPCS]
enable = True
EOF
    
    log_info "Конфигурационный файл создан: ~/.config/GNS3/2.2/gns3_server.conf"
}

# Шаг 7: Создание шаблона Cisco 7200
step7_create_template() {
    log_step "7. Создание шаблона Cisco 7200"
    
    cat > /tmp/c7200_template.json << 'EOF'
{
    "category": "router",
    "compute_id": "local",
    "default_name_format": "R{0}",
    "name": "Cisco 7200",
    "symbol": ":/symbols/router.svg",
    "template_type": "dynamips",
    "usage": "For IOS c7200 images",
    "platform": "c7200",
    "nvram": 256,
    "ram": 512,
    "slot0": "C7200-IO-FE",
    "slot1": "PA-FE-TX",
    "slot2": "PA-FE-TX",
    "slot3": "PA-FE-TX",
    "slot4": "",
    "slot5": "",
    "slot6": "",
    "wics": [],
    "executable": "/usr/local/bin/dynamips",
    "mmap": true,
    "sparse_memory": true
}
EOF
    
    log_info "Шаблон Cisco 7200 создан: /tmp/c7200_template.json"
}

# Шаг 8: Запуск GNS3 сервера
step8_start_gns3() {
    log_step "8. Запуск GNS3 сервера"
    
    log_info "Остановка предыдущих процессов GNS3..."
    pkill -f gns3server 2>/dev/null || true
    sleep 2
    
    log_info "Активация виртуального окружения GNS3..."
    cd ~/gns3-server
    source venv/bin/activate
    
    log_info "Запуск GNS3 сервера в фоновом режиме..."
    nohup gns3server > /tmp/gns3.log 2>&1 &
    GNS3_PID=$!
    
    log_info "Ожидание запуска сервера (15 секунд)..."
    sleep 15
    
    log_info "Проверка запуска сервера..."
    if curl -s http://localhost:3080/v2/version >/dev/null 2>&1; then
        log_info "GNS3 сервер успешно запущен (PID: $GNS3_PID)"
        
        # Попытка добавить шаблон через API
        log_info "Попытка добавления шаблона Cisco 7200..."
        if curl -X POST http://localhost:3080/v2/templates \
           -H "Content-Type: application/json" \
           -d @/tmp/c7200_template.json >/dev/null 2>&1; then
            log_info "Шаблон Cisco 7200 добавлен"
        else
            log_warn "Не удалось добавить шаблон через API. Добавьте вручную через Web UI"
        fi
    else
        log_error "GNS3 сервер не запустился. Проверьте логи: /tmp/gns3.log"
        tail -20 /tmp/gns3.log
    fi
    
    cd ..
}

# Шаг 9: Финальная проверка
step9_final_check() {
    log_step "9. Финальная проверка установки"
    
    echo ""
    echo "=== ПРОВЕРКА УСТАНОВЛЕННЫХ КОМПОНЕНТОВ ==="
    echo ""
    
    # Проверка Dynamips
    if which dynamips >/dev/null; then
        echo -e "✓ ${GREEN}Dynamips:${NC} $(which dynamips)"
        echo "  Версия: $(dynamips --version 2>/dev/null | head -1)"
    else
        echo -e "✗ ${RED}Dynamips не установлен${NC}"
    fi
    
    # Проверка uBridge
    if which ubridge >/dev/null; then
        echo -e "✓ ${GREEN}uBridge:${NC} $(which ubridge)"
        echo "  Статус: установлен"
    else
        echo -e "✗ ${RED}uBridge не установлен${NC}"
    fi
    
    # Проверка GNS3 сервера
    if curl -s http://localhost:3080/v2/version >/dev/null; then
        echo -e "✓ ${GREEN}GNS3 сервер:${NC} запущен"
        VERSION=$(curl -s http://localhost:3080/v2/version | python3 -c "import sys,json; print(json.load(sys.stdin)['version'])" 2>/dev/null || echo "версия неизвестна")
        echo "  Версия: $VERSION"
        echo "  Порт: 3080"
    else
        echo -e "✗ ${RED}GNS3 сервер не запущен${NC}"
    fi
    
    # Проверка IOS образа
    if [ -f ~/GNS3/images/IOS/c7200-adventerprisek9-mz.124-24.T5.image ]; then
        echo -e "✓ ${GREEN}IOS образ:${NC} найден"
        echo "  Размер: $(ls -lh ~/GNS3/images/IOS/c7200-adventerprisek9-mz.124-24.T5.image | awk '{print $5}')"
    else
        echo -e "✗ ${RED}IOS образ не найден${NC}"
        echo "  Загрузите вручную: ~/GNS3/images/IOS/"
    fi
    
    # Проверка конфигурации
    if [ -f ~/.config/GNS3/2.2/gns3_server.conf ]; then
        echo -e "✓ ${GREEN}Конфигурация GNS3:${NC} создана"
    else
        echo -e "✗ ${RED}Конфигурация GNS3 не найдена${NC}"
    fi
    
    echo ""
    echo "=== СЕТЕВАЯ ИНФОРМАЦИЯ ==="
    IP_ADDR=$(hostname -I | awk '{print $1}')
    echo "IP адрес сервера: $IP_ADDR"
    echo "Web интерфейс GNS3: http://${IP_ADDR}:3080"
    echo ""
    echo "=== КОМАНДЫ ДЛЯ УПРАВЛЕНИЯ ==="
    echo "Остановить GNS3: pkill -f gns3server"
    echo "Запустить GNS3: cd ~/gns3-server && source venv/bin/activate && gns3server"
    echo "Просмотр логов: tail -f /tmp/gns3.log"
    echo "Проверить порты: netstat -tlnp | grep -E '3080|7200'"
    echo ""
    echo "=== ДАЛЬНЕЙШИЕ ДЕЙСТВИЯ ==="
    echo "1. Откройте браузер и перейдите по адресу: http://${IP_ADDR}:3080"
    echo "2. Создайте новый проект"
    echo "3. Добавьте Cisco 7200 роутер из Devices"
    echo "4. При необходимости загрузите IOS образ через Web UI"
}
rm -r /root/ubridge /root/dynamips /root/c7200_i0_log.txt
# Основная функция
main() {
    clear
    echo "================================================"
    echo "  ПОЛНАЯ УСТАНОВКА GNS3 С DYNAMIPS И UBRIDGE"
    echo "================================================"
    echo ""
    
    # Проверка прав
    check_root
    
    # Выполнение всех шагов
    step1_update_system
    step2_install_gns3
    step3_install_dynamips
    step4_install_ubridge
    step5_download_ios
    step6_configure_gns3
    step7_create_template
    step8_start_gns3
    step9_final_check
    
    log_info "Установка завершена!"
}

# Обработка прерывания
trap 'log_error "Установка прервана!"; exit 1' INT TERM

# Запуск основной функции
main "$@"