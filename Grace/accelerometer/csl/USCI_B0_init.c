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
     * ~UCCKPL -- Inactive state is low
     * UCMSB -- MSB first
     * ~UC7BIT -- 8-bit
     * UCMST -- Master mode
     * UCMODE_0 -- 3-Pin SPI
     * UCSYNC -- Synchronous Mode
     * 
     * Note: ~<BIT> indicates that <BIT> has value zero
     */
    UCB0CTL0 = UCCKPH + UCMSB + UCMST + UCMODE_0 + UCSYNC;
    
    /* 
     * Control Register 1
     * 
     * UCSSEL_1 -- ACLK
     * UCSWRST -- Enabled. USCI logic held in reset state
     */
    UCB0CTL1 = UCSSEL_1 + UCSWRST;
    
    /* Bit Rate Control Register 0 */
    UCB0BR0 = 2;
    
    /* Enable USCI */
    UCB0CTL1 &= ~UCSWRST;
}
