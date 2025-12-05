#!/bin/bash
# vlc-cec.sh - VLC Media Player с управлением через CEC
# Версия: 0.7.0
# Дата: 05.12.2025
# Changelog:
#   0.7.0 - Outro Pause функция (05.12.2025)
#           - Динамический расчёт outro (video_duration - credits_duration)
#           - Persistent флаг outro_triggered в БД
#           - Pause вместо exit на outro
#           - Автоматический статус [X] при outro
#           - RED кнопка: установка intro/outro маркеров с коррекцией -5s
#           - Проверка skip_intro/skip_outro флагов перед срабатыванием
#           - Basename consistency для БД операций
#           - Cache update после outro trigger

# Парсинг параметров: [секунды] файл
if [ $# -eq 2 ]; then
    START_TIME="$1"
    VIDEO_FILE="$2"
elif [ $# -eq 1 ]; then
    START_TIME=""
    VIDEO_FILE="$1"
else
    echo "Использование: $0 [секунды] <видеофайл>"
    exit 1
fi

if [ ! -f "$VIDEO_FILE" ]; then
    echo "❌ Файл не найден: $VIDEO_FILE"
    exit 1
fi

# Basename для операций с БД (чтобы избежать дублирования записей)
VIDEO_BASENAME=$(basename "$VIDEO_FILE")

# Подключаем библиотеку отслеживания прогресса
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/playback-tracker.sh"

# Проверяем совместимость версии библиотеки
REQUIRED_TRACKER_VERSION="0.2.0"
if ! check_version_compatibility "$REQUIRED_TRACKER_VERSION"; then
    exit 1
fi

# Подключаем библиотеку работы с БД для skip markers
source "$SCRIPT_DIR/db-manager.sh"

# Skip Intro/Outro - переменные состояния
SKIP_SETUP_MODE=0  # 0=выключен, 1=intro_start, 2=intro_end, 3=outro_start
INTRO_START_TIME=0
INTRO_END_TIME=0
OUTRO_START_TIME=0

# Загруженные skip markers из БД
LOADED_INTRO_START=""
LOADED_INTRO_END=""
LOADED_OUTRO_START=""

# Настройки skip (флаги включения/выключения)
SKIP_INTRO_ENABLED=0
SKIP_OUTRO_ENABLED=0

# ВАЖНО: Укажите ваше CEC устройство
CEC_DEVICE="/dev/cec1"

if [ ! -e "$CEC_DEVICE" ]; then
    echo "❌ CEC устройство не найдено: $CEC_DEVICE"
    echo "Доступные устройства:"
    ls -la /dev/cec* 2>/dev/null || echo "  Нет CEC устройств"
    exit 1
fi

# VLC RC Log file
VLC_LOG_DIR="$SCRIPT_DIR/Log"
VLC_LOG_FILE="$VLC_LOG_DIR/vlc-cec_$(date +%y%m%d%H%M).log"
mkdir -p "$VLC_LOG_DIR"

# ============================================================================
# VLC RC COMMAND WRAPPER
# ============================================================================

# Отправка команды в VLC RC интерфейс
# Параметры:
#   $1 - команда (обязательный)
#   $2 - timeout в секундах (опциональный, по умолчанию 1)
# Возвращает: 0 если успех, 1 если ошибка
vlc_command() {
    local cmd="$1"
    local timeout="${2:-1}"
    
    # Логирование (отключено)
    # echo "[$(date '+%H:%M:%S')] VLC→ $cmd" >> "$VLC_LOG_FILE"
    
    # Отправляем команду
    echo "$cmd" | nc -w "$timeout" localhost 4212 > /dev/null 2>&1
    local result=$?
    
    if [ $result -ne 0 ]; then
        # echo "[$(date '+%H:%M:%S')] VLC✗ Failed: $cmd (exit $result)" >> "$VLC_LOG_FILE"
        return 1
    fi
    
    return 0
}

# Получение значения из VLC RC (для get_time, get_length и т.д.)
# Параметры:
#   $1 - команда запроса
#   $2 - timeout в секундах (опциональный, по умолчанию 2)
# Возвращает: значение через stdout
vlc_query() {
    local cmd="$1"
    local timeout="${2:-2}"
    
    # Логирование (отключено)
    # echo "[$(date '+%H:%M:%S')] VLC? $cmd" >> "$VLC_LOG_FILE"
    
    # Отправляем запрос и возвращаем ответ
    echo "$cmd" | nc -w "$timeout" localhost 4212 2>&1
}

# Получить текущую позицию воспроизведения (секунды)
vlc_get_time() {
    vlc_query "get_time" | grep -oE '[0-9]+' | tail -1
}

# Получить общую длину видео (секунды)
vlc_get_length() {
    vlc_query "get_length" | grep -oE '[0-9]+' | tail -1
}

# Корректный выход из VLC с очисткой всех процессов
vlc_exit() {
    vlc_command "quit"
    kill $VLC_PID 2>/dev/null
    kill $CEC_PID 2>/dev/null
    pkill -P $$ 2>/dev/null
    clear
    exit 0
}

# ============================================================================
# ФУНКЦИИ SKIP INTRO/OUTRO
# ============================================================================

# Загрузка skip markers из БД
load_skip_markers() {
    local video_file="$1"
    local basename=$(basename "$video_file")
    
    # Извлекаем series_prefix и series_suffix
    local series_prefix=$(extract_series_prefix "$basename")
    local series_suffix=$(extract_series_suffix "$basename")
    
    if [ -n "$series_prefix" ]; then
        # Загружаем настройки сериала (autoplay|skip_intro|skip_outro|intro_start|intro_end|credits_duration)
        local settings=$(db_get_series_settings "$series_prefix" "$series_suffix" 2>/dev/null)
        
        if [ -n "$settings" ]; then
            local skip_intro=$(echo "$settings" | cut -d'|' -f2)
            local skip_outro=$(echo "$settings" | cut -d'|' -f3)
            
            # Сохраняем флаги в глобальные переменные
            SKIP_INTRO_ENABLED=${skip_intro:-0}
            SKIP_OUTRO_ENABLED=${skip_outro:-0}
        fi
        
        # Получаем skip markers из БД (JSON)
        local skip_data=$(db_get_skip_markers "$series_prefix" "$series_suffix" 2>/dev/null)
        
        if [ -n "$skip_data" ]; then
            # Парсим только intro (outro_start больше не используется)
            LOADED_INTRO_START=$(echo "$skip_data" | grep -oP '"intro_start":\s*\K[0-9]+' || echo "")
            LOADED_INTRO_END=$(echo "$skip_data" | grep -oP '"intro_end":\s*\K[0-9]+' || echo "")
            
            if [ -n "$LOADED_INTRO_START" ] && [ -n "$LOADED_INTRO_END" ]; then
                echo "✓ Intro: ${LOADED_INTRO_START}s - ${LOADED_INTRO_END}s (skip: $([ $SKIP_INTRO_ENABLED -eq 1 ] && echo "ON" || echo "OFF"))"
            fi
        fi
        
        # Загружаем credits_duration для динамического расчёта outro
        CREDITS_DURATION=$(python3 "$SCRIPT_DIR/vlc_db.py" get-credits-duration "$series_prefix" "$series_suffix" 2>/dev/null)
        if [ -n "$CREDITS_DURATION" ]; then
            echo "✓ Credits: ${CREDITS_DURATION}s (skip: $([ $SKIP_OUTRO_ENABLED -eq 1 ] && echo "ON" || echo "OFF"))"
        fi
    fi
}

# Обработка RED кнопки для установки skip markers
handle_red_button() {
    local video_file="$1"
    local basename=$(basename "$video_file")
    
    # Коррекция времени реакции (задержка между нажатием и обработкой)
    local REACTION_DELAY=5  # секунд
    
    # Извлекаем series info
    local series_prefix=$(extract_series_prefix "$basename")
    local series_suffix=$(extract_series_suffix "$basename")
    
    if [ -z "$series_prefix" ]; then
        echo "⚠️  Не сериал - skip markers недоступны"
        return
    fi
    
    # Получаем текущую позицию и длительность
    local current_time=$(vlc_get_time)
    local total_length=$(vlc_get_length)
    
    if [ -z "$current_time" ] || [ -z "$total_length" ]; then
        echo "⚠️  Ошибка получения времени"
        return
    fi
    
    # Определяем фазу видео (в процентах)
    local position_percent=$((current_time * 100 / total_length))
    
    # АВТООПРЕДЕЛЕНИЕ: начало или конец видео?
    if [ $position_percent -lt 20 ]; then
        # НАЧАЛО ВИДЕО - устанавливаем INTRO
        case $SKIP_SETUP_MODE in
            0)  # Intro Start
                # Вычитаем задержку реакции
                INTRO_START_TIME=$((current_time - REACTION_DELAY))
                if [ $INTRO_START_TIME -lt 0 ]; then
                    INTRO_START_TIME=0
                fi
                SKIP_SETUP_MODE=1
                echo "📍 Intro Start: ${INTRO_START_TIME}s (коррекция -${REACTION_DELAY}s)"
                ;;
            1)  # Intro End
                # Вычитаем задержку реакции
                INTRO_END_TIME=$((current_time - REACTION_DELAY))
                if [ $INTRO_END_TIME -le $INTRO_START_TIME ]; then
                    INTRO_END_TIME=$((INTRO_START_TIME + 1))
                fi
                SKIP_SETUP_MODE=0
                
                if db_set_intro_markers "$series_prefix" "$series_suffix" "$INTRO_START_TIME" "$INTRO_END_TIME"; then
                    echo "✓ Intro: ${INTRO_START_TIME}s - ${INTRO_END_TIME}s"
                    LOADED_INTRO_START=$INTRO_START_TIME
                    LOADED_INTRO_END=$INTRO_END_TIME
                else
                    echo "✗ Ошибка сохранения intro"
                fi
                ;;
        esac
        
    elif [ $position_percent -gt 80 ]; then
        # КОНЕЦ ВИДЕО - устанавливаем CREDITS DURATION
        # Вычитаем задержку (титры начинаются раньше чем мы нажали)
        local credits_duration=$((total_length - current_time - REACTION_DELAY))
        
        if python3 "$SCRIPT_DIR/vlc_db.py" set-credits-duration "$series_prefix" "$series_suffix" "$credits_duration" 2>/dev/null | grep -q "OK"; then
            echo "✓ Credits: ${credits_duration}s (коррекция -${REACTION_DELAY}s)"
            CREDITS_DURATION=$credits_duration
            SKIP_SETUP_MODE=0
        else
            echo "✗ Ошибка сохранения credits"
        fi
        
    else
        # СЕРЕДИНА ВИДЕО
        echo "⚠️  Нажмите RED в начале (<20%) для Intro или в конце (>80%) для Credits"
    fi
}

