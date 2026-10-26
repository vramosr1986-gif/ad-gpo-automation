Vagrant.configure("2") do |config|
config.vm.box = "gusztavvargadr/windows-server-2022-standard"
config.vm.box_version = "2607.0.0"
config.vm.communicator ="winrm"
config.winrm.transport = :negotiate
config.vm.boot_timeout = 1800
# Windows se reinicia al cambiar el nombre: Vagrant reintenta WinRM ~5 min en vez de fallar a la primera
config.winrm.retry_limit = 30
config.winrm.retry_delay = 10
config.vm.synced_folder ".", "/vagrant", disabled: true
config.vm.provision "lab-tuning", type: "shell", path: "scripts/Optimize-LabGuest.ps1"

# Proveedor: VMware Workstation. Convive con el hipervisor de Windows (WSL2, Docker).
# VMware no configura private_network en invitados Windows: la IP fija la pone
# el provisioner "lab-ip".
config.vm.define "DC01" do |dc|
  dc.vm.hostname="DC01"
  dc.vm.network "private_network", ip: "192.168.56.10"
  dc.vm.provision "lab-ip", type: "shell", path: "scripts/Set-LabIP.ps1", args: ["-IPAddress", "192.168.56.10"]
  dc.vm.provider "vmware_desktop" do |vm|
    vm.vmx["displayName"] = "lab-DC01"
    vm.memory = 4096
    vm.cpus = 2
    vm.gui = false
    vm.linked_clone = true
    # IP de la NIC NAT por el DHCP de VMware, no por vmrun (que puede dar la del lab
    # y dejar los reenvíos de puertos apuntando a una red que la NAT no alcanza)
    vm.enable_vmrun_ip_lookup = false
    end
  end
config.vm.define "DC02" do |dc|
  # Server Core: sin escritorio, mas ligero
  dc.vm.box = "gusztavvargadr/windows-server-2022-standard-core"
  dc.vm.hostname="DC02"
  dc.vm.network "private_network", ip: "192.168.56.11"
  dc.vm.provision "lab-ip", type: "shell", path: "scripts/Set-LabIP.ps1", args: ["-IPAddress", "192.168.56.11"]
  dc.vm.provider "vmware_desktop" do |vm|
    vm.vmx["displayName"] = "lab-DC02"
    vm.memory = 4096
    vm.cpus = 2
    vm.gui = false
    vm.linked_clone = true
    # IP de la NIC NAT por el DHCP de VMware, no por vmrun (que puede dar la del lab
    # y dejar los reenvíos de puertos apuntando a una red que la NAT no alcanza)
    vm.enable_vmrun_ip_lookup = false
    end
  end
config.vm.define "SRV01" do |srv|
  srv.vm.box = "gusztavvargadr/windows-server-2022-standard-core"
  srv.vm.hostname = "SRV01"
  srv.vm.network "private_network", ip: "192.168.56.20"
  srv.vm.provision "lab-ip", type: "shell", path: "scripts/Set-LabIP.ps1", args: ["-IPAddress", "192.168.56.20"]
  srv.vm.provider "vmware_desktop" do |vm|
    vm.vmx["displayName"] = "lab-SRV01"
    vm.memory = 2048
    vm.cpus = 2
    vm.gui = false
    vm.linked_clone = true
    # IP de la NIC NAT por el DHCP de VMware, no por vmrun (que puede dar la del lab
    # y dejar los reenvíos de puertos apuntando a una red que la NAT no alcanza)
    vm.enable_vmrun_ip_lookup = false
  end
end
end
