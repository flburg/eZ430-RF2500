/*
 *  ==== DO NOT MODIFY THIS FILE - CHANGES WILL BE OVERWRITTEN ====
 *
 *  Generated from
 *      C:/ti/grace/grace_1_10_03_31_eng/packages/ti/mcu/msp430/csl/watchdog/WDTplus_init.xdt
 */

#include <msp430.h>

/*
 *  ======== WDTplus_init ========
 *  Initialize MSP430 Watchdog Timer+
 */
void WDTplus_init(void)
{
    /* 
     * WDTCTL, Watchdog Timer+ Register
     * 
     * WDTPW -- Watchdog password
     * WDTHOLD -- Watchdog timer+ is stopped
     * ~WDTNMIES -- NMI on rising edge
     * ~WDTNMI -- Reset function
     * ~WDTTMSEL -- Watchdog mode
     * ~WDTCNTCL -- No action
     * WDTSSEL -- ACLK
     * ~WDTIS0 -- Watchdog clock source bit0 disabled
     * ~WDTIS1 -- Watchdog clock source bit1 disabled
     * 
     * Note: ~<BIT> indicates that <BIT> has value zero
     */
    WDTCTL = WDTPW + WDTHOLD + WDTSSEL;
    
}
