Vagrant.configure(2) do |config|
  config.vm.box = "LukeCarrier/windows_2016_x64_standard-core"

  config.vm.provision "shell", path: "bootstrap.ps1"
  config.vm.provision "reload"

  config.vm.define "php56" do |php56|
    php56.vm.hostname = "php56"

    php56.vm.provision "dsc" do |dsc|
      dsc.module_path = ["modules"]
      dsc.manifests_path = "manifests"

      dsc.configuration_file = "Php56Build.ps1"
      dsc.configuration_data_file = "manifests/PhpBuild.psd1"
    end
  end

  config.vm.define "php70" do |php70|
    php70.vm.hostname = "php70"

    php70.vm.provision "dsc" do |dsc|
      dsc.module_path = ["modules"]
      dsc.manifests_path = "manifests"

      dsc.configuration_file = "Php70Build.ps1"
      dsc.configuration_data_file = "manifests/PhpBuild.psd1"
    end
  end
end
