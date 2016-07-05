#!/bin/bash -ex
### Build a docker image for ubuntu i386.

set -e

### settings
arch=i386
suite=${1:-trusty}
chroot_dir="/var/chroot/builder-ubuntu32bit/$suite"
apt_mirror='http://archive.ubuntu.com/ubuntu'
docker_image="32bit/ubuntu:${1:-14.04}"

### make sure that the required tools are installed
packages="debootstrap dchroot apparmor"
which docker || packages="$packages docker.io"
apt-get install -y $packages

if [ -d $chroot_dir ]; then
    rm -rf $chroot_dir
fi

### install a minbase system with debootstrap
export DEBIAN_FRONTEND=noninteractive
debootstrap --variant=minbase --arch=$arch $suite $chroot_dir $apt_mirror

### update the list of package sources
cat <<EOF > $chroot_dir/etc/apt/sources.list
deb $apt_mirror $suite main restricted universe multiverse
deb $apt_mirror $suite-updates main restricted universe multiverse
deb $apt_mirror $suite-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu $suite-security main restricted universe multiverse
deb http://extras.ubuntu.com/ubuntu $suite main
EOF

### install ubuntu-minimal
cp /etc/resolv.conf $chroot_dir/etc/resolv.conf
mount -o bind /proc $chroot_dir/proc
mount -t sysfs none $chroot_dir/sys
mkdir -p $chroot_dir/dev/pts
mount -t devpts none $chroot_dir/dev/pts

if [ "x$INSTALL_IN_DOCKER" = xyes ]; then
    # Divert away initctl temporarily to allow proper installation and
    # "config" by apt-get
    # ref: https://github.com/docker/docker/issues/1024#issuecomment-20018600
    chroot $chroot_dir dpkg-divert --local --rename --add /sbin/initctl
    chroot $chroot_dir ln -sf /bin/true /sbin/initctl
fi

chroot $chroot_dir apt-get update
chroot $chroot_dir apt-get -y upgrade
chroot $chroot_dir apt-get -y install ubuntu-minimal

### cleanup
chroot $chroot_dir apt-get autoclean
chroot $chroot_dir apt-get clean
chroot $chroot_dir apt-get autoremove
rm $chroot_dir/etc/resolv.conf

if [ "x$INSTALL_IN_DOCKER" = xyes ]; then
    # Undo diversion
    chroot $chroot_dir rm /sbin/initctl
    chroot $chroot_dir dpkg-divert --rename --remove /sbin/initctl
fi

### unmount other auxiliary mount points, first
umount $chroot_dir/dev/pts
umount $chroot_dir/sys

### kill any processes that are running on chroot
chroot_pids=$(for p in /proc/*/root; do ls -l $p; done | grep $chroot_dir | cut -d'/' -f3)
test -z "$chroot_pids" || (kill -9 $chroot_pids; sleep 2)

### unmount /proc
umount $chroot_dir/proc

### create a tar archive from the chroot directory
tar cfz ubuntu.tgz -C $chroot_dir .

### import this tar archive into a docker image:
echo "cat ubuntu.tgz | docker import - $docker_image"

# ### push image to Docker Hub
# docker push $docker_image

### cleanup
echo rm ubuntu.tgz
rm -rf $chroot_dir