# Мониторинг для автопропуска intro/outro
monitor_skip_markers() {
    local vlc_pid="$1"
    local intro_skipped=0
    local prev_position=0
    local outro_start=""  # Вычисляется динамически
    
    # Получаем длину видео ОДИН РАЗ
    local video_duration=$(vlc_get_length)
    
    # Вычисляем outro_start если есть credits_duration
    if [ -n "$CREDITS_DURATION" ] && [ -n "$video_duration" ]; then
        outro_start=$((video_duration - CREDITS_DURATION))
        echo "📺 Видео: ${video_duration}s, титры: ${CREDITS_DURATION}s → outro: ${outro_start}s"
    fi
    
    while true; do
        sleep 2
        
        if ! kill -0 "$vlc_pid" 2>/dev/null; then
            break
        fi
        
        local current=$(vlc_get_time)
        
        if [ -z "$current" ]; then
            continue
        fi
        
        # === INTRO CHECK ===
        # Проверяем: есть маркеры И включен skip_intro
        if [ -n "$LOADED_INTRO_START" ] && [ -n "$LOADED_INTRO_END" ] && [ $SKIP_INTRO_ENABLED -eq 1 ] && [ $intro_skipped -eq 0 ]; then
            if [ "$current" -ge "$LOADED_INTRO_START" ] && [ "$current" -lt "$LOADED_INTRO_END" ]; then
                echo "⏩ Пропуск заставки: ${LOADED_INTRO_START}s → ${LOADED_INTRO_END}s"
                vlc_command "seek $LOADED_INTRO_END"
                intro_skipped=1
                sleep 1
            fi
        fi
        
        # === OUTRO CHECK ===
        # Проверяем: есть credits_duration И включен skip_outro
        if [ -n "$outro_start" ] && [ $SKIP_OUTRO_ENABLED -eq 1 ]; then
            # Сброс флага при перемотке назад
            if [ "$current" -lt "$outro_start" ] && [ "$prev_position" -ge "$outro_start" ]; then
                if [ $OUTRO_TRIGGERED -eq 1 ]; then
                    echo "⏪ Сброс outro флага"
                    OUTRO_TRIGGERED=0
                    python3 "$SCRIPT_DIR/vlc_db.py" set-outro-triggered "$VIDEO_BASENAME" 0 2>/dev/null
                fi
            fi
            
            # Pause на outro
            if [ "$current" -ge "$outro_start" ] && [ $OUTRO_TRIGGERED -eq 0 ]; then
                echo "⏸️  Outro - PAUSE (${outro_start}s)"
                vlc_command "pause"
                OUTRO_TRIGGERED=1
                
                # Сохраняем флаг в БД
                python3 "$SCRIPT_DIR/vlc_db.py" set-outro-triggered "$VIDEO_BASENAME" 1 2>/dev/null
                
                # Помечаем видео как просмотренное (100%) чтобы появился [X]
                python3 "$SCRIPT_DIR/vlc_db.py" save_playback "$VIDEO_BASENAME" "$video_duration" "$video_duration" 100 2>/dev/null
                
                # Обновляем кеш статуса чтобы меню показывало [X]
                update_cache_for_file "$VIDEO_BASENAME" "watched"
            fi
        fi
        
        # Проверка окончания видео (в самом конце, после outro)
        if [ -n "$video_duration" ] && [ "$current" -ge $((video_duration - 5)) ]; then
            echo "🏁 Видео завершено - выход в меню"
            vlc_exit
        fi
        
        prev_position=$current
    done
}

