Vagrant.configure(2) do |config|
  config.vm.box = "LukeCarrier/windows-2012-r2-64"

  hostname = "php56.local"

  config.vm.provision "shell", path: "bootstrap.ps1"
  config.vm.provision "reload"
  config.vm.provision "dsc" do |dsc|
    dsc.module_path = ["modules"]
    dsc.manifests_path = "manifests"

    dsc.configuration_file = "Php56Build.ps1"
    dsc.configuration_data_file = "manifests/Php56Build.psd1"
  end
end
