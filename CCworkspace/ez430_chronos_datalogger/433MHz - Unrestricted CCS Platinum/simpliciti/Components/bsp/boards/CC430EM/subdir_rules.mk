################################################################################
# Automatically-generated file. Do not edit!
################################################################################

# Each subdirectory must supply rules for building sources it contributes
simpliciti/Components/bsp/boards/CC430EM/bsp_board.obj: ../simpliciti/Components/bsp/boards/CC430EM/bsp_board.c $(GEN_OPTS) $(GEN_SRCS)
	@echo 'Building file: $<'
	@echo 'Invoking: MSP430 Compiler'
	"C:/ti/ccsv5/tools/compiler/msp430_4.1.1/bin/cl430" --cmd_file="C:\Users\flb.bwrclt61-1\Desktop\eZ430-RF2500\CCworkspace\ez430_chronos_datalogger\simpliciti\Applications\configuration\smpl_nwk_config.dat" --cmd_file="C:\Users\flb.bwrclt61-1\Desktop\eZ430-RF2500\CCworkspace\ez430_chronos_datalogger\simpliciti\Applications\configuration\End Device\smpl_config.dat"  --silicon_version=mspx -g -O2 --define=__CCE__ --define=ISM_LF --define=MRFI_CC430 --define=__CC430F6137__ --include_path="C:/ti/ccsv5/ccs_base/msp430/include" --include_path="C:/ti/ccsv5/msp430/include" --include_path="C:/ti/ccsv5/tools/compiler/msp430_4.1.1/include" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos_datalogger" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos_datalogger/driver" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos_datalogger/include" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos_datalogger/logic" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos_datalogger/bluerobin" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos_datalogger/simpliciti" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos_datalogger/simpliciti/Applications/application/End Device" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos_datalogger/simpliciti/Components/bsp" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos_datalogger/simpliciti/Components/bsp/boards" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos_datalogger/simpliciti/Components/bsp/boards/CC430EM" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos_datalogger/simpliciti/Components/bsp/boards/CC430EM/bsp_external" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos_datalogger/simpliciti/Components/bsp/drivers" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos_datalogger/simpliciti/Components/bsp/drivers/code" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos_datalogger/simpliciti/Components/bsp/mcus" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos_datalogger/simpliciti/Components/mrfi" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos_datalogger/simpliciti/Components/mrfi/radios" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos_datalogger/simpliciti/Components/mrfi/radios/family5" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos_datalogger/simpliciti/Components/mrfi/smartrf" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos_datalogger/simpliciti/Components/nwk" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos_datalogger/simpliciti/Components/nwk_applications" --diag_warning=225 --printf_support=minimal --preproc_with_compile --preproc_dependency="simpliciti/Components/bsp/boards/CC430EM/bsp_board.pp" --obj_directory="simpliciti/Components/bsp/boards/CC430EM" $(GEN_OPTS__FLAG) "$<"
	@echo 'Finished building: $<'
	@echo ' '


