# Preparing disk for longhorn

You need to prepare your disk(s) before use longhorn with it. You may use multiples disks or only one. This manual assume that you are using only one SSD. To know how work with multiples disks, please, consult the Longhorn docs.

## Unmounting

You may prefer that Longhorn use the currently installed device, and use only a part/size of it. It is possible and you can configure this on Longhorn interface. Or even create a specific partition for it.

In my scenario, I'm using a entire and dedicated disk as storage, that's already mounted. My first step, so, is format this disk. So I need to umount it.

```bash
sudo umount {/path/to/disk}
```

## What is my device?

You need to be sure what device you are going to ~destroy~ format. So, type the commands below to be sure about it:

```bash
lsblk -f
```

The output should be something similar to:

```bash

NAME FSTYPE FSVER LABEL UUID                                   FSAVAIL FSUSE% MOUNTPOINTS
sda  ext4   1.0         6d4f23a4-c597-44a4-b985-4b8661eb64eb    103,5G     0% /storage01
sdb
├─sdb1
│    vfat   FAT32       ECC8-3EC7                                   1G     1% /boot/efi
├─sdb2
│    ext4   1.0         6d025d9f-de5f-44c9-8663-765508eabd96      1,6G    10% /boot
└─sdb3
     LVM2_m LVM2        iOeWjJ-Ibs9-pVS7-2ZU7-kw8G-mLfr-hRWyun
  └─ubuntu--vg-ubuntu--lv
     ext4   1.0         68d74f52-f044-434e-b4fb-123e6b2b5bf7     55,1G    39% /var/lib/kubelet/pods/50668c00-5ae2-420b-a467-9a73fd7761ef/volume-subpaths/kafbat-ui-config/kafbat-ui/0
```

> Above you are seeing a real output from my machine. That's why the `sda` device is currently mounted. We expected that after `sudo umount ...` you device apears unmounted in this list.

I know that the righ device is `sda` because of size of it and because there are a lot of mounting points in `sdb`, beeing used to boot, kubelet and etc.

If you reboot your computer for any reason, check the device name again. This is more common on managed environment, but the drive letter can change after reboot. So be alert: Did you reboot? Check the device name again.

## Formating

Format your device as `ext4`:

```bash
mkfs.ext4 /dev/sda
```

In my example, `/dev/sda` represents the device that I wanna use. You must define `/dev/{device}` according to `lsblk` output.

## Mounting forever

To automatically mount the device after any reboot (if is a sever, you do not expect a lot of reboots, but...) you need to update the `/etc/fstab` file, with mounting parameters. But first of all, discover what is the driver UUID, typing:

```bash
blkid -s UUID -o value /dev/sda
```

Again, `/dev/sda` is my driver. You must define yours. The command output will be something like:

```bash
6d4f23a4-c597-44a4-b985-4b8661eb64eb
```

In the beggining, when you are selecting the disk, if you are a detalist person, you may notice that `/dev/sda` had a different UUID before formating process. **Every time you format a disk device, the UUID will going to change**. So, if this is not your first time mounting this disk, you **MUST** update `/etc/fstab` after format it.

Before mount the device, you will need to specify a mount point. By default, Longhorn use a `/storage01` folder as disk entrypoint. I do advice you to use the same naming. Then, create a directory at root folder:

```bash
sudo mkdir /storage01
```


Now, open the `/etc/fstab` for update (I like vim, but you can use your favorite editor):

```bash
sudo vim /etc/fstab
```

Using the keyboard, go to the end of file. Press "Insert" key and then "Enter" key. You may have created a new line at the end of file. Type to type:

```text
# a lot of thing about your disks
# add the line bellow at the end of file:
UUID=6d4f23a4-c597-44a4-b985-4b8661eb64eb /storage01 ext4 defaults 0 0
```

Time to mount:

```bash
sudo mount /storage01
```

Done!

If you access this directory you will only see a `lost+found` folder. And if you restart your server, you must have the driver mounted automatically.

## Multipathd issue

You deploy a manifest that create a PVC. But the pods NEVER become ready. When you check the logs/event you see something like below:

>MountVolume.MountDevice failed for volume "pvc-8c78c53a-d015-4c2a-bd36-afaa0ebbe035" : rpc error: code = Internal desc = format of disk "/dev/longhorn/pvc-8c78c53a-d015-4c2a-bd36-afaa0ebbe035" failed: type:("ext4") target:("/var/lib/kubelet/plugins/kubernetes.io/csi/driver.longhorn.io/480274e2aa87cdc0618a1dcfed9272ccd6f52d39c9f42f493520bce70648b4de/globalmount") options:("defaults") errcode:(exit status 1) output:(mke2fs 1.47.0 (5-Feb-2023) /dev/longhorn/pvc-8c78c53a-d015-4c2a-bd36-afaa0ebbe035 is apparently in use by the system; will not make a filesystem here! )

Some environment, after update, has installed `multipathd`. This software may cause issues when running along side Longhorn. That's because both use the device at same time and longhorn is extremally possessive. If it does not have full controll, then none will be done. After all, at each created PVC, longhorn needs to format a piece of disk. How to format when there are people (software) using it?!

To fix this issue, you need to scale down your deployments:

```bash
# If is a statefulset
kubectl -n my-namespace scale statefulset my-scalleset --replicas=0

# or if is a deployment
kubectl -n my-namespace scale deployment my-deployment --replicas=0
```

You may disable multipathd - if you do not need it.

```bash
sudo systemctl disable --now multipathd
```

Or you can add devices to black list. 

Fix the `/etc/multipathd':

```bash
sudo vim /etc/multipathd
```

and then add the new content at the end of file:

```conf
blacklist {
    devnode "^sd[a-z0-9]+"
}
```

> Is important add all sdX devices because longhorn will mount and format new sdX for each mounted volume. Add only `/dev/sda/` will not solve the problem.

Now, restart the multipathd. But if it is possible, I strongly recommend that you reboot your system.

```bash
sudo systemctl restart multipatchd
```

Then is time to scale up!

```bash
# If is a statefulset
kubectl -n my-namespace scale statefulset my-scalleset --replicas=1

# or if is a deployment
kubectl -n my-namespace scale deployment my-deployment --replicas=1
```

All done!