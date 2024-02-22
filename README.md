# ochami-vm
This VM only runs on a linux host at the moment, specifically on a RHEL8 flavor of linux
## Prerequisites
These are required if you would like to run the ochami services in VM.  
The next few steps set up the environment for the VM to boot and run

### Install Packages
```bash
dnf install \ 
    podman \
    libvirt \
    grub2-efi-x64 \
    shim-x64 \
    qemu-kvm
```


### Create local service containers
You can skip these steps if you have an existing s3 and/or cloud-init instances running.

#### create dummy interface
We create a dummy interface to attach our local service containers to.
```bash
export DUMMY_IP=10.100.0.1
export DUMMY_MASK=24
./dummy-interface.sh
```

#### start minio
Start a local s3 instance using minio.  
You can change the minio user, passwd, and storage location
```bash
export MINIO_USER="admin"
export MINIO_PASSWD="admin123"
export MINIO_DIR="/data/minio"
./containers/minio/minio-start.sh
```

#### start simple cloud init server
Start a local cloud init instance.  
```bash
export CI_DATA="/data/cloud-init/"
./containers/simple-cloud-init/cloud-init-start.sh
```
You can add cloud-init configs to the `CI_DATA` directory and point to `http://$DUMMY_IP/cloud-init/` for the cloud-init clients.  
See examples in the `examples/cloud-init`

## VM booting
This VM uses libvirt and http to boot. 

### Build test image
The following steps will build a test image and push it to s3
```bash
source s3-utils/s3-setup.sh
./vm-images/build-test-image.sh
s3-list --bucket-name boot-images 
```
You should now have at least one image and kernel and initramfs

### Get EFI boot binaries
We are going to boot the VM via the network using grub.  
You'll need two things pushed to s3 to make this work: `BOOTX64.EFI` and `grubx64.efi `.  
These are provided by two packages: `grub2-efi-x64` and `shim-x64`.  
The locations of these on Rocky8 are in `/boot/efi/EFI/BOOT/BOOTX64.EFI ` and `/boot/efi/EFI/rocky/grubx64.efi` respectively.   
Once these packages are installed we can push them to s3:
```bash
s3_push --bucket-name efi --key-name BOOTX64.EFI --file-name /boot/efi/EFI/BOOT/BOOTX64.EFI
s3_push --bucket-name efi --key-name grubx64.efi --file-name /boot/efi/EFI/rocky/grubx64.efi
```

### Configure grub
This is just an example setup but you can configure grub however you wish

#### Setup grub.cfg
We first start with an entry point grub.cfg. This is so we can have multiple VMs if desired.  
Make a file called `grub.cfg` with the contents below.  
```
set prefix=(http,10.100.0.1:9000)/efi
configfile ${prefix}/grub.cfg-${net_default_mac}
```
This will key off of the MAC of the VM.  

#### Choose a MAC address for you VM
Again, this is up to you but a simple way to do this that was shamelessly stolen from StacOverflow:
```bash
VM_MAC=$(printf '02:00:00:%02X:%02X:%02X\n' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
```

#### Configure VM specific grub
Here we will create a grub.cfg that is specific for the VM.  
It's name will be based on the MAC address chosen above. 
Make a file called `grub.cfg-$VM_MAC` with contents below: 
```bash
set default="1"

function load_video {
  insmod efi_gop
  insmod efi_uga
  insmod video_bochs
  insmod video_cirrus
  insmod all_video
}

load_video
set gfxpayload=keep
insmod gzio
insmod part_gpt
insmod ext2

set timeout=10

menuentry 'Netboot OchamiVM' --class fedora --class gnu-linux --class gnu --class os {
        linuxefi /boot-images/efi-images/vmlinuz-4.18.0-477.27.1.el8_8.x86_64 nomodeset ro root=live:http://10.100.0.1:9000/boot-images/vm-images/ochami-vm-image.squashfs ip=dhcp overlayroot=tmpfs overlayroot_cfgdisk=disabled apparmor=0 console=ttyS0,115200 ip6=off "ds=nocloud-net;s=http://10.100.0.1:8000/cloud-init/${net_default_mac}/"
        initrdefi /boot-images/efi-images/initramfs-4.18.0-477.27.1.el8_8.x86_64.img
}
```
Some things to note here.
- linuxefi points to your kernel. It will have to match what is in s3 (`s3-list --bucketname boot-images`)
    - on the same line there is a `root=live` option. The IP here should match your `DUMMY_IP` setting (10.100.0.1 in our case)
    - another one on the same line is the `ds=nocloud-net`, you will again want to point this at the `DUMMY_IP`. We will cover cloud-init later
