Vagrant.configure("2") do |config|
config.vm.box = "gusztavvargadr/windows-server-2022-standard"
config.vm.box_version = "2607.0.0"
config.vm.communicator ="winrm"
config.winrm.transport = :negotiate
config.vm.boot_timeout = 900
config.vm.synced_folder ".", "/vagrant", disabled: true

config.vm.define "DC01" do |dc|
  dc.vm.hostname="DC01"
  dc.vm.network "private_network", ip: "192.168.56.10"
  dc.vm.provider "virtualbox" do |vb|
    vb.name ="lab-DC01"
    vb.memory = 4096
    vb.cpus = 1
    vb.gui = true
    vb.linked_clone = true
    end
  end
end