################################################################################
# Automatically-generated file. Do not edit!
################################################################################

# Each subdirectory must supply rules for building sources it contributes
Applications/main_AP.obj: C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Applications/main_AP.c $(GEN_OPTS) $(GEN_SRCS)
	@echo 'Building file: $<'
	@echo 'Invoking: MSP430 Compiler'
	"C:/ti/ccsv5/tools/compiler/msp430_4.1.1/bin/cl430" --cmd_file="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/eZ430-RF2500_WSM/../Code/Configuration/smpl_nwk_config.dat" --cmd_file="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/eZ430-RF2500_WSM/../Code/Configuration/smpl_config_AP.dat"  -vmsp --abi=coffabi -Ooff --opt_for_speed=0 -g --include_path="C:/ti/ccsv5/ccs_base/msp430/include" --include_path="C:/ti/ccsv5/tools/compiler/msp430_4.1.1/include" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Components/bsp" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Components/bsp/boards/EZ430RF" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Components/bsp/drivers" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Components/mrfi" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Components/simpliciti/nwk" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Components/simpliciti/nwk_applications" --include_path="C:/ti/grace_1_10_04_36/packages" --define=__MSP430F2274__ --define=MRFI_CC2500 --diag_warning=225 --printf_support=minimal --preproc_with_compile --preproc_dependency="Applications/main_AP.pp" --obj_directory="Applications" $(GEN_OPTS__FLAG) "$<"
	@echo 'Finished building: $<'
	@echo ' '

Applications/virtual_com_cmds.obj: C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Applications/virtual_com_cmds.c $(GEN_OPTS) $(GEN_SRCS)
	@echo 'Building file: $<'
	@echo 'Invoking: MSP430 Compiler'
	"C:/ti/ccsv5/tools/compiler/msp430_4.1.1/bin/cl430" --cmd_file="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/eZ430-RF2500_WSM/../Code/Configuration/smpl_nwk_config.dat" --cmd_file="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/eZ430-RF2500_WSM/../Code/Configuration/smpl_config_AP.dat"  -vmsp --abi=coffabi -Ooff --opt_for_speed=0 -g --include_path="C:/ti/ccsv5/ccs_base/msp430/include" --include_path="C:/ti/ccsv5/tools/compiler/msp430_4.1.1/include" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Components/bsp" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Components/bsp/boards/EZ430RF" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Components/bsp/drivers" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Components/mrfi" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Components/simpliciti/nwk" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Components/simpliciti/nwk_applications" --include_path="C:/ti/grace_1_10_04_36/packages" --define=__MSP430F2274__ --define=MRFI_CC2500 --diag_warning=225 --printf_support=minimal --preproc_with_compile --preproc_dependency="Applications/virtual_com_cmds.pp" --obj_directory="Applications" $(GEN_OPTS__FLAG) "$<"
	@echo 'Finished building: $<'
	@echo ' '

Applications/vlo_rand.obj: C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Applications/vlo_rand.asm $(GEN_OPTS) $(GEN_SRCS)
	@echo 'Building file: $<'
	@echo 'Invoking: MSP430 Compiler'
	"C:/ti/ccsv5/tools/compiler/msp430_4.1.1/bin/cl430" --cmd_file="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/eZ430-RF2500_WSM/../Code/Configuration/smpl_nwk_config.dat" --cmd_file="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/eZ430-RF2500_WSM/../Code/Configuration/smpl_config_AP.dat"  -vmsp --abi=coffabi -Ooff --opt_for_speed=0 -g --include_path="C:/ti/ccsv5/ccs_base/msp430/include" --include_path="C:/ti/ccsv5/tools/compiler/msp430_4.1.1/include" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Components/bsp" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Components/bsp/boards/EZ430RF" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Components/bsp/drivers" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Components/mrfi" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Components/simpliciti/nwk" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/Code/Components/simpliciti/nwk_applications" --include_path="C:/ti/grace_1_10_04_36/packages" --define=__MSP430F2274__ --define=MRFI_CC2500 --diag_warning=225 --printf_support=minimal --preproc_with_compile --preproc_dependency="Applications/vlo_rand.pp" --obj_directory="Applications" $(GEN_OPTS__FLAG) "$<"
	@echo 'Finished building: $<'
	@echo ' '


