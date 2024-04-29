#!/bin/bash

#Start from a base almalinux image
#You can also start from scratch
## MNAME=$(buildah mount $CNAME)
## dnf install --installroot=$MNAME <packages>
CNAME=$(buildah from scratch)

MNAME=$(buildah mount $CNAME)
REPO_DIR="${MNAME}/etc/yum.repos.d"

#Add extra repos here
dnf config-manager --setopt=reposdir=${REPO_DIR} \
	--add-repo https://download.docker.com/linux/centos/docker-ce.repo

dnf config-manager --setopt=reposdir=${REPO_DIR} \
        --add-repo https://repo.almalinux.org/almalinux/8/BaseOS/x86_64/os

dnf config-manager --setopt=reposdir=${REPO_DIR} \
        --add-repo https://repo.almalinux.org/almalinux/8/AppStream/x86_64/os

dnf config-manager --setopt=reposdir=${REPO_DIR} \
        --add-repo https://repo.almalinux.org/almalinux/8/PowerTools/x86_64/os

#Generate machine-id
#buildah run $CNAME bash -c "rm -f /etc/machine-id; dbus-uuidgen --ensure=/etc/machine-id"

dnf groupinstall --releasever=8 --nogpgcheck --installroot $MNAME -y \
	'Minimal Install'

#install packages
buildah run $CNAME dnf install --nogpgcheck -y \
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
	openssh-server \
	openssh-clients \
	NetworkManager-initscripts-updown

#Update the initramfs so we can network mount the rootfs
buildah run $CNAME bash -c "dracut \
	--add \"dmsquash-live livenet network-manager\" \
	--kver \"\$(basename /lib/modules/*)\" -N -f"

#mount the container so we can push up the image kernel and initramfs
#MNAME=$(buildah mount $CNAME)

buildah run $CNAME bash -c "systemctl disable firewalld"

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
mksquashfs $MNAME ochami-vm-image.squashfs

s3-push \
	--bucket-name boot-images \
	--key-name vm-images/ochami-vm-image.squashfs \
	--file-name ochami-vm-image.squashfs
