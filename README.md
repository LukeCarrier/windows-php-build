# PHP for Windows

Reliable, reproducible builds of PHP for Windows.

* * *

## Testing

For the time being, we're doing this manually via
[Vagrant](https://www.vagrantup.com/).

```
$ vagrant plugin install vagrant-dsc
$ vagrant plugin install vagrant-reload

$ vagrant up --no-provision
# Configure region and language options, allow machine to reboot
$ vagrant reload

$ vagrant rdp
# Install guest additions
$ vagrant reload

$ vagrant provision
```
