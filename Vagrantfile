Vagrant.configure("2") do |config|
config.vm.box = "gusztavvargadr/windows-server-2022-standard"
config.vm.box_version = "2607.0.0"
config.vm.communicator ="winrm"
config.winrm.transport = :negotiate
config.vm.boot_timeout = 1800
config.vm.synced_folder ".", "/vagrant", disabled: true
config.vm.provision "lab-tuning", type: "shell", path: "scripts/Optimize-LabGuest.ps1"

# Proveedor principal: VMware Workstation (vagrant up --provider vmware_desktop).
# Con el hipervisor de Windows activo, VirtualBox cae al modo NEM "Snail" y es
# demasiado lento; VMware funciona bien sobre Hyper-V y admite varias CPUs.
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
    end
  dc.vm.provider "virtualbox" do |vb|
    vb.name ="lab-DC01"
    vb.memory = 4096
    vb.cpus = 1
    vb.gui = false
    vb.linked_clone = true
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
    end
  dc.vm.provider "virtualbox" do |vb|
    vb.name ="lab-DC02"
    vb.memory = 4096
    vb.cpus = 1
    vb.gui = false
    vb.linked_clone = true
    end
  end
end
