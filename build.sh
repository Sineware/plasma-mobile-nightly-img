#!/usr/bin/env bash
set -e
whoami

# Partially derived from https://builds.sr.ht/api/jobs/848773/manifest

build_image () {
    echo "Building image for $1"
    if [ ! -d pmaports ]; then
        git clone https://gitlab.com/postmarketOS/pmaports.git
    else 
        cd pmaports
        git pull
        cd ..
    fi

    yes "" | pmbootstrap --aports=$PWD/pmaports -q init

    pmbootstrap config ui plasma-mobile
    pmbootstrap config device ${1}
    pmbootstrap config kernel "$2"
    pmbootstrap config extra_packages osk-sdl

    pmbootstrap -q -y zap -p

    # 147147 is the default pin
    printf "%s\n%s\n" 147147 147147 | pmbootstrap \
        -m http://dl-cdn.alpinelinux.org/alpine/ \
        -mp http://mirror.postmarketos.org/postmarketos/ \
        --details-to-stdout \
        install

    # pmbootstrap shutdown
    ls -l $(pmbootstrap config work)/chroot_native/home/pmos/rootfs/

    cp -v $(pmbootstrap config work)/chroot_native/home/pmos/rootfs/${1}.img .
    IMAGE_FILE="${1}.img"
    LOOP_DEV=$(sudo losetup -f)
    echo "Loop Device: $LOOP_DEV"
    sudo losetup -f -P $IMAGE_FILE
    losetup -l
    sudo partprobe $LOOP_DEV
    sudo udevadm trigger
    echo "Waiting for devices to settle..."
    sleep 5
    ls -l /dev/disk/by-label
    if [ ! -e /dev/disk/by-label/pmOS_root ]; then
        echo "Error: /dev/disk/by-label/pmOS_root does not exist"
        sudo losetup -d $LOOP_DEV
        exit 1
    fi
    mkdir -pv ./mnt
    sudo mount /dev/disk/by-label/pmOS_root ./mnt
    ls -l ./mnt
    sudo echo "https://espi.sineware.ca/repo/alpine/prolinux-nightly/" | sudo tee -a ./mnt/etc/apk/repositories
    sudo wget -O ./mnt/etc/apk/keys/swadmin-632219ce.rsa.pub https://sineware.ca/prolinux/plasma-mobile-nightly/swadmin-632219ce.rsa.pub
    #PS1="] " sh

    echo "Entering chroot..."
    sudo mount -t proc /proc ./mnt/proc/
    sudo mount -t sysfs /sys ./mnt/sys/
    sudo mount --bind /dev ./mnt/dev/
    sudo cp /etc/resolv.conf ./mnt/etc/resolv.conf
    
    echo "Enabling binfmt multiarch..."
    sudo docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

    # chroot
    sudo chroot ./mnt /bin/busybox sh  <<'EOF'
        echo "(chroot) Upgrading to Plasma Mobile Nightly packages..."
        /sbin/apk update
        /sbin/apk upgrade
        /sbin/apk add nano bash neofetch htop
        echo "Sineware ProLinux - Plasma Mobile Nightly Image built on $(/bin/date)" >> prolinux_build_info.txt
        echo "(chroot) Exiting chroot..."
EOF

    sudo rm -rf ./mnt/etc/resolv.conf

    sudo umount -R ./mnt
    sudo losetup -d $LOOP_DEV
}

build_image "tablet-x64uefi" "stable"
build_image "pine64-pinephone" ""

# compress each *.img file
for f in *.img; do
    echo "Compressing $f"
    xz -T0 -v $f
    # create hash of file
    sha256sum $f.xz > $f.xz.sha256
done

rsync -aHAXxv --delete --progress *.img.* espimac:/var/www/sineware/images/plasma-mobile-nightly/

echo "All done!"