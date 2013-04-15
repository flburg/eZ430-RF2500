/**************************************************************************************************
  Revised:        $Date: 2007-07-06 11:19:00 -0700 (Fri, 06 Jul 2007) $
  Revision:       $Revision: 13579 $

  Copyright 2007 Texas Instruments Incorporated.  All rights reserved.

  IMPORTANT: Your use of this Software is limited to those specific rights granted under
  the terms of a software license agreement between the user who downloaded the software,
  his/her employer (which must be your employer) and Texas Instruments Incorporated (the
  "License"). You may not use this Software unless you agree to abide by the terms of the
  License. The License limits your use, and you acknowledge, that the Software may not be
  modified, copied or distributed unless embedded on a Texas Instruments microcontroller
  or used solely and exclusively in conjunction with a Texas Instruments radio frequency
  transceiver, which is integrated into your product. Other than for the foregoing purpose,
  you may not use, reproduce, copy, prepare derivative works of, modify, distribute,
  perform, display or sell this Software and/or its documentation for any purpose.

  YOU FURTHER ACKNOWLEDGE AND AGREE THAT THE SOFTWARE AND DOCUMENTATION ARE PROVIDED “AS IS”
  WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION, ANY
  WARRANTY OF MERCHANTABILITY, TITLE, NON-INFRINGEMENT AND FITNESS FOR A PARTICULAR PURPOSE.
  IN NO EVENT SHALL TEXAS INSTRUMENTS OR ITS LICENSORS BE LIABLE OR OBLIGATED UNDER CONTRACT,
  NEGLIGENCE, STRICT LIABILITY, CONTRIBUTION, BREACH OF WARRANTY, OR OTHER LEGAL EQUITABLE
  THEORY ANY DIRECT OR INDIRECT DAMAGES OR EXPENSES INCLUDING BUT NOT LIMITED TO ANY
  INCIDENTAL, SPECIAL, INDIRECT, PUNITIVE OR CONSEQUENTIAL DAMAGES, LOST PROFITS OR LOST
  DATA, COST OF PROCUREMENT OF SUBSTITUTE GOODS, TECHNOLOGY, SERVICES, OR ANY CLAIMS BY
  THIRD PARTIES (INCLUDING BUT NOT LIMITED TO ANY DEFENSE THEREOF), OR OTHER SIMILAR COSTS.

  Should you have any questions regarding your right to use this Software,
  contact Texas Instruments Incorporated at www.TI.com.
**************************************************************************************************/

/* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
 *   BSP (Board Support Package)
 *   Target : Texas Instruments EZ430-RF2500
 *            "MSP430 Wireless Development Tool"
 *   Board definition file.
 * =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
 */

#ifndef BSP_BOARD_DEFS_H
#define BSP_BOARD_DEFS_H


/* ------------------------------------------------------------------------------------------------
 *                                     Board Unique Define
 * ------------------------------------------------------------------------------------------------
 */
#define BSP_BOARD_EZ430RF


/* ------------------------------------------------------------------------------------------------
 *                                           Mcu
 * ------------------------------------------------------------------------------------------------
 */
#include "mcus/bsp_msp430_defs.h"


/* ------------------------------------------------------------------------------------------------
 *                                          Clock
 * ------------------------------------------------------------------------------------------------
 */
#include "bsp_config.h"
#define __bsp_CLOCK_MHZ__    BSP_CONFIG_CLOCK_MHZ


/* ------------------------------------------------------------------------------------------------
 *                                     Board Initialization
 * ------------------------------------------------------------------------------------------------
 */
#define BSP_BOARD_C               "bsp_board.c"
#define BSP_INIT_BOARD()          BSP_InitBoard()
#define BSP_DELAY_USECS(x)        BSP_Delay(x)

void BSP_InitBoard(void);
void BSP_Delay(uint16_t usec);

/* ------------------------------------------------------------------------------------------------
 *                                      SPI Configuration
 * ------------------------------------------------------------------------------------------------
 */

