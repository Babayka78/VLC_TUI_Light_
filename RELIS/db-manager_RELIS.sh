#!/bin/bash

# db-manager.sh - Библиотека для работы с SQLite БД (через Python vlc_db.py)
# Версия: 0.2.0
# Дата: 02.12.2025
# Изменения: Рефакторинг для защиты от SQL injection - все SQL операции через vlc_db.py

# Константы
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_PATH="${SCRIPT_DIR}/vlc_media.db"
PYTHON_DB="${SCRIPT_DIR}/vlc_db.py"

# ============================================================================
# ПРОВЕРКА ЗАВИСИМОСТЕЙ
# ============================================================================

# Проверка наличия Python 3
if ! command -v python3 &> /dev/null; then
    echo "❌ ОШИБКА: python3 не найден!"
    echo ""
    echo "Для установки на Raspberry Pi (Debian) выполните:"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install -y python3"
    echo ""
    return 1 2>/dev/null || exit 1
fi

# Проверка версии Python (минимум 3.7)
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 7 ]); then
    echo "❌ ОШИБКА: Требуется Python 3.7+, найден: $PYTHON_VERSION"
    echo ""
    echo "Обновите Python:"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install -y python3"
    echo ""
    return 1 2>/dev/null || exit 1
fi

# Проверка наличия vlc_db.py
if [ ! -f "$PYTHON_DB" ]; then
    echo "❌ ОШИБКА: $PYTHON_DB не найден!"
    echo ""
    return 1 2>/dev/null || exit 1
fi

# ============================================================================
# ИНИЦИАЛИЗАЦИЯ БД
# ============================================================================

# Создание БД и таблиц если их нет
db_init() {
    python3 "$PYTHON_DB" init > /dev/null 2>&1
}

# ============================================================================
# УТИЛИТЫ
# ============================================================================

# Извлечение series_prefix из имени файла (название сериала + сезон)
# Параметры: $1 - filename
# Возвращает: "ShowName.S##" или пустую строку для фильмов
extract_series_prefix() {
    local filename="$1"
    
    # Проверяем паттерн S##E## или S##.E##
    if echo "$filename" | grep -qiE '[._\ ]S[0-9]{1,2}[._\ ]?E[0-9]{1,2}'; then
        # Извлекаем всё до E## (включая S##)
        local prefix=$(echo "$filename" | sed -E 's/([._\ ]S[0-9]{1,2})[._\ ]?E[0-9]{1,2}.*/\1/')
        
        # Нормализуем номер сезона (убрать leading zeros, потом добавить обратно)
        local show_part=$(echo "$prefix" | sed -E 's/[._\ ]S[0-9]{1,2}$//')
        local season=$(echo "$prefix" | sed -E 's/.*[._\ ]S([0-9]{1,2})$/\1/')
        
        # Убрать leading zeros
        season=$(echo "$season" | sed 's/^0*//')
        [ -z "$season" ] && season=0
        
        # Форматировать с leading zero
        local season_padded=$(printf "%02d" "$season")
        
        echo "${show_part}.S${season_padded}"
    else
        echo ""  # Не сериал
    fi
}

# Извлечение series_suffix из имени файла (всё после E##, включая расширение)
# Параметры: $1 - filename
# Возвращает: "HDR.2160p.mkv", "720p.mp4", "mkv" или пустую строку
extract_series_suffix() {
    local filename="$1"
    
    # Проверяем паттерн S##E## или S##.E##
    if echo "$filename" | grep -qiE '[._\ ]S[0-9]{1,2}[._\ ]?E[0-9]{1,2}'; then
        # Извлекаем всё после E## (включая расширение)
        local suffix=$(echo "$filename" | sed -E 's/.*[._\ ]S[0-9]{1,2}[._\ ]?E[0-9]{1,2}[._\ ]?//')
        
        # Убрать leading точки/подчёркивания/пробелы
        suffix=$(echo "$suffix" | sed 's/^[._ ]*//')
        
        echo "$suffix"
    else
        echo ""  # Не сериал
    fi
}

# Извлечение композитного series_key (для обратной совместимости)
# Параметры: $1 - filename
# Возвращает: "prefix||suffix" или пустую строку
extract_series_key() {
    local filename="$1"
    local prefix=$(extract_series_prefix "$filename")
    local suffix=$(extract_series_suffix "$filename")
    
    if [ -n "$prefix" ]; then
        echo "${prefix}||${suffix}"
    else
        echo ""  # Не сериал
    fi
}

