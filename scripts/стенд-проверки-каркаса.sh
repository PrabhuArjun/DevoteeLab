#!/usr/bin/env bash
# Стенд проверки каркаса — для КОМАНДЫ АРДЖУНЫ, не для владельца лаборатории.
# Владельцу запускать не нужно и не вредно: стенд ничего не меняет ни в каркасе,
# ни в его папке — он делает свои временные копии и удаляет их за собой.
#
# ЗАЧЕМ ОН ЕСТЬ. 03.09.2026 проверка №8 («номер версии обязан двигаться вместе с
# содержимым») прошла первый стенд из восьми случаев и была неверна по существу:
# встречная проверка шестью независимыми направлениями подтвердила 32 находки,
# сводящиеся к восьми корням. Проверка, которую никто не может уронить, — это
# документ о намерении, а не проверка. Поэтому случаи ниже живут рядом с ней.
#
# ПРАВИЛО ДЛЯ СЛЕДУЮЩЕЙ ПРАВКИ: меняешь проверку — сначала допиши сюда случай,
# который на ней КРАСНЕЕТ, и только потом чини. Красная проба до починки дороже
# зелёной после.
#
#   bash scripts/стенд-проверки-каркаса.sh    → 0 всё сошлось · 1 есть расхождения

set -u
SRC="$HOME/Projects/DevoteeLab"
CHK="$SRC/scripts/проверка-каркаса.sh"
BASE="${TMPDIR:-/tmp}/kit-check8.$$"
mkdir -p "$BASE"
PASS=0; FAILED=0
G="git -c user.email=t@t -c user.name=t"

# ⚠️ Клон берёт ЗАКОММИЧЕННОЕ. Проверяемый скрипт правится в рабочей папке и в клон
#    бы не попал — первая версия стенда так и проверила СТАРЫЙ скрипт и дала семь
#    ложных провалов. Поэтому скрипт вносится в клон и уходит в upstream вместе с
#    номером: тогда дерево чисто и «общий каркас» знает ровно то, что мы проверяем.
mk() { # mk <имя> [номер] → upstream.git + рабочий клон, дерево чистое, origin/main = HEAD
  local n="$1" v="${2:-2.0.0}"
  git clone -q --bare "$SRC" "$BASE/$n.git" 2>/dev/null
  git clone -q "$BASE/$n.git" "$BASE/$n" 2>/dev/null
  cp "$CHK" "$BASE/$n/scripts/проверка-каркаса.sh"
  ( cd "$BASE/$n" && echo "$v" > VERSION && $G add -A && $G commit -qm "версия $v" \
    && $G push -q origin HEAD:main )
}

t() { # t <ярлык> <ожидаемый код> <папка> [строка-которая-обязана-быть]
  local label="$1" want="$2" dir="$3" needle="${4:-}" got line="да"
  ( cd "$dir" && bash scripts/проверка-каркаса.sh ) >"$BASE/out.txt" 2>&1
  got=$?
  [ -n "$needle" ] && ! grep -qF "$needle" "$BASE/out.txt" && line="НЕТ"
  if [ "$got" = "$want" ] && [ "$line" = "да" ]; then
    printf '  ✅ %-52s код %s\n' "$label" "$got"; PASS=$((PASS+1))
  else
    printf '  🔴 %-52s код %s (ждали %s) · строка «%s»: %s\n' "$label" "$got" "$want" "$needle" "$line"
    grep -E '^  (✅|❌|❗|⚠️)|^(✅|❌|⚠️)' "$BASE/out.txt" | tail -4 | sed 's/^/        /'
    FAILED=$((FAILED+1))
  fi
}

echo "── ① КАСАНИЕ ≠ ДВИЖЕНИЕ НОМЕРА"
mk a; t "номер поднят, содержимое за ним не ушло → зелено" 0 "$BASE/a" "согласованы"

mk b
( cd "$BASE/b" && printf '\n<!-- глава -->\n' >> README.md && $G commit -qam "глава" \
  && $G push -q origin HEAD:main )
t "содержимое ушло вперёд номера → красно" 1 "$BASE/b" "стоит на месте"

mk c
( cd "$BASE/c" && printf '\n<!-- глава -->\n' >> README.md && echo "2.0.1" > VERSION \
  && $G commit -qam "глава + 2.0.1" && $G push -q origin HEAD:main \
  && echo "2.0.0" > VERSION && $G commit -qam "передумали выпускать" && $G push -q origin HEAD:main )
t "номер поехал НАЗАД → красно" 1 "$BASE/c" "поехал НАЗАД"

mk d
( cd "$BASE/d" && printf '\n<!-- глава -->\n' >> README.md && printf '2.0.0\n\n' > VERSION \
  && $G commit -qam "глава, номер прежний" && $G push -q origin HEAD:main )
t "VERSION тронут пустой строкой → красно" 1 "$BASE/d" "стоит на месте"

