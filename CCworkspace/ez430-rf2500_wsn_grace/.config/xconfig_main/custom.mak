## THIS IS A GENERATED FILE -- DO NOT EDIT
.configuro: .libraries,e430 linker.cmd \
  package/cfg/main_pe430.oe430 \

linker.cmd: package/cfg/main_pe430.xdl
	$(SED) 's"^\"\(package/cfg/main_pe430cfg.cmd\)\"$""\"C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430-rf2500_wsn_grace/.config/xconfig_main/\1\""' package/cfg/main_pe430.xdl > $@
