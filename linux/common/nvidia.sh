

# https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/fedora.html
# The above uses https://developer.download.nvidia.com/compute/cuda/repos/fedora43/x86_64/

#sudo dnf config-manager addrepo --from-repofile=https://developer.download.nvidia.com/compute/cuda/repos/fedora43/x86_64/cuda-fedora43.repo



=======================================


write a script that sets up existing NVIDIA graphics card on a fresh installation of fedora 43 (Wayland). Check the necessary hardware or generation or how old it is, etc and install appropriate tools/software/drivers, etc accordingly. Should support all NVIDIA graphics cards from 2012 till the latest. If there are multiple options in some cases, write both options with explanation, but comment out the less preferred option. Also, add comments whether the thing being installed is FOSS or proprietary. 


write a script that sets up existing NVIDIA graphics card on a fresh installation of fedora 43 (Wayland). If there are multiple options in some cases, write both options with explanation, but comment out the less preferred option. Also, add comments whether the thing being installed is FOSS or proprietary. 

```
lspci -v | grep -A 12 "VGA"
```
is returning 
```
00:02.0 VGA compatible controller: Intel Corporation Skylake-H GT2 [HD Graphics 530] (rev 06) (prog-if 00 [VGA controller])
```
However, the following :
```
lspci -v | grep "NVIDIA"
```
returns:
```
01:00.0 3D controller: NVIDIA Corporation GM107M [GeForce GTX 960M] (rev a2)
```