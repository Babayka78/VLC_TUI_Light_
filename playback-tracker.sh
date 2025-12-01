#!/bin/bash
# playback-tracker.sh - Библиотека отслеживания прогресса воспроизведения
# Версия: 0.3.0
# Changelog:
#   0.1.0 - Первая версия
#   0.2.0 - Добавлен автомониторинг VLC (29.11.2025)
#   0.3.0 - Переход на SQLite БД (29.11.2025)
#
# Использование: source "$SCRIPT_DIR/playback-tracker.sh"

# Подключаем БД библиотеку
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/db-manager.sh"

# Версия библиотеки (Semantic Versioning: MAJOR.MINOR.PATCH)
PLAYBACK_TRACKER_VERSION="0.3.0"
PLAYBACK_TRACKER_MIN_VERSION="0.3.0"  # Минимальная совместимая версия

# Функция проверки совместимости версий
check_version_compatibility() {
    local required_version="$1"
    local current_version="$PLAYBACK_TRACKER_VERSION"
    
    # Простая проверка: major version должна совпадать
    local req_major=$(echo "$required_version" | cut -d. -f1)
    local cur_major=$(echo "$current_version" | cut -d. -f1)
    
    if [ "$req_major" != "$cur_major" ]; then
        echo "❌ ОШИБКА: Несовместимая версия playback-tracker.sh"
        echo "   Требуется: $required_version"
        echo "   Текущая:   $current_version"
        return 1
    fi
    
    return 0
}

# ============================================================
# НАСТРОЙКИ (можно изменять для тонкой настройки)
# ============================================================

# Паттерн для определения сериалов (legacy, для обратной совместимости)
# Поддерживает S##E## с любыми разделителями: . - _ пробел или без разделителя
# Примеры: S01E01, S01.E01, S01-E01, S01_E01, S01 E01
SERIES_PATTERN='S[0-9][0-9][-_. ]*E[0-9][0-9]'

# Пороги процентов просмотра
WATCHED_THRESHOLD=99     # Процент для [X] - просмотрено
PARTIAL_THRESHOLD=1      # Минимальный процент для [T] - частично

# Интервал мониторинга в секундах
MONITOR_INTERVAL=60

# ============================================================
# ФУНКЦИИ
# ============================================================

# DEPRECATED: Эта функция больше не используется, оставлена для обратной совместимости
# TODO: Удалить в следующей версии
# Проверяет является ли файл сериалом по паттерну
# Использование: is_series_file "filename"
# Возвращает: 0 если сериал, 1 если нет
is_series_file() {
    local filename="$1"
    
    if [[ "$filename" =~ $SERIES_PATTERN ]]; then
        return 0
    fi
    
    return 1
}

# DEPRECATED: Эта функция больше не используется, оставлена для обратной совместимости
# TODO: Удалить в следующей версии
# Извлекает код эпизода (S##E##) из имени файла
# Использование: get_episode_code "filename"
# Возвращает: S01E01 или пустую строку
get_episode_code() {
    local filename="$1"
    
    # Ищем паттерн S##...E##
    if [[ "$filename" =~ $SERIES_PATTERN ]]; then
        local matched="${BASH_REMATCH[0]}"
        
        # Извлекаем S## и E## части
        local season=$(echo "$matched" | grep -oE 'S[0-9][0-9]')
        local episode=$(echo "$matched" | grep -oE 'E[0-9][0-9]')
        
        if [ -n "$season" ] && [ -n "$episode" ]; then
            # Возвращаем нормализованный формат S##E##
            echo "${season}${episode}"
            return 0
        fi
    fi
    
    # Ничего не найдено
    echo ""
    return 1
}

# Возвращает путь к .playback файлу для директории
# Использование: get_playback_file "/path/to/video/dir"
# Возвращает: /path/to/video/dir/.playback
get_playback_file() {
    local dir="$1"
    echo "$dir/.playback"
}

# Загружает прогресс воспроизведения для файла из .playback
# Использование: load_progress "/path/to/dir" "filename"
# Возвращает: "seconds:total:percent" или пустую строку
load_progress() {
    local dir="$1"
    local filename="$2"
    
    # Используем БД вместо файлов
    local playback_data=$(db_get_playback "$filename")
    
    if [ -z "$playback_data" ]; then
        echo ""
        return 1
    fi
    
    # Формат из БД: position|duration|percent|series_key
    # Возвращаем: position:duration:percent (для совместимости)
    echo "$playback_data" | cut -d'|' -f1-3 | tr '|' ':'
    return 0
}

