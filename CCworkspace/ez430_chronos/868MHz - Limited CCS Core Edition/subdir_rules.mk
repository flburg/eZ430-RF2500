################################################################################
# Automatically-generated file. Do not edit!
################################################################################

# Each subdirectory must supply rules for building sources it contributes
main.obj: ../main.c $(GEN_OPTS) $(GEN_SRCS)
	@echo 'Building file: $<'
	@echo 'Invoking: MSP430 Compiler'
	"C:/ti/ccsv5/tools/compiler/msp430_4.1.1/bin/cl430" --silicon_version=mspx -g -O3 --define=__CCE__ --define=ISM_EU --include_path="C:/ti/ccsv5/ccs_base/msp430/include" --include_path="C:/ti/ccsv5/msp430/include" --include_path="C:/ti/ccsv5/tools/compiler/msp430_4.1.1/include" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos/include" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos/driver" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos/logic" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos/bluerobin" --include_path="C:/Users/flb.bwrclt61-1/Desktop/eZ430-RF2500/CCworkspace/ez430_chronos/simpliciti" --diag_warning=225 --call_assumptions=0 --gen_opt_info=2 --printf_support=minimal --preproc_with_compile --preproc_dependency="main.pp" $(GEN_OPTS__FLAG) "$<"
	@echo 'Finished building: $<'
	@echo ' '

