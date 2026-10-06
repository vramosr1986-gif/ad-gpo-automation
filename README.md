# ad-gpo-automation

Laboratorio para automatizar Active Directory y GPOs con Ansible (`microsoft.ad`, `ansible.windows`) y PowerShell.
Aquí voy contando paso a paso cómo he montado todo.

## Arquitectura objetivo

![Arquitectura: Identity Lifecycle as Code](docs/img/arquitectura-identidad.svg)

El objetivo no es un alta masiva desde CSV, sino gestionar el **ciclo de vida completo de las identidades** (altas, cambios y bajas) como código:

- **Fuente de verdad en Git:** los cambios entran por Pull Request revisada por el responsable del área (CODEOWNERS), con separación entre quien solicita y quien aprueba.
- **Validación en CI antes de tocar el AD:** esquema de datos, reglas de segregación de funciones (SoD), `ansible-lint` y tests contra un DC efímero.
- **Ejecución segura:** plan con `--check --diff`, *circuit breaker* que aborta si un cambio afecta a demasiados objetos, backup previo y aplicación por lotes a través de un endpoint JEA con mínimo privilegio.
- **Operación:** secretos en Vault, logs y métricas en Grafana, informe por correo, cierre del ticket y procedimientos de recuperación probados.


## Hoja de ruta

