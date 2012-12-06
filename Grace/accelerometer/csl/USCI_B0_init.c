/*
 *  ==== DO NOT MODIFY THIS FILE - CHANGES WILL BE OVERWRITTEN ====
 *
 *  Generated from
 *      C:/ti/grace/grace_1_10_03_31_eng/packages/ti/mcu/msp430/csl/communication/USCI_B0_init.xdt
 */

#include <msp430.h>

/*
 *  ======== USCI_B0_init ========
 *  Initialize Universal Serial Communication Interface B0 SPI 2xx
 */
void USCI_B0_init(void)
{
    /* Disable USCI */
    UCB0CTL1 |= UCSWRST;
    
    /* 
     * Control Register 0
     * 
     * UCCKPH -- Data is captured on the first UCLK edge and changed on the following edge
     * UCCKPL -- Inactive state is high
     * UCMSB -- MSB first
     * ~UC7BIT -- 8-bit
     * UCMST -- Master mode
     * UCMODE_2 -- 4-Pin SPI with UCxSTE active low: slave enabled when UCxSTE = 0
     * UCSYNC -- Synchronous Mode
     * 
     * Note: ~UC7BIT indicates that UC7BIT has value zero
     */
    UCB0CTL0 = UCCKPH + UCCKPL + UCMSB + UCMST + UCMODE_2 + UCSYNC;
    
    /* 
     * Control Register 1
     * 
     * UCSSEL_2 -- SMCLK
     * UCSWRST -- Enabled. USCI logic held in reset state
     */
    UCB0CTL1 = UCSSEL_2 + UCSWRST;
    
    /* Bit Rate Control Register 0 */
    UCB0BR0 = 16;
    
    /* Enable USCI */
    UCB0CTL1 &= ~UCSWRST;
}
