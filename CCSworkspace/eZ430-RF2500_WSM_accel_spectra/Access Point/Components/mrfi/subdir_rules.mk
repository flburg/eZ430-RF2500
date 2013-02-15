################################################################################
# Automatically-generated file. Do not edit!
################################################################################

# Each subdirectory must supply rules for building sources it contributes
Components/mrfi/mrfi.obj: C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Code/Components/mrfi/mrfi.c $(GEN_OPTS) $(GEN_SRCS)
	@echo 'Building file: $<'
	@echo 'Invoking: MSP430 Compiler'
	"C:/ti/ccsv5/tools/compiler/msp430_4.1.1/bin/cl430" --cmd_file="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/eZ430-RF2500_WSM_accel_spectra/Configuration/smpl_nwk_config.dat" --cmd_file="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/eZ430-RF2500_WSM_accel_spectra/Configuration/Access Point/smpl_config_AP.dat"  -vmsp --abi=coffabi -Ooff --opt_for_speed=0 -g --include_path="C:/ti/ccsv5/ccs_base/msp430/include" --include_path="C:/ti/ccsv5/tools/compiler/msp430_4.1.1/include" --include_path="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Code/Components/bsp" --include_path="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Code/Components/bsp/boards/EZ430RF" --include_path="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Code/Components/bsp/drivers" --include_path="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Code/Components/mrfi" --include_path="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Code/Components/simpliciti/nwk" --include_path="C:/Users/flb.bwrclt61-1/Desktop/research/ME_local/eZ430-RF2500/CCSworkspace/Code/Components/simpliciti/nwk_applications" --define=__MSP430F2274__ --define=MRFI_CC2500 --diag_warning=225 --printf_support=minimal --preproc_with_compile --preproc_dependency="Components/mrfi/mrfi.pp" --obj_directory="Components/mrfi" $(GEN_OPTS__FLAG) "$<"
	@echo 'Finished building: $<'
	@echo ' '


