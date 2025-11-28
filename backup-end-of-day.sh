#!/bin/bash
# Скрипт для создания бэкапов на конец рабочего дня
# Использование: ./backup-end-of-day.sh

TODAY=$(date +%y%m%d)
TIMESTAMP=$(date +%y%m%d_%H%M)

# Создать папку для бэкапов
mkdir -p BAK/$TODAY

echo "========================================="
echo "Создание бэкапов на конец дня: $TODAY"
echo "========================================="
echo ""

# Бэкап RELIS файлов из папки RELIS/ (ВСЕГДА, даже если не было изменений)
echo "📦 Бэкап RELIS файлов..."
if [ -f "RELIS/vlc-cec_RELIS.sh" ]; then
    cp RELIS/vlc-cec_RELIS.sh "BAK/$TODAY/vlc-cec_RELIS_V#_${TIMESTAMP}.bak"
    echo "  ✓ RELIS/vlc-cec_RELIS.sh"
fi

if [ -f "RELIS/video-menu_RELIS.sh" ]; then
    cp RELIS/video-menu_RELIS.sh "BAK/$TODAY/video-menu_RELIS_V#_${TIMESTAMP}.bak"
    echo "  ✓ RELIS/video-menu_RELIS.sh"
fi

if [ -f "RELIS/playback-tracker_RELIS.sh" ]; then
    cp RELIS/playback-tracker_RELIS.sh "BAK/$TODAY/playback-tracker_RELIS_V#_${TIMESTAMP}.bak"
    echo "  ✓ RELIS/playback-tracker_RELIS.sh"
fi

if [ -f "RELIS/series-tracker_RELIS.sh" ]; then
    cp RELIS/series-tracker_RELIS.sh "BAK/$TODAY/series-tracker_RELIS_V#_${TIMESTAMP}.bak"
    echo "  ✓ RELIS/series-tracker_RELIS.sh (legacy)"
fi

echo ""

# Бэкап документации .md из DOCS/
echo "📝 Бэкап документации..."
if [ -f "DOCS/HANDOFF-NEXT-SESSION.md" ]; then
    cp DOCS/HANDOFF-NEXT-SESSION.md "BAK/$TODAY/HANDOFF-NEXT-SESSION_V#_${TIMESTAMP}.bak"
    echo "  ✓ DOCS/HANDOFF-NEXT-SESSION.md"
fi

if [ -f "DOCS/CHANGELOG.md" ]; then
    cp DOCS/CHANGELOG.md "BAK/$TODAY/CHANGELOG_V#_${TIMESTAMP}.bak"
    echo "  ✓ DOCS/CHANGELOG.md"
fi

if [ -f "DOCS/future_features/development_roadmap.md" ]; then
    cp DOCS/future_features/development_roadmap.md "BAK/$TODAY/development_roadmap_V#_${TIMESTAMP}.bak"
    echo "  ✓ DOCS/development_roadmap.md"
fi

# Бэкап Summary файлов за сегодня из DOCS/
SUMMARY_COUNT=$(ls DOCS/Summary_${TODAY}_*.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$SUMMARY_COUNT" -gt 0 ]; then
    cp DOCS/Summary_${TODAY}_*.md "BAK/$TODAY/" 2>/dev/null
    echo "  ✓ DOCS/Summary_${TODAY}_*.md ($SUMMARY_COUNT файл(ов))"
fi

echo ""
echo "========================================="
echo "✅ Бэкапы созданы в BAK/$TODAY/"
echo "========================================="
echo ""
echo "⚠️  ВАЖНО: Замените V# на правильные номера версий!"
echo "    Посмотрите последние версии в BAK/ и используйте следующий номер."
echo ""
echo "Содержимое BAK/$TODAY/:"
ls -1 "BAK/$TODAY/" | head -20
echo ""