mk e; ( cd "$BASE/e" && : > VERSION )
t "VERSION пуст → НЕ зелено, код 2" 2 "$BASE/e" "файл VERSION пуст"

mk f; ( cd "$BASE/f" && echo "почти-версия" > VERSION )
t "в VERSION не номер → НЕ зелено, код 2" 2 "$BASE/f" "не номер"

echo
echo "── ② ИММУНИТЕТ ЗА КАСАНИЕ"
mk g; ( cd "$BASE/g" && printf '\n<!-- правка -->\n' >> README.md && echo "0.0.1" > VERSION )
t "правка + номер НАЗАД в папке → не гасит, замечание" 0 "$BASE/g" "номер при этом 0.0.1"

mk h; ( cd "$BASE/h" && printf '\n<!-- правка -->\n' >> README.md && echo "2.0.1" > VERSION )
t "правка + номер поднят в папке → замечание, не молчание" 0 "$BASE/h" "ещё не сохранён в историю"

echo
echo "── ③ НОВЫЕ ФАЙЛЫ"
mk i; ( cd "$BASE/i" && echo "новое" > docs/НОВОЕ.md )
t "новый файл каркаса виден (не «не менялся»)" 0 "$BASE/i" "docs/НОВОЕ.md"

mk j; ( cd "$BASE/j" && mkdir -p notes work/library && echo "дневник" > notes/2026-09-03.md \
        && echo "черновик" > work/library/x.md )
t "личное владельца НЕ считается правкой каркаса" 0 "$BASE/j" "согласованы"

echo
echo "── ④ ЧУЖОЙ РЕПОЗИТОРИЙ"
mkdir -p "$BASE/outer" && ( cd "$BASE/outer" && $G init -q && echo x > чужое.txt \
  && $G add -A && $G commit -qm outer )
mk k; cp -R "$BASE/k" "$BASE/outer/kit" && rm -rf "$BASE/outer/kit/.git"
t "каркас внутри чужого репозитория → код 2" 2 "$BASE/outer/kit" "ВНУТРИ другого репозитория"

echo
echo "── ⑤ НЕЗАВЕРШЁННОЕ СЛИЯНИЕ"
mk l
( cd "$BASE/l" && printf 'наше\n' >> README.md && $G commit -qam our \
  && $G push -q origin HEAD:main )
( cd "$BASE/l" && $G reset -q --hard HEAD~1 && printf 'чужое\n' >> README.md \
  && $G commit -qam their && $G fetch -q origin && $G merge -q origin/main >/dev/null 2>&1 )
t "слияние не завершено → код 2, а не зелёное" 2 "$BASE/l" "слияние не завершено"

echo
echo "── ⑥ АРХИВ, ПРИТВОРИВШИЙСЯ РЕПОЗИТОРИЕМ (git init из START_HERE)"
mk m; ( cd "$BASE/m" && $G remote remove origin )
t "истории нет связи с общим каркасом → код 2" 2 "$BASE/m" "нет связи с общим репозиторием"

echo
echo "── ⑦ и ⑧ ДВА ЧИТАТЕЛЯ: правки владельца НЕ ошибка сборки"
mk n; ( cd "$BASE/n" && cp coordinators/_template.md coordinators/мой.md \
        && $G add -A && $G commit -qm "свой координатор" )
t "свой координатор по инструкции → замечание, НЕ красное" 0 "$BASE/n" "своих правок сверх общего каркаса"

mk o; ( cd "$BASE/o" && printf '\n<!-- моя правка -->\n' >> ДОБРО_ПОЖАЛОВАТЬ.md )
t "правка владельца в папке → замечание, код 0" 0 "$BASE/o" "не ошибка сборки"

echo
echo "── ПРОЧЕЕ: обрезанная история, пропавшие файлы, читаемость русских имён"
mk p >/dev/null
git clone -q --depth 1 "file://$BASE/p.git" "$BASE/q" 2>/dev/null
cp "$CHK" "$BASE/q/scripts/проверка-каркаса.sh"
t "обрезанный клон → код 2" 2 "$BASE/q" "история обрезана"

mk r; ( cd "$BASE/r" && $G rm -q VERSION && $G commit -qm "убрать номер" )
t "нет файла VERSION → код 2" 2 "$BASE/r" "нет файла VERSION"

mk s; ( cd "$BASE/s" && $G rm -q config/lab.yaml.example && $G commit -qm "убрать схему" )
t "нет схемы настроек → ранний код 2, а не 8 из 8" 2 "$BASE/s" "проверять нечего"

mk u
( cd "$BASE/u" && printf '\n<!-- правка -->\n' >> "docs/АРХИТЕКТУРА.md" \
  && $G commit -qam arch && $G push -q origin HEAD:main )
t "русское имя файла печатается буквами" 1 "$BASE/u" "docs/АРХИТЕКТУРА.md"

echo
printf '  ИТОГ стенда: пройдено %s, провалено %s\n' "$PASS" "$FAILED"
rm -rf "$BASE"
[ "$FAILED" -eq 0 ]
