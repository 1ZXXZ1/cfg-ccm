#!/bin/bash
# gns3_full_install-V0.0.5.sh - Полная установка GNS3 с Dynamips, uBridge и IOS образом
# Автоматическая установка и настройка для Debian/Ubuntu

set -e  # Остановка при ошибках

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Логирование
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_note() { echo -e "${CYAN}[NOTE]${NC} $1"; }

# Проверка совместимости дистрибутива
check_distro() {
    log_step "Проверка совместимости системы"
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="$ID"
        DISTRO_NAME="$NAME"
        DISTRO_VERSION="$VERSION_ID"
        
        log_info "Обнаружена система: $DISTRO_NAME ($DISTRO_ID $DISTRO_VERSION)"
        
        # Список поддерживаемых дистрибутивов
        SUPPORTED_DISTROS=("debian" "ubuntu" "linuxmint" "pop" "kali" "raspbian")
        
        local is_supported=false
        for supported in "${SUPPORTED_DISTROS[@]}"; do
            if [[ "$DISTRO_ID" == *"$supported"* ]] || [[ "$DISTRO_NAME" == *"$supported"* ]]; then
                is_supported=true
                break
            fi
        done
        
        if [ "$is_supported" = true ]; then
            log_info "Система совместима с установкой GNS3"
            return 0
        else
            log_warn "Система НЕ является Debian/Ubuntu или производной!"
            log_warn "Обнаружена: $DISTRO_NAME ($DISTRO_ID)"
            
            echo -e "\n${YELLOW}════════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${RED}                        ВНИМАНИЕ: НЕСОВМЕСТИМАЯ СИСТЕМА                          ${NC}"
            echo -e "${YELLOW}════════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e ""
            echo -e "Этот скрипт оптимизирован для ${GREEN}Debian/Ubuntu${NC} и производных дистрибутивов."
            echo -e "Ваша система (${YELLOW}$DISTRO_NAME${NC}) может вызвать следующие проблемы:"
            echo -e ""
            echo -e "${RED}Возможные проблемы:${NC}"
            echo -e "  1. ${YELLOW}Пакеты могут иметь другие имена${NC}"
            echo -e "  2. ${YELLOW}Зависимости могут отсутствовать в репозиториях${NC}"
            echo -e "  3. ${YELLOW}Системные библиотеки могут быть несовместимы${NC}"
            echo -e "  4. ${YELLOW}Установка может завершиться с ошибками${NC}"
            echo -e "  5. ${YELLOW}GNS3 может работать нестабильно${NC}"
            echo -e ""
            echo -e "${CYAN}Рекомендации:${NC}"
            echo -e "  1. Рассмотрите использование Debian/Ubuntu для GNS3"
            echo -e "  2. Или выполните ${YELLOW}ручную установку${NC} для вашего дистрибутива"
            echo -e "  3. Проверьте документацию GNS3 для вашей системы"
            echo -e ""
            
            # Запрос подтверждения
            echo -e "${YELLOW}Желаете продолжить установку несмотря на риски?${NC}"
            read -p "Введите 'yes' для продолжения или любой другой текст для отмены: " user_response
            
            if [[ "$user_response" != "yes" ]]; then
                log_error "Установка отменена пользователем"
                exit 1
            fi
            
            log_note "Продолжение установки на несовместимой системе..."
            log_note "Вы отвечаете за возможные проблемы!"
            
            # Дополнительная информация для несовместимых систем
            echo -e "\n${CYAN}Для не-Debian систем вам может потребоваться:${NC}"
            echo -e "  1. Вручную установить зависимости через менеджер пакетов вашей системы"
            echo -e "  2. Изменить имена пакетов в скрипте"
            echo -e "  3. Скомпилировать библиотеки из исходников"
            echo -e ""
            
            return 1
        fi
    else
        log_warn "Не удалось определить дистрибутив через /etc/os-release"
        log_warn "Проверка через другие методы..."
        
        # Альтернативные методы определения
        if command -v lsb_release >/dev/null 2>&1; then
            DISTRO_NAME=$(lsb_release -si)
            DISTRO_VERSION=$(lsb_release -sr)
            log_info "Определено через lsb_release: $DISTRO_NAME $DISTRO_VERSION"
            
            if [[ "$DISTRO_NAME" =~ (Debian|Ubuntu|Mint|Pop|Kali) ]]; then
                log_info "Система совместима (через lsb_release)"
                return 0
            fi
        fi
        
        log_error "Не удалось определить дистрибутив. Установка может не работать!"
        echo -e "\n${YELLOW}Продолжить с риском? (yes/no): ${NC}"
        read -r response
        if [[ "$response" != "yes" ]]; then
            exit 1
        fi
        return 1
    fi
}