echo "Запуск VLC с RC интерфейсом..."
echo "Для ручного управления: nc localhost 4212"
echo ""

# Загружаем skip markers для текущего файла
load_skip_markers "$VIDEO_FILE"

# Загружаем флаг outro_triggered из БД
OUTRO_TRIGGERED=$(python3 "$SCRIPT_DIR/vlc_db.py" get-outro-triggered "$VIDEO_BASENAME" 2>/dev/null)
OUTRO_TRIGGERED=${OUTRO_TRIGGERED:-0}

# Запускаем VLC с RC интерфейсом
if [ -n "$START_TIME" ]; then
    cvlc --intf rc \
         --rc-host localhost:4212 \
         --fullscreen \
         --no-osd \
         --subsdec-encoding=Windows-1251 \
         "$VIDEO_FILE" :start-time=$START_TIME 2>&1 | grep -v "^\[" | grep -v "^VLC" | grep -v "^Command" &
else
    cvlc --intf rc \
         --rc-host localhost:4212 \
         --fullscreen \
         --no-osd \
         --subsdec-encoding=Windows-1251 \
         "$VIDEO_FILE" 2>&1 | grep -v "^\[" | grep -v "^VLC" | grep -v "^Command" &
fi

VLC_PID=$!
echo "VLC PID: $VLC_PID"