- initrdefi points to the initramfs in s3, so check the `boot-images` bucket to get the right option
- there are a few other options you can tweek, like the `timeout=10`

Once this file looks ok, push it to s3
```bash
s3_push --bucket-name efi --key-name grub.cfg-$VM_MAC  --file-name grub.cfg-$VM_MAC
```

### Cloud-init
The first thing is to take of where you set `CI_DATA` when setting up the cloud-init server. The default listed above was 
```bash
CI_DATA='/data/cloud-init'
```

In `$CI_DATA` we will place our VM configs
```bash
cd $CI_DATA
mkdir $VM_MAC
```
Then create a blank `vendor-data` file. We don't need this for the VM
```bash
touch $VM_MAC/vendor-data
```

Then create a `$VM_MAC/meta-data` file. This should look something like:
```bash
instance-id: myinstance123
local-hostname: ochami-vm
```
You can change either to be whatever you wish

The next file needed is `$VM_MAC/user-data`, this is where all the magic happens and is probably the most site specific setting you'll have to configure.

It's recommended to go through the cloud-init modules seen here: https://cloudinit.readthedocs.io/en/latest/reference/modules.html

Each has an example and most are not too confusing. 

An example is if you want to login as the root user to the VM from the host, you can add something like this to `$VM_MAC/user-data`:
```yaml
write_files:
- content: |
    <host_pub_key>
  path: /root/.ssh/authorized_keys
```
Just replace `host_pub_key` with the hosts public ssh key

Once cloud-init runs on the VM locally that key will be in place.

### configure libvirt
The last step before attempting to boot is to configure libvirt.  
We will use a custom libvirt network and it to use http network booting.

#### ENV variables
Before we begin lets set some things. You can change these to whatever you want:
```bash
export VM_NAME="ochami-vm"
export VM_MEMORY="16777216"
export VM_CPUS="1"
export VM_NETWORK="ochami"
export VM_BRIDGE="br0"
export VM_NET_MAC=$(printf '02:00:00:%02X:%02X:%02X\n' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
```
#### make a libvirt network
There is a template provided in `libvirt/ochami-network-template.xml`that will use the above variables to make a libvirt network

Let's modify our template:
```bash
mkdir -p /data/libvirt
VM_NET_FILE=/data/libvirt/ochami-network.xml
cp libvirt/ochami-network-template.xml $VM_NET_FILE
sed -i "s/@@@VM_NETWORK@@@/$VM_NETWORK/g" $VM_NET_FILE
sed -i "s/@@@VM_NET_MAC@@@/$VM_NET_MAC/g" $VM_NET_FILE
sed -i "s/@@@VM_MAC@@@/$VM_MAC/g" $VM_NET_FILE
sed -i "s/@@@VM_NAME@@@/$VM_NAME/g" $VM_NET_FILE
```
inspect the contents of `VM_NET_FILE`, and if it looks good run
```bash
virsh net-create $VM_NET_FILE
```
and check it is running and enable
```bash
virsh net-list
```

#### create the VM config file
We'll do a similar thing as above to create the VM config file

NOTE:
the `VM_BRIDGE` assumes you created a bridged interface for the VM to use in the prerequisites. If you didn't you'll need to modify the template and remove this stanza: 
```xml
    <interface type='bridge'>
      <source bridge="@@@VM_BRIDGE@@@"/>
      <model type="virtio"/>
    </interface>
```

Now lets create the VM config file
```bash
VM_CONFIG_FILE=/data/libvirt/ochami-vm.xml
cp libvirt/ochami-vm-template.xml $VM_CONFIG_FILE
sed -i "s/@@@VM_NAME@@@/$VM_NAME/g" $VM_CONFIG_FILE
sed -i "s/@@@VM_MEMORY@@@/$VM_MEMORY/g" $VM_CONFIG_FILE
sed -i "s/@@@VM_CPUS@@@/$VM_CPUS/g" $VM_CONFIG_FILE
sed -i "s/@@@VM_NETWORK@@@/$VM_NETWORK/g" $VM_CONFIG_FILE
sed -i "s/@@@VM_MAC@@@/$VM_MAC/g" $VM_NET_FILE
sed -i "s/@@@VM_BRIDGE@@@/$VM_BRIDGE/g" $VM_NET_FILE
```

Inspect `VM_CONFIG_FILE` and if things look ok then boot the VM:
```bash
virsh create $VM_CONFIG_FILE
```
check to make sure it started:
```bash
virsh list
```
You can watch the VM boot with 
```bash
virsh console $VM_NAME
```
The escape sequence is `ctl + ]`

## Debugging issues
TODO