# Проверка версии дистрибутива (для предупреждений)
check_distro_version() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        
        case "$ID" in
            debian)
                if [[ "$VERSION_ID" =~ ^[0-9]+$ ]] && [ "$VERSION_ID" -lt 10 ]; then
                    log_warn "Debian версии $VERSION_ID устарел. Рекомендуется Debian 10+"
                fi
                ;;
            ubuntu)
                if [[ "$VERSION_ID" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    version_num=$(echo "$VERSION_ID" | cut -d. -f1)
                    if [ "$version_num" -lt 20 ]; then
                        log_warn "Ubuntu версии $VERSION_ID устарел. Рекомендуется Ubuntu 20.04+"
                    fi
                fi
                ;;
        esac
    fi
}

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

# Шаг 6: Запуск GNS3 сервера
step6_start_gns3() {
    log_step "6. Запуск GNS3 сервера"
    
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
    else
        log_error "GNS3 сервер не запустился. Проверьте логи: /tmp/gns3.log"
        tail -20 /tmp/gns3.log
    fi
    
    cd ..
}

# Шаг 7: Финальная проверка
step7_final_check() {
    log_step "7. Финальная проверка установки"
    
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
    echo "3. Добавьте Cisco 7200 роутер через Web UI"
    echo "4. Укажите путь к IOS образу: ~/GNS3/images/IOS/c7200-adventerprisek9-mz.124-24.T5.image"
    echo ""
    
    # Дополнительное предупреждение для несовместимых систем
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ ! "$ID" =~ (debian|ubuntu|mint|pop|kali|raspbian) ]]; then
            echo -e "\n${YELLOW}════════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${RED}                    ДОПОЛНИТЕЛЬНОЕ ПРЕДУПРЕЖДЕНИЕ                                ${NC}"
            echo -e "${YELLOW}════════════════════════════════════════════════════════════════════════════════${NC}"
            echo -e ""
            echo -e "Ваша система (${YELLOW}$NAME${NC}) не является официально поддерживаемой."
            echo -e "Если возникли проблемы:"
            echo -e "  1. Проверьте совместимость библиотек"
            echo -e "  2. Обновите зависимости вручную"
            echo -e "  3. Обратитесь к документации вашего дистрибутива"
            echo -e "  4. Рассмотрите использование контейнера Docker с GNS3"
            echo -e ""
        fi
    fi
}

# Основная функция
main() {
    clear
    echo "================================================"
    echo "  ПОЛНАЯ УСТАНОВКА GNS3 С DYNAMIPS И UBRIDGE"
    echo "================================================"
    echo ""
    
    # Проверка прав
    check_root
    
    # Проверка совместимости дистрибутива
    check_distro
    
    # Проверка версии дистрибутива
    check_distro_version
    
    # Выполнение всех шагов
    step1_update_system
    step2_install_gns3
    step3_install_dynamips
    step4_install_ubridge
    step5_download_ios
    step6_start_gns3
    step7_final_check
    log_info "Установка завершена!"
    
}

# Обработка прерывания
trap 'log_error "Установка прервана!"; exit 1' INT TERM

# Запуск основной функции
main "$@"
