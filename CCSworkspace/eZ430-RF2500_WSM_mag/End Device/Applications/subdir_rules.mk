################################################################################
# Automatically-generated file. Do not edit!
################################################################################

# Each subdirectory must supply rules for building sources it contributes
Applications/flash.obj: ../Applications/flash.c $(GEN_OPTS) $(GEN_SRCS)
	@echo 'Building file: $<'
	@echo 'Invoking: MSP430 Compiler'
	"C:/ti/ccsv5/tools/compiler/msp430_4.1.1/bin/cl430" --cmd_file="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/eZ430-RF2500_WSM_mag/Configuration/smpl_nwk_config.dat" --cmd_file="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/eZ430-RF2500_WSM_mag/Configuration/End Device/smpl_config_ED.dat"  -vmsp --abi=coffabi -Ooff --opt_for_speed=0 -g --include_path="C:/ti/ccsv5/ccs_base/msp430/include" --include_path="C:/ti/ccsv5/tools/compiler/msp430_4.1.1/include" --include_path="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Shared/Components/bsp" --include_path="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Shared/Components/bsp/boards/EZ430RF" --include_path="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Shared/Components/bsp/boards/EZ430RF/bsp_external" --include_path="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Shared/Components/bsp/drivers" --include_path="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Shared/Components/mrfi" --include_path="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Shared/Components/simpliciti/nwk" --include_path="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Shared/Components/simpliciti/nwk_applications" --define=__MSP430F2274__ --define=MRFI_CC2500 --diag_warning=225 --printf_support=minimal --preproc_with_compile --preproc_dependency="Applications/flash.pp" --obj_directory="Applications" $(GEN_OPTS__FLAG) "$<"
	@echo 'Finished building: $<'
	@echo ' '

Applications/main_ED.obj: ../Applications/main_ED.c $(GEN_OPTS) $(GEN_SRCS)
	@echo 'Building file: $<'
	@echo 'Invoking: MSP430 Compiler'
	"C:/ti/ccsv5/tools/compiler/msp430_4.1.1/bin/cl430" --cmd_file="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/eZ430-RF2500_WSM_mag/Configuration/smpl_nwk_config.dat" --cmd_file="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/eZ430-RF2500_WSM_mag/Configuration/End Device/smpl_config_ED.dat"  -vmsp --abi=coffabi -Ooff --opt_for_speed=0 -g --include_path="C:/ti/ccsv5/ccs_base/msp430/include" --include_path="C:/ti/ccsv5/tools/compiler/msp430_4.1.1/include" --include_path="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Shared/Components/bsp" --include_path="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Shared/Components/bsp/boards/EZ430RF" --include_path="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Shared/Components/bsp/boards/EZ430RF/bsp_external" --include_path="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Shared/Components/bsp/drivers" --include_path="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Shared/Components/mrfi" --include_path="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Shared/Components/simpliciti/nwk" --include_path="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Shared/Components/simpliciti/nwk_applications" --define=__MSP430F2274__ --define=MRFI_CC2500 --diag_warning=225 --printf_support=minimal --preproc_with_compile --preproc_dependency="Applications/main_ED.pp" --obj_directory="Applications" $(GEN_OPTS__FLAG) "$<"
	@echo 'Finished building: $<'
	@echo ' '


