#!/usr/bin/env bash
set -euo pipefail

# Настройки
DAY=2
MIN=0
MAX=9
PREFIX="ex"
FNAME_TEMPLATE="day%02d_ex%02d.sql"

# Проверка, что текущая папка — "src"
if [[ "$(basename "$PWD")" == "src" ]]; then
  BASE_DIR="."
else
  BASE_DIR="src"
fi

if ! [[ "$DAY" =~ ^[0-9]+$ ]] || ! [[ "$MIN" =~ ^[0-9]+$ ]] || ! [[ "$MAX" =~ ^[0-9]+$ ]]; then
  echo "Ошибка: DAY, MIN и MAX должны быть целыми числами." >&2
  exit 2
fi

if (( DAY < 0 )) || (( MIN < 0 )) || (( MAX < 0 )); then
  echo "Ошибка: DAY, MIN и MAX должны быть неотрицательными." >&2
  exit 3
fi

if (( MIN > MAX )); then
  echo "Ошибка: MIN не может быть больше MAX." >&2
  exit 4
fi

# Основной цикл
for ((n=MIN; n<=MAX; n++)); do
  idx=$(printf "%02d" "$n")
  dir="${BASE_DIR}/${PREFIX}${idx}"
  file="${dir}/$(printf "$FNAME_TEMPLATE" "$DAY" "$n")"

  if [[ -d "$dir" ]]; then
    echo "Папка уже существует: $dir"
  else
    mkdir -p "$dir"
    echo "Создана папка: $dir"
  fi

  if [[ -e "$file" ]]; then
    echo "Файл уже существует: $file"
  else
    touch "$file"
    echo "Создан файл: $file"
  fi
done