/* SCLK Pin Configuration */
#define __BSP_SPI_SCLK_GPIO_BIT__            3
#define BSP_SPI_CONFIG_SCLK_PIN_AS_OUTPUT()  st( P3DIR |=  BV(__BSP_SPI_SCLK_GPIO_BIT__); )
#define BSP_SPI_DRIVE_SCLK_HIGH()            st( P3OUT |=  BV(__BSP_SPI_SCLK_GPIO_BIT__); )
#define BSP_SPI_DRIVE_SCLK_LOW()             st( P3OUT &= ~BV(__BSP_SPI_SCLK_GPIO_BIT__); )

/* SI Pin Configuration */
#define __BSP_SPI_SI_GPIO_BIT__              1
#define BSP_SPI_CONFIG_SI_PIN_AS_OUTPUT()    st( P3DIR |=  BV(__BSP_SPI_SI_GPIO_BIT__); )
#define BSP_SPI_DRIVE_SI_HIGH()              st( P3OUT |=  BV(__BSP_SPI_SI_GPIO_BIT__); )
#define BSP_SPI_DRIVE_SI_LOW()               st( P3OUT &= ~BV(__BSP_SPI_SI_GPIO_BIT__); )

/* SO Pin Configuration */
#define __BSP_SPI_SO_GPIO_BIT__              2
#define BSP_SPI_CONFIG_SO_PIN_AS_INPUT()     /* nothing to required */
#define BSP_SPI_SO_IS_HIGH()                 ( P3IN & BV(__BSP_SPI_SO_GPIO_BIT__) )

/* SPI Port Configuration - CLK, SI, SO are SPI, STE is GPIO */
#define BSP_SPI_CONFIG_PORT()                st( P3SEL |= BV(__BSP_SPI_SCLK_GPIO_BIT__) |  \
                                                          BV(__BSP_SPI_SI_GPIO_BIT__)   |  \
                                                          BV(__BSP_SPI_SO_GPIO_BIT__); )
/* read/write macros */
#define BSP_SPI_WRITE_BYTE(x)                st( IFG2 &= ~UCB0RXIFG;  UCB0TXBUF = x; )
#define BSP_SPI_READ_BYTE()                  UCB0RXBUF
#define BSP_SPI_WAIT_DONE()                  while(!(IFG2 & UCB0RXIFG));

/*
 *  SPI Specifications
 * -----------------------------------------------
 *    Max SPI Clock   :  10 MHz
 *    Data Order      :  MSB transmitted first
 *    Clock Polarity  :  low when idle
 *    Clock Phase     :  sample leading edge
 */

/* initialization macro */
// with UCSSEL1 set and UCB0BR0 is 2, bit rate is about 6kHz
#define BSP_SPI_INIT() \
st ( \
  UCB0CTL1 = UCSWRST;                           \
  UCB0CTL1 = UCSWRST | UCSSEL1;                 \
  UCB0CTL0 = UCCKPH | UCMSB | UCMST | UCSYNC;   \
  UCB0BR0  = 2;                                 \
  UCB0BR1  = 0;                                 \
  BSP_SPI_CONFIG_PORT();                        \
  UCB0CTL1 &= ~UCSWRST;                         \
)

#define BSP_SPI_IS_INITIALIZED()         (UCB0CTL0 & UCMST)

#define BSP_SPI_READ_BIT    0x80
#define BSP_SPI_BURST_BIT   0x40
#define BSP_SPI_DUMMY_BYTE  0xDB


/* ************************************************************************************************
 *                                   Compile Time Integrity Checks
 * ************************************************************************************************
 */
#if (defined __IAR_SYSTEMS_ICC__) && (__VER__ >= 342)
#if (!defined __MSP430F2274__)
#error "ERROR: Mismatch between specified board and selected microcontroller."
#endif
#endif


/**************************************************************************************************
 */
#endif
