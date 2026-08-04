#!/bin/bash
# Лаборатория преданного — первый запуск (двойной клик на Mac)
cd "$(dirname "$0")"
clear
echo "═══════════════════════════════════════════════"
echo "   🙏  ЛАБОРАТОРИЯ — подготовка"
echo "       Цифровая библиотека и портал"
echo "═══════════════════════════════════════════════"
echo ""

# 1. Проверка Claude Code
if command -v claude >/dev/null 2>&1; then
  echo "✅ Claude Code найден: $(claude --version 2>/dev/null | head -1)"
else
  echo "⚠️  Claude Code не найден."
  echo "   1) Установите приложение: https://claude.com/claude-code"
  echo "   2) Войдите в аккаунт"
  echo "   3) Запустите этот файл ещё раз"
  open "https://claude.com/claude-code" 2>/dev/null
  echo ""
  read -p "Нажмите Enter, чтобы закрыть..." _
  exit 0
fi

# 2. Локальная память лаборатории (git — тихо, без вопросов)
if [ ! -d .git ]; then
  git init -q 2>/dev/null && git add -A 2>/dev/null && git commit -qm "Лаборатория: первый день" 2>/dev/null
  echo "✅ Память лаборатории включена (история изменений будет сохраняться)"
fi

mkdir -p INBOX notes work/library work/portal work/infra work/content
# --- Личные настройки владельца ---
# Живут в config/lab.local.yaml (вне git — обновления их НЕ трогают).
# Если это первый запуск после обновления, а настройки уже были в config/lab.yaml —
# переносим их автоматически, чтобы ничего не потерялось.
if [ ! -f config/lab.local.yaml ]; then
  if [ -f config/lab.yaml ] && grep -qE '^[a-z_]+: *"[^"]+"' config/lab.yaml; then
    cp config/lab.yaml config/lab.local.yaml
    echo "✅ Ваши прежние настройки перенесены в config/lab.local.yaml (обновления их не затрут)"
  elif [ -f config/lab.yaml.example ]; then
    cp config/lab.yaml.example config/lab.local.yaml
    echo "✅ Создан config/lab.local.yaml — сюда помощник запишет ваши настройки"
  fi
fi
echo "✅ Папки готовы: INBOX (входящие), notes (дневник), work (работа по направлениям)"
echo ""
echo "───────────────────────────────────────────────"
echo " Открываю первый разговор. Помощник представится"
echo " и задаст несколько вопросов. 🙏"
echo "───────────────────────────────────────────────"
echo ""
sleep 1

# 3. Старт Claude в папке лаборатории
exec claude
