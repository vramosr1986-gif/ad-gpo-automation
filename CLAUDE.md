# Instrucciones para Claude

## Cómo trabajamos
- Es un lab de aprendizaje: explica el porqué de cada paso, no solo el comando.
- No ejecutes playbooks ni cambies las VMs sin preguntar: los lanzo yo.
  Puedes leer ficheros y hacer --syntax-check.
- No hagas comprobaciones de más cuando te digo que algo está bien.
- Comandos para Windows siempre en PowerShell, nunca cmd (nada de ipconfig, nltest, nslookup).
- Paso a paso: un bloque de comandos, espero mi salida, y seguimos.

## Precisión al explicar
- Cuando hables de un fichero, di cuál con su ruta relativa al repositorio.
  Mal: "el fichero está cifrado". Bien: "inventories/lab/group_vars/domain_controllers/vault.yml está cifrado".
- Cuando hables del valor de una variable, di qué variable es y en qué fichero está definida.
  Mal: "la OU es Servidores". Bien: "ad_member_ou (inventories/lab/group_vars/member_servers/vars.yml) vale OU=Servidores,DC=lab,DC=local".
- Si el valor sale de otras variables, enseña la cadena hasta el valor final.
- Cuando pidas lago que requiera un comando pon el comando que necesito
## Ansible
- Todo idempotente: una segunda ejecución debe dar changed=0.
- Usa el módulo de la colección si existe; win_powershell solo si no hay módulo,
  con la comprobación previa y $Ansible.Changed.
- Un playbook que no cambia nada nunca reinicia un servidor.
- Secretos solo en el vault; no_log en tareas con contraseñas; no mostrar secretos en pantalla.
- Variables en group_vars, datos (usuarios, grupos) en data/.

## Entorno
- Ansible en WSL: source ~/.venvs/ansible/bin/activate, ANSIBLE_CONFIG=$PWD/ansible.cfg.
- Conexión a las VMs por la IP del lab (192.168.56.x), no por los puertos de Vagrant.
