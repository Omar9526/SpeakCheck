#!/usr/bin/env bash
# Первичная настройка VPS (Ubuntu 22.04/24.04). Запуск один раз: sudo bash server-setup.sh <пользователь>
set -euo pipefail
USER_NAME="${1:?укажите пользователя: sudo bash server-setup.sh omar2}"

echo "== 1/5 Обновления системы"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get upgrade -yq
apt-get install -yq ca-certificates curl ufw fail2ban unattended-upgrades

echo "== 2/5 Docker"
if ! command -v docker >/dev/null; then curl -fsSL https://get.docker.com | sh; fi
usermod -aG docker "$USER_NAME"
systemctl enable --now docker

echo "== 3/5 Фаервол: открыты только SSH, HTTP, HTTPS"
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "== 4/5 SSH: вход только по ключу, root закрыт"
if [ ! -s "/home/$USER_NAME/.ssh/authorized_keys" ]; then
  echo "!! У $USER_NAME нет SSH-ключа — пароль НЕ отключаю"; exit 1
fi
cat > /etc/ssh/sshd_config.d/00-hardening.conf <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
CONF
sshd -t
systemctl reload ssh

echo "== 5/5 Защита от перебора паролей и автообновления безопасности"
systemctl enable --now fail2ban
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "ГОТОВО. Теперь смените пароль командой: passwd"
