#!/bin/bash

# serials.sh - Библиотека для управления настройками сериалов
# Версия: 0.1.0
# Дата: 29.11.2025

# Глобальные переменные
SETTINGS_FILE=".series_settings"

# Функция для отображения меню настроек сериалов
# Параметры:
#   $1 - текущая директория (для сохранения настроек)
show_series_settings() {
    local current_dir="$1"
    local settings_path="$current_dir/$SETTINGS_FILE"
    
    # Загружаем текущие настройки
    local autoplay=$(load_setting "$current_dir" "autoplay" "off")
    local skip_intro=$(load_setting "$current_dir" "skip_intro" "off")
    local skip_outro=$(load_setting "$current_dir" "skip_outro" "off")
    
    # Восстанавливаем TTY
    exec < /dev/tty
    exec > /dev/tty
    
    # Показываем checklist (только 3 опции)
    local selected=$(dialog --output-fd 1 \
        --title "Настройки воспроизведения" \
        --checklist "Выберите опции (SPACE для выбора):" 12 60 3 \
        "autoplay" "Автопродолжение следующей серии" $autoplay \
        "skip_intro" "Пропуск начальной заставки" $skip_intro \
        "skip_outro" "Пропуск конечных титров" $skip_outro \
        2>/dev/tty)
    
    local exit_code=$?
    
    # Если пользователь нажал OK, сохраняем настройки
    if [ $exit_code -eq 0 ]; then
        save_series_settings "$current_dir" "$selected"
    fi
}

# Функция для сохранения настроек в файл
# Параметры:
#   $1 - директория
#   $2 - строка с выбранными опциями (разделённые пробелами)
save_series_settings() {
    local current_dir="$1"
    local selected="$2"
    local settings_path="$current_dir/$SETTINGS_FILE"
    
    # Создаём файл настроек
    cat > "$settings_path" << EOF
# Настройки воспроизведения сериалов
# Автоматически создано: $(date '+%Y-%m-%d %H:%M:%S')

EOF
    
    # Устанавливаем значения на основе выбора (только 3 опции)
    if echo "$selected" | grep -q "autoplay"; then
        echo "autoplay=1" >> "$settings_path"
    else
        echo "autoplay=0" >> "$settings_path"
    fi
    
    if echo "$selected" | grep -q "skip_intro"; then
        echo "skip_intro=1" >> "$settings_path"
    else
        echo "skip_intro=0" >> "$settings_path"
    fi
    
    if echo "$selected" | grep -q "skip_outro"; then
        echo "skip_outro=1" >> "$settings_path"
    else
        echo "skip_outro=0" >> "$settings_path"
    fi
}

# Функция для загрузки одной настройки
# Параметры:
#   $1 - директория
#   $2 - ключ настройки
#   $3 - значение по умолчанию (on/off)
# Возвращает: "on" или "off"
load_setting() {
    local current_dir="$1"
    local key="$2"
    local default_value="$3"
    local settings_path="$current_dir/$SETTINGS_FILE"
    
    # Если файла нет, возвращаем значение по умолчанию
    if [ ! -f "$settings_path" ]; then
        echo "$default_value"
        return
    fi
    
    # Читаем значение из файла
    local value=$(grep "^${key}=" "$settings_path" 2>/dev/null | cut -d= -f2)
    
    # Конвертируем 1/0 в on/off для dialog
    if [ "$value" == "1" ]; then
        echo "on"
    elif [ "$value" == "0" ]; then
        echo "off"
    else
        echo "$default_value"
    fi
}

# Функция для получения строки статуса настроек для пункта меню (Вариант 1)
# Параметры:
#   $1 - директория
# Возвращает: строку вида "[✓] Автопродолжение  [✗] Пропуск заставки  [✗] Титры  [✓] Уведомления"
get_settings_status_menuitem() {
    local current_dir="$1"
    
    local autoplay=$(get_setting_value "$current_dir" "autoplay")
    local skip_intro=$(get_setting_value "$current_dir" "skip_intro")
    local skip_outro=$(get_setting_value "$current_dir" "skip_outro")
    local notification=$(get_setting_value "$current_dir" "show_notification")
    
    # Определяем иконки (✓ или ✗)
    local auto_icon="✗"; [ "$autoplay" == "1" ] && auto_icon="✓"
    local intro_icon="✗"; [ "$skip_intro" == "1" ] && intro_icon="✓"
    local outro_icon="✗"; [ "$skip_outro" == "1" ] && outro_icon="✓"
    local notif_icon="✗"; [ "$notification" == "1" ] && notif_icon="✓"
    
    echo "[$auto_icon] Автопродолжение  [$intro_icon] Пропуск заставки  [$outro_icon] Титры  [$notif_icon] Уведомления"
}

# Функция для получения компактной строки статуса для подзаголовка (Вариант 2)
# Параметры:
#   $1 - директория
# Возвращает: строку вида "[X] Auto Continue  [ ] Intro  [X] Outro"
get_settings_status_compact() {
    local current_dir="$1"
    local settings_path="$current_dir/$SETTINGS_FILE"
    
    # Получаем значения настроек (пустая строка если файла нет)
    local autoplay=$(get_setting_value "$current_dir" "autoplay")
    local skip_intro=$(get_setting_value "$current_dir" "skip_intro")
    local skip_outro=$(get_setting_value "$current_dir" "skip_outro")
    
    # Формируем иконки для каждой настройки
    local auto_icon=" "; [ "$autoplay" == "1" ] && auto_icon="X"
    local intro_icon=" "; [ "$skip_intro" == "1" ] && intro_icon="X"
    local outro_icon=" "; [ "$skip_outro" == "1" ] && outro_icon="X"
    
    # Всегда показываем детальный статус
    echo "[$auto_icon] Auto Continue  [$intro_icon] Intro  [$outro_icon] Outro"
}


# Функция для получения значения настройки (для использования в других скриптах)
# Параметры:
#   $1 - директория
#   $2 - ключ настройки
# Возвращает: "1" или "0" или пустую строку если не найдено
get_setting_value() {
    local current_dir="$1"
    local key="$2"
    local settings_path="$current_dir/$SETTINGS_FILE"
    
    if [ ! -f "$settings_path" ]; then
        echo ""
        return
    fi
    
    grep "^${key}=" "$settings_path" 2>/dev/null | cut -d= -f2
}