# Ждём пока VLC запустится
sleep 3

# Проверяем что VLC запущен
if ! kill -0 $VLC_PID 2>/dev/null; then
    echo "❌ Ошибка: VLC не запустился!"
    exit 1
fi

echo "✓ VLC запущен"
echo "✓ RC интерфейс: localhost:4212"
echo "✓ CEC мониторинг: $CEC_DEVICE"
echo ""
echo "🎮 Мониторинг пульта (нажмите любую кнопку для проверки)..."
echo ""

# Мониторим CEC с максимальной детализацией
cec-client -d 8 -t r "$CEC_DEVICE" 2>&1 | while IFS= read -r line; do
    
    # Показываем все входящие команды для отладки (кроме polling и статус-запросов)
    if [[ "$line" == *"TRAFFIC"* ]] && [[ "$line" == *">>"* ]]; then
        # Пропускаем:
        # - f0, 10, 11 = polling messages
        # - 8f = Give Device Power Status
        # - 8c = Give Device Vendor ID
        # - 83 = Give Physical Address
        # - 46 = Give OSD Name
        # - 87 = Give Device Power Status response
        if [[ "$line" != *"f0"* ]] && \
           [[ "$line" != *"<< 10"* ]] && [[ "$line" != *"<< 11"* ]] && \
           [[ "$line" != *"01:8f"* ]] && [[ "$line" != *"01:8c"* ]] && \
           [[ "$line" != *"01:83"* ]] && [[ "$line" != *"01:46"* ]] && \
           [[ "$line" != *"01:87"* ]]; then
            echo "[CEC RAW] $line"
        fi
    fi

    # === ОБРАБОТКА КНОПОК ПУЛЬТА ===
    
    # OK → Play/Pause
    if [[ "$line" == *"44:00"* ]]; then
        echo "▶️  Play/Pause"
        vlc_command "pause"
        continue
    fi
    
    # UP → +30 sec
    if [[ "$line" == *"44:01"* ]]; then
        echo "⏩⏩ +30 sec"
        vlc_command "seek +30"
        continue
    fi
    
    # DOWN → -30 sec
    if [[ "$line" == *"44:02"* ]]; then
        echo "⏪⏪ -30 sec"
        vlc_command "seek -30"
        continue
    fi
    
    # LEFT → -10 sec
    if [[ "$line" == *"44:03"* ]]; then
        echo "⏪ -10 sec"
        vlc_command "seek -10"
        continue
    fi
    
    # RIGHT → +10 sec
    if [[ "$line" == *"44:04"* ]]; then
        echo "⏩ +10 sec"
        vlc_command "seek +10"
        continue
    fi
    
    # BACK → Exit
    if [[ "$line" == *"44:0d"* ]] || [[ "$line" == *"44:0D"* ]]; then
        echo "⏹️  Exit"
        vlc_exit
    fi

