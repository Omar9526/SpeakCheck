#!/usr/bin/env bash
# Ежедневный бэкап PostgreSQL: ~/backups/speakcheck-ГГГГММДД-ЧЧММ.sql.gz, хранится 14 дней.
# Запуск по cron (crontab -l). Восстановление: gunzip -c ФАЙЛ | docker compose exec -T db psql -U speakcheck speakcheck
set -euo pipefail
cd "$(dirname "$0")"
DIR="$HOME/backups"
mkdir -p "$DIR" && chmod 700 "$DIR"
FILE="$DIR/speakcheck-$(date +%Y%m%d-%H%M).sql.gz"
docker compose exec -T db pg_dump -U speakcheck --no-owner speakcheck | gzip -9 > "$FILE.tmp"
mv "$FILE.tmp" "$FILE"
chmod 600 "$FILE"
find "$DIR" -name 'speakcheck-*.sql.gz' -mtime +14 -delete
echo "$(date -Is) ok $(du -h "$FILE" | cut -f1) $FILE"
