#!/bin/bash

#Start from a base almalinux image
#You can also start from scratch
## MNAME=$(buildah mount $CNAME)
## dnf install --installroot=$MNAME <packages>
CNAME=$(buildah from almalinux:8)

# install dnf config-manager
buildah run $CNAME dnf install -y 'dnf-command(config-manager)'

#Add extra repos here
buildah run $CNAME dnf config-manager \
	--add-repo https://download.docker.com/linux/centos/docker-ce.repo

#Generate machine-id
buildah run $CNAME bash -c "rm -f /etc/machine-id; dbus-uuidgen --ensure=/etc/machine-id"

#install packages
buildah run $CNAME dnf install -y \
	kernel \
	grub2-efi-x64 \
	dracut-live \
	cloud-init \
	jq \
	vim \
	docker-ce \
	docker-ce-cli \
	containerd.io \
	nss_db \
	nfs-utils \
        openssh-clients \
        openssh-server \
        libssh \
	NetworkManager-initscripts-updown

# Unmask login service to allow login via console.
buildah run $CNAME systemctl unmask systemd-logind

# Unmask TTY target so login prompt will appear.
buildah run $CNAME systemctl unmask getty.target

#Update the initramfs so we can network mount the rootfs
buildah run $CNAME bash -c "dracut \
	--add \"dmsquash-live livenet network-manager\" \
	--kver \"\$(basename /lib/modules/*)\" -N -f"

#mount the container so we can push up the image kernel and initramfs
MNAME=$(buildah mount $CNAME)

#get the kernel version
KVER="$(basename $MNAME/lib/modules/*)"

#using our s3 utilities we can push to an s3 instance
s3-push \
	--bucket-name boot-images \
	--key-name efi-images/vmlinuz-$KVER \
	--file-name $MNAME/boot/vmlinuz-$KVER

s3-push \
	--bucket-name boot-images \
	--key-name efi-images/initramfs-$KVER.img \
	--file-name $MNAME/boot/initramfs-$KVER.img

#Now squash up the image and push it to s3
mksquashfs $MNAME ochami-vm-image.squashfs -noappend

s3-push \
	--bucket-name boot-images \
	--key-name vm-images/ochami-vm-image.squashfs \
	--file-name ochami-vm-image.squashfs