# ============================================================================
# PLAYBACK ФУНКЦИИ
# ============================================================================

# Сохранение прогресса воспроизведения
# Параметры: $1 - filename, $2 - position, $3 - duration, $4 - percent, 
#            $5 - series_prefix (optional), $6 - series_suffix (optional)
db_save_playback() {
    local filename="$1"
    local position="$2"
    local duration="$3"
    local percent="$4"
    local series_prefix="${5:-}"
    local series_suffix="${6:-}"
    
    python3 "$PYTHON_DB" save_playback "$filename" "$position" "$duration" "$percent" "$series_prefix" "$series_suffix" > /dev/null 2>&1
}

# Получение данных воспроизведения
# Параметры: $1 - filename
# Возвращает: position|duration|percent|series_prefix|series_suffix
db_get_playback() {
    local filename="$1"
    python3 "$PYTHON_DB" get_playback "$filename"
}

# Получение процента просмотра
# Параметры: $1 - filename
# Возвращает: percent (0 если нет записи)
db_get_playback_percent() {
    local filename="$1"
    python3 "$PYTHON_DB" get_percent "$filename"
}

# ============================================================================
# SERIES SETTINGS ФУНКЦИИ
# ============================================================================

# Сохранение настроек сериала
# Параметры: $1 - series_prefix, $2 - series_suffix, $3 - autoplay, $4 - skip_intro, $5 - skip_outro,
#            $6 - intro_start, $7 - intro_end, $8 - outro_start
db_save_series_settings() {
    local series_prefix="$1"
    local series_suffix="$2"
    local autoplay="$3"
    local skip_intro="$4"
    local skip_outro="$5"
    local intro_start="${6:-}"
    local intro_end="${7:-}"
    local outro_start="${8:-}"
    
    python3 "$PYTHON_DB" save_settings "$series_prefix" "$series_suffix" "$autoplay" "$skip_intro" "$skip_outro" "$intro_start" "$intro_end" "$outro_start" > /dev/null 2>&1
}

# Получение настроек сериала
# Параметры: $1 - series_prefix, $2 - series_suffix
# Возвращает: autoplay|skip_intro|skip_outro|intro_start|intro_end|outro_start
db_get_series_settings() {
    local series_prefix="$1"
    local series_suffix="$2"
    python3 "$PYTHON_DB" get_settings "$series_prefix" "$series_suffix"
}

# Проверка существования настроек
# Параметры: $1 - series_prefix, $2 - series_suffix
# Возвращает: 0 если есть, 1 если нет
db_series_settings_exist() {
    local series_prefix="$1"
    local series_suffix="$2"
    
    local result=$(python3 "$PYTHON_DB" settings_exist "$series_prefix" "$series_suffix")
    
    if [ "$result" = "1" ]; then
        return 0
    else
        return 1
    fi
}

# Поиск других версий сериала с тем же prefix, но другим suffix
# Параметры: $1 - series_prefix, $2 - series_suffix (текущий, может быть пустым)
# Возвращает: список suffix|last_filename|max_percent (по строке на версию)
db_find_other_versions() {
    local series_prefix="$1"
    local current_suffix="$2"
    
    python3 "$PYTHON_DB" find_versions "$series_prefix" "$current_suffix"
}

# ============================================================================
# ТЕСТОВЫЕ/DEBUG ФУНКЦИИ (только для разработки)
# ============================================================================

# Запись debug данных в description
# Параметры: $1 - filename, $2 - debug_data
db_save_debug_info() {
    local filename="$1"
    local debug_data="$2"
    
    sqlite3 "$DB_PATH" <<EOF
UPDATE playback
SET description = '$debug_data'
WHERE filename = '$filename';
EOF
}

# Чтение debug данных из description
# Параметры: $1 - filename
# Возвращает: содержимое description
db_get_debug_info() {
    local filename="$1"
    
    sqlite3 "$DB_PATH" "SELECT COALESCE(description, '') FROM playback WHERE filename = '$filename';"
}

# ============================================================================
# АВТОИНИЦИАЛИЗАЦИЯ
# ============================================================================

# Инициализируем БД при загрузке библиотеки
db_init
