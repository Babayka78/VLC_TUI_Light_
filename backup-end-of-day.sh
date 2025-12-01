#!/bin/bash
# Скрипт для создания бэкапов на конец рабочего дня
# Использование: ./backup-end-of-day.sh

TODAY=$(date +%y%m%d)
TIMESTAMP=$(date +%y%m%d_%H%M)

echo "========================================="
echo "Создание бэкапов на конец дня: $TODAY"
echo "========================================="
echo ""

# ============================================
# 1. Копирование артефактов сессии в DOCS/Brain/
# ============================================
echo "📂 Копирование артефактов сессии..."

# Определить текущую session ID
session_id=$(ls -t ~/.gemini/antigravity/brain 2>/dev/null | head -1)

if [ -n "$session_id" ]; then
    brain_dir="$HOME/.gemini/antigravity/brain/$session_id"
    
    if [ -d "$brain_dir" ]; then
        # Создать папку для артефактов
        mkdir -p "DOCS/Brain/$TIMESTAMP"
        
        # Копировать все .md файлы
        cp "$brain_dir"/*.md "DOCS/Brain/$TIMESTAMP/" 2>/dev/null
        
        # Копировать историю изменений (.resolved.*)
        cp "$brain_dir"/*.md.resolved* "DOCS/Brain/$TIMESTAMP/" 2>/dev/null
        
        # Копировать комментарии (.metadata.json)
        cp "$brain_dir"/*.md.metadata.json "DOCS/Brain/$TIMESTAMP/" 2>/dev/null
        
        # Подсчитать количество скопированных файлов
        artifact_count=$(ls -1 "DOCS/Brain/$TIMESTAMP/" 2>/dev/null | wc -l | tr -d ' ')
        
        if [ "$artifact_count" -gt 0 ]; then
            echo "  ✓ Артефакты → DOCS/Brain/$TIMESTAMP/ ($artifact_count файл(ов))"
        else
            echo "  ⚠️  Артефакты не найдены в ~/.gemini/antigravity/brain/$session_id"
            rmdir "DOCS/Brain/$TIMESTAMP" 2>/dev/null
        fi
    else
        echo "  ⚠️  Папка сессии не найдена: $brain_dir"
    fi
else
    echo "  ⚠️  Session ID не найден в ~/.gemini/antigravity/brain/"
fi

echo ""

# ============================================
# 2. Бэкап документации (только если изменилась)
# ============================================
echo "📝 Бэкап документации..."

# Создать папку для бэкапов
mkdir -p "BAK/$TODAY"

# Функция для проверки изменений файла
file_changed() {
    local file="$1"
    local backup_pattern="$2"
    
    # Если нет бэкапов - файл считается изменённым
    if ! ls BAK/*/"$backup_pattern" 1>/dev/null 2>&1; then
        return 0
    fi
    
    # Сравнить с последним бэкапом
    last_backup=$(ls -t BAK/*/"$backup_pattern" 2>/dev/null | head -1)
    
    if [ -f "$last_backup" ]; then
        if ! diff -q "$file" "$last_backup" >/dev/null 2>&1; then
            return 0  # Файл изменился
        else
            return 1  # Файл не изменился
        fi
    fi
    
    return 0  # По умолчанию считаем, что изменился
}

# Бэкап HANDOFF.md (новая структура)
if [ -f "DOCS/INSTRUCTIONS/HANDOFF.md" ]; then
    if file_changed "DOCS/INSTRUCTIONS/HANDOFF.md" "HANDOFF_*.bak"; then
        mkdir -p "BAK/$TODAY/INSTRUCTIONS"
        cp "DOCS/INSTRUCTIONS/HANDOFF.md" "BAK/$TODAY/INSTRUCTIONS/HANDOFF_${TIMESTAMP}.bak"
        echo "  ✓ DOCS/INSTRUCTIONS/HANDOFF.md"
    else
        echo "  ⊘ HANDOFF.md (не изменился)"
    fi
fi

# Бэкап HANDOFF-NEXT-SESSION.md (старая структура, если еще есть)
if [ -f "DOCS/HANDOFF-NEXT-SESSION.md" ]; then
    if file_changed "DOCS/HANDOFF-NEXT-SESSION.md" "HANDOFF-NEXT-SESSION_*.bak"; then
        cp "DOCS/HANDOFF-NEXT-SESSION.md" "BAK/$TODAY/HANDOFF-NEXT-SESSION_${TIMESTAMP}.bak"
        echo "  ✓ DOCS/HANDOFF-NEXT-SESSION.md (legacy)"
    else
        echo "  ⊘ HANDOFF-NEXT-SESSION.md (не изменился)"
    fi
fi

# Бэкап CHANGELOG.md
if [ -f "DOCS/CHANGELOG.md" ]; then
    if file_changed "DOCS/CHANGELOG.md" "CHANGELOG_*.bak"; then
        cp "DOCS/CHANGELOG.md" "BAK/$TODAY/CHANGELOG_${TIMESTAMP}.bak"
        echo "  ✓ DOCS/CHANGELOG.md"
    else
        echo "  ⊘ CHANGELOG.md (не изменился)"
    fi
fi

# Бэкап development_roadmap.md
if [ -f "DOCS/future_features/development_roadmap.md" ]; then
    if file_changed "DOCS/future_features/development_roadmap.md" "development_roadmap_*.bak"; then
        cp "DOCS/future_features/development_roadmap.md" "BAK/$TODAY/development_roadmap_${TIMESTAMP}.bak"
        echo "  ✓ DOCS/development_roadmap.md"
    else
        echo "  ⊘ development_roadmap.md (не изменился)"
    fi
fi

echo ""
echo "========================================="
echo "✅ Процесс завершён!"
echo "========================================="
echo ""
echo "📂 Артефакты сессии: DOCS/Brain/$TIMESTAMP/"
echo "💾 Бэкапы документации: BAK/$TODAY/"
echo ""
echo "💡 Примечание:"
echo "   - RELIS файлы бэкапятся ТОЛЬКО при релизе"
echo "   - Документация бэкапится только если изменилась"
echo ""