# Сохраняет прогресс воспроизведения в .playback файл
# Использование: save_progress "/path/to/dir" "filename" seconds total percent
save_progress() {
    local dir="$1"
    local filename="$2"
    local seconds="$3"
    local total="$4"
    local percent="$5"
    
    # Извлекаем series_key из имени файла
    local series_key=$(extract_series_key "$filename")
    
    # Сохраняем в БД
    db_save_playback "$filename" "$seconds" "$total" "$percent" "$series_key"
    
    # DEBUG: Сохраняем timestamp в description для тестов
    db_save_debug_info "$filename" "updated_at:$(date +%s)"
    
    return 0
}

# Возвращает иконку статуса для файла
# Использование: get_status_icon "/path/to/dir" "filename"
# Возвращает: "[ ]" "[T]" или "[X]"
get_status_icon() {
    local dir="$1"
    local filename="$2"
    
    # Используем БД напрямую
    local percent=$(db_get_playback_percent "$filename")
    
    # Определяем иконку по порогам
    if [ "$percent" -ge "$WATCHED_THRESHOLD" ]; then
        echo "[X]"
    elif [ "$percent" -ge "$PARTIAL_THRESHOLD" ]; then
        echo "[T]"
    else
        echo "[ ]"
    fi
    
    return 0
}

# Возвращает процент просмотра для файла
# Использование: get_progress_percent "/path/to/dir" "filename"
# Возвращает: процент (0-100) или 0 если нет данных
get_progress_percent() {
    local dir="$1"
    local filename="$2"
    
    local progress=$(load_progress "$dir" "$filename")
    
    if [ -z "$progress" ]; then
        echo "0"
        return 0
    fi
    
    # Извлекаем процент
    echo "$progress" | cut -d: -f3
    return 0
}

# ============================================================
# МОНИТОРИНГ VLC ВОСПРОИЗВЕДЕНИЯ
# ============================================================

# Мониторинг прогресса воспроизведения VLC в фоне
# Использование: monitor_vlc_playback "/path/to/video.avi" VLC_PID
# Возвращает: PID процесса мониторинга
monitor_vlc_playback() {
    local video_file="$1"
    local vlc_pid="$2"
    local video_dir=$(dirname "$video_file")
    local video_name=$(basename "$video_file")
    
    (
        while true; do
            sleep "$MONITOR_INTERVAL"  # Используем настройку из начала файла (60 сек)
            
            # Проверяем что VLC ещё работает
            if ! kill -0 "$vlc_pid" 2>/dev/null; then
                break
            fi
            
            # Получаем позицию через VLC RC (timeout 1 сек)
            local current=$(echo "get_time" | nc -w 1 localhost 4212 2>&1 | grep -oE '[0-9]+' | tail -1)
            local total=$(echo "get_length" | nc -w 1 localhost 4212 2>&1 | grep -oE '[0-9]+' | tail -1)
            
            # Если получили данные - сохраняем
            if [ -n "$current" ] && [ -n "$total" ] && [ "$total" -gt 0 ]; then
                local percent=$((current * 100 / total))
                save_progress "$video_dir" "$video_name" "$current" "$total" "$percent"
            fi
        done
    ) &
    
    echo $!  # Возвращаем PID процесса мониторинга
}

# Финальное сохранение позиции при выходе
# Использование: finalize_playback "/path/to/video.avi"
finalize_playback() {
    local video_file="$1"
    local video_dir=$(dirname "$video_file")
    local video_name=$(basename "$video_file")
    
    # Получаем позицию (timeout 2 сек - дольше т.к. это финальное)
    local current=$(echo "get_time" | nc -w 2 localhost 4212 2>&1 | grep -oE '[0-9]+' | tail -1)
    local total=$(echo "get_length" | nc -w 2 localhost 4212 2>&1 | grep -oE '[0-9]+' | tail -1)
    
    if [ -n "$current" ] && [ -n "$total" ] && [ "$total" -gt 0 ]; then
        local percent=$((current * 100 / total))
        save_progress "$video_dir" "$video_name" "$current" "$total" "$percent"
        return 0
    fi
    
    return 1
}