# INFO → Show time
    if [[ "$line" == *"44:35"* ]]; then
        echo "⏱️  Запрос времени..."
        
        current=$(vlc_get_time)
        total=$(vlc_get_length)
        
        if [ -n "$current" ] && [ -n "$total" ]; then
            remaining=$((total - current))
            current_fmt=$(printf "%02d:%02d:%02d" $((current/3600)) $((current%3600/60)) $((current%60)))
            total_fmt=$(printf "%02d:%02d:%02d" $((total/3600)) $((total%3600/60)) $((total%60)))
            remaining_fmt=$(printf "%02d:%02d:%02d" $((remaining/3600)) $((remaining%3600/60)) $((remaining%60)))
            echo "⏱️  $current_fmt / $total_fmt (осталось: $remaining_fmt)"
        else
            echo "⏱️  Ошибка получения времени"
        fi
        continue
    fi

# RED → Skip Intro/Outro setup
    if [[ "$line" == *"44:72"* ]]; then
        handle_red_button "$VIDEO_FILE"
        continue
    fi
    
    # GREEN → Subtitles (циклическое переключение, включая выкл)
    if [[ "$line" == *"44:73"* ]]; then
        echo "📝 Subtitles switch"
        # Получаем текущие субтитры и переключаем (включая -1 = выкл)
        current_strack=$(vlc_query "strack" | grep -oE 'track [0-9-]+' | grep -oE '[0-9-]+' | head -1)
        if [ -n "$current_strack" ]; then
            if [ "$current_strack" -eq "-1" ]; then
                next_strack=0
            else
                next_strack=$((current_strack + 1))
            fi
            vlc_command "strack $next_strack"
            if [ "$next_strack" -eq "0" ]; then
                echo "   → Subtitles: ON (track $next_strack)"
            else
                echo "   → Subtitles: track $next_strack)"
            fi
        fi
        continue
    fi
    
    # YELLOW → Volume +
    if [[ "$line" == *"44:74"* ]]; then
        echo "🔊 Volume +"
        vlc_command "volup 1"
        continue
    fi
    
    # BLUE → Volume -
    if [[ "$line" == *"44:71"* ]]; then
        echo "🔉 Volume -"
        vlc_command "voldown 1"
        continue
    fi
    
    # CHANNEL UP → +60 sec
    if [[ "$line" == *"44:30"* ]]; then
        echo "⏩⏩⏩ +60 sec"
        vlc_command "seek +60"
        continue
    fi
    
    # CHANNEL DOWN → -60 sec
    if [[ "$line" == *"44:31"* ]]; then
        echo "⏪⏪⏪ -60 sec"
        vlc_command "seek -60"
        continue
    fi
    
    # 0 → Start
    if [[ "$line" == *"44:20"* ]]; then
        echo "⏮️  To start"
        vlc_command "seek 0"
        continue
    fi
    