**Montaje del entorno** (sección [Cómo he montado el entorno](#cómo-he-montado-el-entorno))

- [x] Paso 1 — Herramientas en el host
- [x] Paso 2 — Repositorio Git y estructura del proyecto
- [x] Paso 3 — Primera VM: DC01 con Vagrant
- [x] Paso 4 — Nodo de control Ansible en WSL y primer `win_ping`
- [x] Paso 5 — Inventario y credenciales cifradas con Ansible Vault
- [ ] Paso 6 — Promoción de DC01 a controlador de dominio (`lab.local`) con Ansible
- [ ] Paso 7 — DC02 (dominio hijo) y SRV01 (servidor miembro)

**Fases de automatización** (cuando el entorno esté listo)

- [ ] Fase 1 — Identity Lifecycle as Code: altas, cambios y bajas
- [ ] Fase 2 — GPO como código, backup y rollback
- [ ] Fase 3 — AWX como orquestador
- [ ] Fase 4 — Parcheo orquestado por oleadas
- [ ] Fase 5 — Monitorización y Event-Driven Ansible (*self-healing*)
- [ ] Fase 6 — Ticketing (GLPI) y notificaciones por correo

## Cómo he montado el entorno

### Paso 1 — Herramientas en el host

**Mi equipo:** Windows 11 Home, i7-13700HX, 32 GB de RAM, con WSL2 (Ubuntu 24.04) ya funcionando.

Windows 11 Home no trae Hyper-V Manager, así que las VMs del lab las monto con **VirtualBox** y las defino con **Vagrant**, para poder recrearlas cuando quiera. Además he instalado **Docker Desktop** (usa WSL2 como backend) y **Git**.

Instalé todo con `winget` desde una PowerShell como administrador:

```powershell
winget install -e --id Oracle.VirtualBox --accept-package-agreements --accept-source-agreements
winget install -e --id Hashicorp.Vagrant
winget install -e --id Docker.DockerDesktop
winget install -e --id Git.Git
```

Versiones instaladas (octubre 2026):

| Herramienta | Versión |
|---|---|
| VirtualBox | 7.2.20 (winget instaló también la dependencia Microsoft.VCRedist.2015+.x64) |
| Vagrant | 2.4.9 |
| Docker Desktop | 4.94.0 (Docker Engine 29.8.2) |
| Git | 2.55.0.windows.3 |
| WSL | Ubuntu-24.04, versión 2 |

Como ya tenía WSL2, Hyper-V está activo. Para que VirtualBox funcione encima de él, activé Windows Hypervisor Platform:

```powershell
dism /online /enable-feature /featurename:HypervisorPlatform /all /norestart
dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```

Las dos órdenes terminaron con *"La operación se completó correctamente"*. Después **reinicié** el equipo (con `/norestart` no se aplican hasta reiniciar).

Lo comprobé también de forma gráfica: **Windows + R → `optionalfeatures`**. En la lista aparecen marcadas:

- [x] Plataforma de máquina virtual
- [x] Plataforma del hipervisor de Windows

O desde PowerShell como administrador:

```powershell
Get-WindowsOptionalFeature -Online |
  Where-Object FeatureName -in 'HypervisorPlatform','VirtualMachinePlatform' |
  Select-Object FeatureName, State
```

Las dos deben salir en estado `Enabled`.

Para comprobar que todo estaba bien instalado, preparé un script que muestra todas las versiones de una vez ([`scripts/Test-LabTools.ps1`](scripts/Test-LabTools.ps1)):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Test-LabTools.ps1
```

![Versiones de las herramientas del lab](docs/img/01-herramientas-host.png)

También se puede comprobar herramienta por herramienta:

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" --version
vagrant --version
docker --version
git --version
wsl -l -v
```

Notas de este paso:

- **Docker Desktop:** lo abrí una vez para aceptar la licencia y activé *Settings → Resources → WSL Integration → Ubuntu-24.04*.
- **VirtualBox con Hyper-V:** funciona, pero algo más lento. Sale una tortuga verde en la barra de estado de las VMs; es normal.
- **Si falla la instalación de VirtualBox por Visual C++:** `winget install -e --id Microsoft.VCRedist.2015+.x64` y volver a instalar.
- **Si no se reconoce `vagrant` o `docker`:** me pasó con `docker` ("El término 'docker' no se reconoce..."). Docker estaba bien instalado y su ruta (`C:\Program Files\Docker\Docker\resources\bin`) ya estaba en el PATH del sistema, pero la terminal se había abierto antes de la instalación. Se arregla cerrando y abriendo la terminal, o recargando el PATH en la misma sesión:

  ```powershell
  $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
  ```

### Paso 2 — Repositorio Git y estructura del proyecto

Creé las carpetas del proyecto (vacías por ahora, con un `.gitkeep` para que Git las guarde) e inicialicé el repositorio:

```powershell
git init -b main
git add -A
git commit -m "Paso 1 y 2: herramientas del host y estructura del proyecto"
```

Añadí dos ficheros de configuración:

- **`.gitignore`:** deja fuera la carpeta `.vagrant/` de las VMs, las contraseñas del vault de Ansible (`.vault_pass*`) y el entorno virtual de Python (`.venv/`). **Las credenciales nunca se suben al repo.**
- **`.gitattributes`:** los ficheros de Ansible (YAML) usan finales de línea LF, porque Ansible se ejecuta desde WSL (Linux), y los scripts de PowerShell usan CRLF.

### Paso 3 — Primera VM: DC01 con Vagrant

**Imagen base.** Vagrant no instala Windows desde una ISO: usa una *box*, una VM ya instalada y preparada. Uso la de Windows Server 2022 Standard (evaluación) de `gusztavvargadr`, que trae WinRM habilitado y el usuario `vagrant`/`vagrant`:

```powershell
vagrant box add gusztavvargadr/windows-server-2022-standard --provider virtualbox
vagrant box list
```

**Vagrantfile.** Define la VM DC01 con IP fija en una red privada del lab:

```ruby
Vagrant.configure("2") do |config|
  config.vm.box          = "gusztavvargadr/windows-server-2022-standard"
  config.vm.box_version  = "2607.0.0"        # versión fija: lab reproducible
  config.vm.communicator = "winrm"
  config.winrm.transport = :negotiate        # NTLM: sigue funcionando tras promover a DC
  config.vm.boot_timeout = 900
  config.vm.synced_folder ".", "/vagrant", disabled: true

  config.vm.define "DC01" do |dc|
    dc.vm.hostname = "DC01"
    dc.vm.network "private_network", ip: "192.168.56.10"
    dc.vm.provider "virtualbox" do |vb|
      vb.name         = "lab-DC01"
      vb.memory       = 4096
      vb.cpus         = 1                    # ver problema 2
      vb.gui          = true
      vb.linked_clone = true
    end
  end
end
```

Decisiones:

- **`transport = :negotiate`:** la autenticación *basic* solo funciona con cuentas locales. Al promover la VM a controlador de dominio desaparecen las cuentas locales y Vagrant dejaría de poder conectarse.
- **`private_network`:** además de la NIC NAT que crea Vagrant (salida a Internet), una segunda NIC *host-only* con IP fija `192.168.56.10`. Esa es la red del lab, por la que entrará Ansible.
- **`linked_clone`:** la box se importa una sola vez como VM maestra y cada VM usa un disco diferencial. Ahorra disco y tiempo al crear DC02 y SRV01.

Para crearla:

```powershell
vagrant validate
vagrant up DC01
```

#### Problemas que me encontré

**1. Errores de sintaxis en el Vagrantfile.** `vagrant validate` los detecta antes de crear nada:

- `syntax error, unexpected ':'` → había un punto en lugar de una coma: `"/vagrant". disabled:` en vez de `"/vagrant", disabled:`.
- `The following settings shouldn't exist: boot, synced, version, linked` → había escrito `boot.timeout` en lugar de `boot_timeout` (y lo mismo con `synced_folder`, `box_version` y `linked_clone`). Para Vagrant el punto separa niveles de configuración; el guion bajo forma parte del nombre.

**2. La VM se quedaba en negro y `vagrant up` acababa con `Timed out while waiting for the machine to boot`.**

La ventana de la VM no mostraba nada, ni siquiera el logo. El log de VirtualBox (`%USERPROFILE%\VirtualBox VMs\lab-DC01\Logs\VBox.log`) mostraba la causa:

```
HM: HMR3Init: Attempting fall back to NEM: VT-x is not available
...
EFI: debug point DXE_AP
EFI: VBoxDbg> loadimage64 'PciHostBridgeDxe.efi' ...
```

- Como Hyper-V está activo (por WSL2 y Docker), VirtualBox no puede usar VT-x directamente y funciona **a través de Hyper-V (NEM)**: es la tortuga verde de la barra de estado.
- El firmware UEFI de la VM se colgaba al inicializar la **segunda CPU virtual** (`DXE_AP`) y no pasaba de `PciHostBridgeDxe.efi`, aunque la VM estuviera horas encendida.

**Solución:** `vb.cpus = 1`. Con una sola vCPU el firmware arranca, Windows carga en menos de un minuto y Vagrant conecta por WinRM:

```powershell
vagrant halt DC01 --force   # apagado forzado: Windows ni había arrancado
vagrant up DC01
```

### Paso 4 — Nodo de control Ansible en WSL y primer contacto con DC01

Ansible no funciona de forma nativa en Windows, así que el nodo de control es mi Ubuntu 24.04 de WSL. Desde WSL el repo está en `/mnt/c/Users/vramo/ad-gpo-automation`.

**Comprobación de red.** Antes de instalar nada, verifiqué que WinRM de DC01 responde por la red del lab, primero desde Windows y luego desde WSL:

```powershell
Test-NetConnection 192.168.56.10 -Port 5985   # TcpTestSucceeded : True
```

```bash
nc -zv 192.168.56.10 5985
```

**Instalación en un entorno virtual de Python.** Así Ansible no se mezcla con los paquetes del sistema (Ubuntu 24.04 ya bloquea `pip install` en el Python del sistema):

```bash
sudo apt update && sudo apt install -y python3-venv python3-pip
python3 -m venv ~/.venvs/ansible
source ~/.venvs/ansible/bin/activate          # el prompt muestra (ansible)
pip install ansible pywinrm
ansible-galaxy collection install ansible.windows microsoft.ad community.windows
```

Cada vez que abro una terminal nueva activo el entorno con `source ~/.venvs/ansible/bin/activate` (y `deactivate` para salir).

**Primer `win_ping`.** Una prueba ad-hoc, todavía sin inventario, pasando la conexión como variables:

```bash
ansible all -i '192.168.56.10,' -m ansible.windows.win_ping \
  -e ansible_connection=winrm \
  -e ansible_port=5985 \
  -e ansible_winrm_transport=ntlm \
  -e ansible_winrm_server_cert_validation=ignore \
  -e ansible_user=vagrant \
  -e ansible_password=vagrant
```

```
192.168.56.10 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

La cadena completa funciona: WSL → red host-only de VirtualBox → WinRM → Windows Server. La coma de `-i '192.168.56.10,'` es necesaria: le dice a Ansible que es una lista de hosts y no la ruta a un fichero de inventario.

> Pasar la contraseña por la línea de comandos solo vale para esta prueba: queda en el historial de la shell. En el siguiente paso la conexión pasa a un inventario y la contraseña a Ansible Vault.

### Paso 5 — Inventario y credenciales cifradas con Ansible Vault

Pasar IP, usuario y contraseña en cada comando es incómodo, no escala y deja la contraseña en el historial de la shell. Lo sustituí por la estructura estándar de Ansible:

```
ansible.cfg                                 # valores por defecto del proyecto
inventories/lab/
├── hosts.yml                               # QUÉ máquinas hay y en qué grupos
└── group_vars/windows/
    ├── vars.yml                            # CÓMO conectarse (en claro)
    └── vault.yml                           # la contraseña (cifrada, AES-256)
```

**Inventario** (`inventories/lab/hosts.yml`):

```yaml
all:
  children:
    windows:
      children:
        domain_controllers:
          hosts:
            DC01:
              ansible_host: 192.168.56.10
```

DC01 está en `domain_controllers`, que está dentro de `windows`. Los grupos se heredan, así que DC01 recibe las variables de `group_vars/windows/`, y cualquier servidor que añada después al grupo `windows` también.

**Variables de conexión** (`inventories/lab/group_vars/windows/vars.yml`):

```yaml
ansible_connection: winrm
ansible_port: 5985
ansible_winrm_transport: ntlm
ansible_winrm_server_cert_validation: ignore
ansible_user: vagrant
ansible_password: "{{ vault_windows_password }}"
```

`ansible_password` no contiene la contraseña: es una referencia a una variable definida en el vault. Separar `vars.yml` (en claro) y `vault.yml` (cifrado) permite ver qué variables existen sin descifrar nada, y el prefijo `vault_` indica de dónde viene cada una.

**Vault.** La clave que descifra el vault se genera aleatoriamente y vive **fuera del repo**, en mi home de Linux, con permisos solo para mi usuario:

```bash
mkdir -p ~/.ansible
openssl rand -base64 32 > ~/.ansible/lab-vault-pass
chmod 600 ~/.ansible/lab-vault-pass

ansible-vault create --vault-password-file ~/.ansible/lab-vault-pass \
  inventories/lab/group_vars/windows/vault.yml
# contenido: vault_windows_password: <contraseña>
```

En el repo solo queda el fichero cifrado, que empieza por `$ANSIBLE_VAULT;1.1;AES256`. Para consultarlo o cambiarlo: `ansible-vault view` / `ansible-vault edit`.

**Configuración del proyecto** (`ansible.cfg`, en la raíz del repo):

```ini
[defaults]
inventory = inventories/lab/hosts.yml
vault_password_file = ~/.ansible/lab-vault-pass
host_key_checking = False
retry_files_enabled = False
interpreter_python = auto_silent
```

**Resultado.** El mismo `win_ping` del paso anterior, ahora sin IP, usuario ni contraseña en la línea de comandos:

```bash
ansible --version | grep "config file"     # config file = .../ad-gpo-automation/ansible.cfg
ansible windows -m ansible.windows.win_ping
```

```
DC01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

#### Problemas que me encontré

**Ansible ignora el `ansible.cfg` en `/mnt/c`.** Por defecto WSL monta las unidades de Windows con permisos 777, y Ansible no lee un `ansible.cfg` en una carpeta en la que cualquiera puede escribir (sería una vía para inyectar configuración). Se corrige en `/etc/wsl.conf`, y después `wsl --shutdown` desde PowerShell:

```ini
[automount]
options = "metadata,umask=22,fmask=11"
```

**`No inventory was parsed ... Could not match supplied host pattern: windows`.** Ansible no encontraba el inventario porque el `ansible.cfg` aún no existía. `ansible --version | grep "config file"` muestra qué fichero de configuración está usando (o `None`).

## Estructura del proyecto

Esta es la estructura prevista. Las carpetas ya existen y se irán llenando en los siguientes pasos.

```
ad-gpo-automation/
├── inventories/lab/        # hosts.yml + group_vars (vault para credenciales)
├── roles/
│   ├── ad_forest/          # promoción de DCs (microsoft.ad.domain, domain_child)
│   ├── ad_ou/              # árbol de OUs declarativo desde YAML
│   ├── ad_users_groups/    # ciclo de vida de identidades: altas, cambios y bajas
│   ├── gpo_management/     # New-GPO, Set-GPRegistryValue, New-GPLink vía win_powershell
│   └── ad_backup_rollback/ # Backup-GPO/Restore-GPO, AD Recycle Bin, snapshots
├── playbooks/              # site.yml, provision_users.yml, rollback.yml...
├── scripts/                # módulos PowerShell propios
├── data/users.csv
├── tests/                  # Pester + validaciones con ldap_search
└── docs/
```
