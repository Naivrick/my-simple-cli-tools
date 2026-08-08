#!/bin/bash

# ==============================================================================
# vboxctl.sh - Интерактивный CLI-менеджер для VirtualBox
# ==============================================================================

CONFIG_FILE="$HOME/.config/vbox_control.conf"
TIMEOUT=60  # Время ожидания мягкого выключения (в секундах)

# Проверка наличия vboxmanage
if ! command -v vboxmanage &> /dev/null; then
  echo "Ошибка: vboxmanage не установлен или не добавлен в PATH."
  exit 1
fi

# Вспомогательные функции конфига
get_default_vm() {
  if [ -f "$CONFIG_FILE" ]; then
    cat "$CONFIG_FILE"
  fi
}

set_default_vm() {
  local vm_name="$1"
  mkdir -p "$(dirname "$CONFIG_FILE")"
  echo "$vm_name" > "$CONFIG_FILE"
  echo "ВМ '$vm_name' установлена по умолчанию."
}

# Вспомогательные функции VirtualBox
get_vm_state() {
  local vm_name="$1"
  vboxmanage showvminfo "$vm_name" --machinereadable 2>/dev/null | grep "^VMState=" | cut -d'=' -f2 | tr -d '"' | xargs
}

get_all_vms() {
  vboxmanage list vms | sed -E 's/.*"([^"]+)".*/\1/'
}

get_running_vms() {
  vboxmanage list runningvms | sed -E 's/.*"([^"]+)".*/\1/'
}

# Логика выключения ВМ с таймаутом
poweroff_vm() {
  local vm_name="$1"
  local state
  state=$(get_vm_state "$vm_name")

  if [ "$state" = "poweroff" ] || [ -z "$state" ]; then
    echo "Машина '$vm_name' уже выключена."
    return 0
  fi

  echo "Выключение машины '$vm_name'..."
  vboxmanage controlvm "$vm_name" acpipowerbutton 2>/dev/null

  local elapsed=0
  while [ $elapsed -lt $TIMEOUT ]; do
    state=$(get_vm_state "$vm_name")
    if [ "$state" = "poweroff" ]; then
      echo "Машина '$vm_name' успешно выключена."
      return 0
    fi
    echo "  [$vm_name] Статус: $state, ожидание... ($elapsed/$TIMEOUT сек)"
    sleep 2
    elapsed=$((elapsed + 2))
  done

  echo "Внимание: машина '$vm_name' не выключилась за $TIMEOUT секунд."
  echo "Принудительное выключение..."
  vboxmanage controlvm "$vm_name" poweroff
}

# ОБРАБОТКА АРГУМЕНТОВ КОМАНДНОЙ СТРОКИ
if [ "$1" = "on" ]; then
  DEFAULT_VM=$(get_default_vm)
  if [ -z "$DEFAULT_VM" ]; then
    echo "Ошибка: ВМ по умолчанию не задана."
    echo "Запустите скрипт без параметров, выберите ВМ и установите её по умолчанию."
    exit 1
  fi
  echo "Запуск ВМ по умолчанию: $DEFAULT_VM..."
  vboxmanage startvm "$DEFAULT_VM" --type headless
  exit $?
fi

if [ "$1" = "off" ]; then
  RUNNING_VMS=$(get_running_vms)
  if [ -z "$RUNNING_VMS" ]; then
    echo "Запущенных машин не найдено."
    exit 0
  fi

  echo "Отключение всех запущенных виртуальных машин..."
  while IFS= read -r vm; do
    [ -n "$vm" ] && poweroff_vm "$vm"
  done <<< "$RUNNING_VMS"
  exit 0
fi

if [ -n "$1" ]; then
  echo "Ошибка: неверный аргумент '$1'"
  echo "Использование: $0 [on|off]"
  exit 1
fi

# ИНТЕРАКТИВНЫЙ ИНТЕРФЕЙС