# 1 → 10%
    if [[ "$line" == *"44:21"* ]]; then
        total=$(vlc_get_length)
        if [ -n "$total" ]; then
            echo "🎯 Jump to 10%"
            vlc_command "seek $((total * 10 / 100))"
        fi
        continue
    fi
    
    # 2 → 20%
    if [[ "$line" == *"44:22"* ]]; then
        total=$(vlc_get_length)
        if [ -n "$total" ]; then
            echo "🎯 Jump to 20%"
            vlc_command "seek $((total * 20 / 100))"
        fi
        continue
    fi
    
    # 3 → 30%
    if [[ "$line" == *"44:23"* ]]; then
        total=$(vlc_get_length)
        if [ -n "$total" ]; then
            echo "🎯 Jump to 30%"
            vlc_command "seek $((total * 30 / 100))"
        fi
        continue
    fi
    
    # 4 → 40%
    if [[ "$line" == *"44:24"* ]]; then
        total=$(vlc_get_length)
        if [ -n "$total" ]; then
            echo "🎯 Jump to 40%"
            vlc_command "seek $((total * 40 / 100))"
        fi
        continue
    fi
    
    # 5 → 50%
    if [[ "$line" == *"44:25"* ]]; then
        total=$(vlc_get_length)
        if [ -n "$total" ]; then
            echo "🎯 Jump to 50%"
            vlc_command "seek $((total * 50 / 100))"
        fi
        continue
    fi
    
    # 6 → 60%
    if [[ "$line" == *"44:26"* ]]; then
        total=$(vlc_get_length)
        if [ -n "$total" ]; then
            echo "🎯 Jump to 60%"
            vlc_command "seek $((total * 60 / 100))"
        fi
        continue
    fi
    
    # 7 → 70%
    if [[ "$line" == *"44:27"* ]]; then
        total=$(vlc_get_length)
        if [ -n "$total" ]; then
            echo "🎯 Jump to 70%"
            vlc_command "seek $((total * 70 / 100))"
        fi
        continue
    fi
    
    # 8 → 80%
    if [[ "$line" == *"44:28"* ]]; then
        total=$(vlc_get_length)
        if [ -n "$total" ]; then
            echo "🎯 Jump to 80%"
            vlc_command "seek $((total * 80 / 100))"
        fi
        continue
    fi
    
    # 9 → 90%
    if [[ "$line" == *"44:29"* ]]; then
        total=$(vlc_get_length)
        if [ -n "$total" ]; then
            echo "🎯 Jump to 90%"
            vlc_command "seek $((total * 90 / 100))"
        fi
        continue
    fi
    
    # Проверяем что VLC ещё работает
    if ! kill -0 $VLC_PID 2>/dev/null; then
        echo "VLC завершён"
        exit 0
    fi
done &

CEC_PID=$!

# Запускаем мониторинг прогресса в фоне (ПОСЛЕ CEC)
# Передаём basename чтобы избежать дублирования записей в БД
monitor_vlc_playback "$VIDEO_BASENAME" $VLC_PID &
MONITOR_PID=$!

# Запускаем мониторинг skip markers в фоне
monitor_skip_markers $VLC_PID &
SKIP_MONITOR_PID=$!

# Функция для корректного завершения
cleanup() {
    echo ""
    echo "Завершение работы..."
    
    # Финальное сохранение позиции
    # Передаём basename чтобы избежать дублирования записей в БД
    finalize_playback "$VIDEO_BASENAME"
    
    # Завершаем процессы
    kill $SKIP_MONITOR_PID 2>/dev/null
    kill $MONITOR_PID 2>/dev/null
    kill $CEC_PID 2>/dev/null
    kill $VLC_PID 2>/dev/null
    pkill -P $$ 2>/dev/null
    exit 0
}

trap cleanup INT TERM

# Ждём завершения VLC
wait $VLC_PID
