#!/usr/bin/env bash
# Prepara WSL como nodo de control de Ansible para el lab. Idempotente: lo que ya
# está instalado o configurado no se toca. Lo llama scripts/Deploy-Lab.ps1, y
# también se puede lanzar a mano:  bash scripts/setup-wsl.sh
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
venv="$HOME/.venvs/ansible"
vault_key="$HOME/.ansible/lab-vault-pass"
vault_windows="$repo/inventories/lab/group_vars/windows/vault.yml"
vault_dc="$repo/inventories/lab/group_vars/domain_controllers/vault.yml"
# La clave se pasa por variable de entorno, no con --vault-password-file: si además la
# define el ansible.cfg del repo, ansible-vault ve dos claves y no sabe con cuál cifrar.
export ANSIBLE_VAULT_PASSWORD_FILE="$vault_key"

paso() { printf '\n=== %s ===\n' "$1"; }

# Pide una contraseña sin mostrarla y escribe la línea YAML "variable: 'valor'".
# $1 variable, $2 para qué es, $3 valor por defecto (opcional)
pedir() {
  local valor
  while true; do
    read -rsp "  $2${3:+ (Enter = la de la box: $3)}: " valor; echo >&2
    valor="${valor:-${3:-}}"
    [ -n "$valor" ] && break
    echo "  No puede quedar vacía." >&2
  done
  printf "%s: '%s'\n" "$1" "${valor//\'/\'\'}"
}

paso "1/4 Paquetes del sistema (python3-venv)"
if [ -x "$venv/bin/python" ]; then
  echo "OK: el entorno $venv ya existe"
else
  sudo apt-get update -qq
  sudo apt-get install -y -qq python3-venv python3-pip
  python3 -m venv "$venv"
  echo "Creado el entorno $venv"
fi

paso "2/4 Ansible y pywinrm (requirements.txt)"
# shellcheck disable=SC1091
source "$venv/bin/activate"
pip install -q --disable-pip-version-check -r "$repo/requirements.txt"
ansible --version | head -1

paso "3/4 Colecciones de Ansible (collections/requirements.yml)"
ansible-galaxy collection install -r "$repo/collections/requirements.yml"

paso "4/4 Clave del vault y contraseñas del lab"
if [ -f "$vault_key" ]; then
  # La clave existe: comprobar que abre los dos vault del repo
  for f in "$vault_windows" "$vault_dc"; do
    if ! ansible-vault view "$f" >/dev/null 2>&1; then
      echo "ERROR: $vault_key no descifra ${f#"$repo"/}." >&2
      echo "Es otra clave. Recupera la correcta o borra la tuya y vuelve a lanzar este script para crear vaults nuevos." >&2
      exit 1
    fi
  done
  echo "OK: $vault_key descifra los dos vault"
else
  # Sin clave: los vault del repo están cifrados con la del autor y no sirven.
  # Se crea una clave nueva y se escriben vaults nuevos con contraseñas propias.
  echo "No hay clave del vault en $vault_key: se crea una nueva y vaults nuevos."
  echo "Las de DSRM y usuarios de prueba deben cumplir la complejidad de Windows"
  echo "(8 caracteres o más, con mayúsculas, minúsculas, números y símbolos)."
  mkdir -p "$(dirname "$vault_key")"
  umask 077
  openssl rand -base64 32 > "$vault_key"
  chmod 600 "$vault_key"

  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  {
    echo "# Cuenta vagrant: conexión WinRM de Ansible, Enterprise Admin del bosque, une SRV01"
    pedir vault_windows_password "Contraseña de la cuenta vagrant de las VMs" vagrant
    echo "# Cuentas de servicio pendientes de crear (svc_join, svc_ansible): valores aleatorios"
    echo "vault_svc_join_password: '$(openssl rand -base64 18)'"
    echo "vault_svc_ansible_password: '$(openssl rand -base64 18)'"
  } > "$tmp"
  ansible-vault encrypt --output "$vault_windows" "$tmp"

  {
    echo "# Administrator local de cada DC en modo DSRM (recuperación sin AD)"
    pedir vault_ad_dsrm_password "Contraseña de DSRM de los DC"
    echo "# Contraseña inicial de los usuarios de prueba de data/usuarios.yml"
    pedir vault_ad_test_user_password "Contraseña inicial de los usuarios de prueba"
  } > "$tmp"
  ansible-vault encrypt --output "$vault_dc" "$tmp"

  echo "Creados ${vault_windows#"$repo"/} y ${vault_dc#"$repo"/}, cifrados con $vault_key."
  echo "Guarda una copia de $vault_key en tu gestor de contraseñas: sin ella no se pueden abrir."
fi