# Функция меню с чисткой экрана на каждой итерации
select_option() {
  local prompt="$1"
  local header_func="$2"  # Кастомный заголовок (например, с информацией о ВМ)
  shift 2
  local options=("$@")
  local cur=0
  local count=${#options[@]}
  local key

  trap 'tput cnorm; clear; exit' INT TERM
  tput civis

  while true; do
    clear
    
    # Отрисовка зафиксированного заголовка/инфо-блока, если передан
    if [ -n "$header_func" ] && declare -f "$header_func" > /dev/null; then
      "$header_func"
    fi

    echo -e "$prompt\n"
    for i in "${!options[@]}"; do
      if [ $i -eq $cur ]; then
        echo -e " \033[1;32m❯ ${options[$i]}\033[0m"
      else
        echo "   ${options[$i]}"
      fi
    done

    # Чтение клавиш
    read -rsn1 key
    if [[ $key == $'\x1b' ]]; then
      read -rsn2 key
      if [[ $key == '[A' ]]; then # Нажата стрелка ВВЕРХ
        cur=$(( (cur - 1 + count) % count ))
      elif [[ $key == '[B' ]]; then # Нажата стрелка ВНИЗ
        cur=$(( (cur + 1) % count ))
      fi
    elif [[ $key == "" ]]; then # Нажат ENTER
      tput cnorm
      clear
      return $cur
    fi
  done
}

# 1. Меню выбора ВМ
mapfile -t VM_LIST < <(get_all_vms)

if [ ${#VM_LIST[@]} -eq 0 ]; then
  echo "Виртуальные машины VirtualBox не найдены."
  exit 0
fi

DEFAULT_VM=$(get_default_vm)
MAIN_PROMPT="Выберите виртуальную машину (По умолчанию: ${DEFAULT_VM:-не задана}):"

select_option "$MAIN_PROMPT" "" "${VM_LIST[@]}"
SELECTED_VM="${VM_LIST[$?]}"

# 2. Вывод зафиксированной информации о выбранной ВМ
print_vm_info() {
  local state cpus ram
  state=$(get_vm_state "$SELECTED_VM")
  cpus=$(vboxmanage showvminfo "$SELECTED_VM" --machinereadable 2>/dev/null | grep "^cpus=" | cut -d'=' -f2)
  ram=$(vboxmanage showvminfo "$SELECTED_VM" --machinereadable 2>/dev/null | grep "^memory=" | cut -d'=' -f2)

  echo -e "========================================"
  echo -e " Информация о ВМ: \033[1;34m$SELECTED_VM\033[0m"
  echo -e "========================================"
  echo " Статус:   $state"
  echo " CPU:      $cpus core(s)"
  echo " RAM:      $ram MB"
  [ "$SELECTED_VM" = "$DEFAULT_VM" ] && echo " Дефолт:  Да"
  echo -e "========================================\n"
}

# 3. Меню действий
ACTIONS=(
  "Запустить (headless)"
  "Остановить (soft shutdown)"
  "Сделать по умолчанию"
  "Удалить машину"
  "Отмена"
)

select_option "Выберите действие для '$SELECTED_VM':" "print_vm_info" "${ACTIONS[@]}"
ACTION_INDEX=$?

case $ACTION_INDEX in
  0)
    echo "Запуск $SELECTED_VM..."
    vboxmanage startvm "$SELECTED_VM" --type headless
    ;;
  1)
    poweroff_vm "$SELECTED_VM"
    ;;
  2)
    set_default_vm "$SELECTED_VM"
    ;;
  3)
    read -p "Вы уверены, что хотите полностью удалить ВМ '$SELECTED_VM'? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      if [ "$(get_vm_state "$SELECTED_VM")" != "poweroff" ]; then
        echo "Остановка ВМ перед удалением..."
        vboxmanage controlvm "$SELECTED_VM" poweroff 2>/dev/null
        sleep 1
      fi
      echo "Удаление $SELECTED_VM..."
      vboxmanage unregistervm "$SELECTED_VM" --delete
      
      if [ "$SELECTED_VM" = "$DEFAULT_VM" ]; then
        rm -f "$CONFIG_FILE"
        echo "Сброшена настройка ВМ по умолчанию."
      fi
    else
      echo "Удаление отменено."
    fi
    ;;
  4)
    echo "Операция отменена."
    exit 0
    ;;
esac

exit 0
