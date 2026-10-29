#!/bin/sh
# Prints a GPU performance tier: low | mid | high   (graphics only; combine with CPU threads yourself)
#   low  : Intel gen<=4 (HD 2000-4600), ULV (U/Y) laptop chips older than 11th gen, legacy AMD, no/unknown GPU, nouveau-only
#   mid  : Intel gen 5-11 (non-ULV), ULV chips from 11th gen (Xe graphics), modern AMD APU, hybrid laptops (the iGPU does the work)
#   high : Intel gen>=12, discrete AMD, NVIDIA as the ONLY GPU with the proprietary driver
# Rule of thumb for hybrid Intel+NVIDIA laptops: the compositor runs on the Intel iGPU, so the
# Intel tier decides (using the dGPU needs PRIME offload and burns battery).
here=$(dirname "$0")
vendors=$(sh "$here/get_gpu_vendors.sh")
has() { case " $vendors " in *" $1 "*) return 0 ;; esac; return 1; }

if has intel; then
    gen=$(sh "$here/get_intel_gen.sh")
    ulv=$(sh "$here/get_cpu_is_ulv.sh")
    if   [ "$gen" -gt 0 ] && [ "$gen" -le 4 ]; then echo low
    elif [ "$ulv" = true ] && [ "$gen" -ge 11 ]; then echo mid   # low-power chips with Xe graphics
    elif [ "$ulv" = true ];                    then echo low
    elif [ "$gen" -ge 12 ];                    then echo high
    else echo mid; fi
elif has nvidia; then
    if [ "$(sh "$here/get_nvidia_driver.sh")" = proprietary ]; then echo high; else echo low; fi
elif has amd; then
    case "$(sh "$here/get_amd_gpu_class.sh")" in
        legacy) echo low ;; discrete) echo high ;; *) echo mid ;;
    esac
else
    echo low
fi
