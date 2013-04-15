/** @file */
//******************************************************************************
// THIS PROGRAM IS PROVIDED "AS IS". TI MAKES NO WARRANTIES OR
// REPRESENTATIONS, EITHER EXPRESS, IMPLIED OR STATUTORY,
// INCLUDING ANY IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS
// FOR A PARTICULAR PURPOSE, LACK OF VIRUSES, ACCURACY OR
// COMPLETENESS OF RESPONSES, RESULTS AND LACK OF NEGLIGENCE.
// TI DISCLAIMS ANY WARRANTY OF TITLE, QUIET ENJOYMENT, QUIET
// POSSESSION, AND NON-INFRINGEMENT OF ANY THIRD PARTY
// INTELLECTUAL PROPERTY RIGHTS WITH REGARD TO THE PROGRAM OR
// YOUR USE OF THE PROGRAM.
//
// IN NO EVENT SHALL TI BE LIABLE FOR ANY SPECIAL, INCIDENTAL,
// CONSEQUENTIAL OR INDIRECT DAMAGES, HOWEVER CAUSED, ON ANY
// THEORY OF LIABILITY AND WHETHER OR NOT TI HAS BEEN ADVISED
// OF THE POSSIBILITY OF SUCH DAMAGES, ARISING IN ANY WAY OUT
// OF THIS AGREEMENT, THE PROGRAM, OR YOUR USE OF THE PROGRAM.
// EXCLUDED DAMAGES INCLUDE, BUT ARE NOT LIMITED TO, COST OF
// REMOVAL OR REINSTALLATION, COMPUTER TIME, LABOR COSTS, LOSS
// OF GOODWILL, LOSS OF PROFITS, LOSS OF SAVINGS, OR LOSS OF
// USE OR INTERRUPTION OF BUSINESS. IN NO EVENT WILL TI'S
// AGGREGATE LIABILITY UNDER THIS AGREEMENT OR ARISING OUT OF
// YOUR USE OF THE PROGRAM EXCEED FIVE HUNDRED DOLLARS
// (U.S.$500).
//
// Unless otherwise stated, the Program written and copyrighted
// by Texas Instruments is distributed as "freeware".  You may,
// only under TI's copyright in the Program, use and modify the
// Program without any charge or restriction.  You may
// distribute to third parties, provided that you transfer a
// copy of this license to the third party and the third party
// agrees to these terms by its first use of the Program. You
// must reproduce the copyright notice and any other legend of
// ownership on each copy or partial copy, of the Program.
//
// You acknowledge and agree that the Program contains
// copyrighted material, trade secrets and other TI proprietary
// information and is protected by copyright laws,
// international copyright treaties, and trade secret laws, as
// well as other intellectual property laws.  To protect TI's
// rights in the Program, you agree not to decompile, reverse
// engineer, disassemble or otherwise translate any object code
// versions of the Program to a human-readable form.  You agree
// that in no event will you alter, remove or destroy any
// copyright notice included in the Program.  TI reserves all
// rights not specifically granted under this license. Except
// as specifically provided herein, nothing in this agreement
// shall be construed as conferring by implication, estoppel,
// or otherwise, upon you, any license or other right under any
// TI patents, copyrights or trade secrets.
//
// You may not use the Program in non-TI devices.
//
//******************************************************************************
//   eZ430-RF2500 Temperature Sensor End Device
//
//   Description: This is the End Device software for the eZ430-2500RF
//                Temperature Sensing demo
//
//
//   Z. Shivers
//   Version    1.05
//   Texas Instruments, Inc
//   July 2010
//   Known working builds:
//     IAR Embedded Workbench Kickstart (Version: 5.10.4)
//     Code Composer Studio (Version 4.1.2.00027)
//******************************************************************************
//Change Log:
//******************************************************************************
//Version:  1.05
//Comments: Added support for various baud rates dependent on CPU frequencies
//Version:  1.04
//Comments: Added support for SimpliciTI 1.1.1
//          Moved radio wakeup in linkTo() to after ADC code to save power
//          Replaced delays with __delay_cylces() instrinsic
//          Replaced toggleLED with BSP functions
//          Added more comments
//Version:  1.03
//Comments: Added support for SimpliciTI 1.1.0
//          Added support for Code Composer Studio
//          Added security (Enabled with -DSMPL_SECURE in smpl_nwk_config.dat)
//          Added acknowledgement (Enabled with -DAPP_AUTO_ACK in smpl_nwk_config.dat)
//          Based the modifications on the AP_as_Data_Hub example code
//Version:  1.02
//Comments: Changed Port toggling to abstract method
//          Fixed comment typos
//Version:  1.01
//Comments: Added support for SimpliciTI 1.0.3
//          Added Flash storage/check of Random address
//          Moved LED toggle to HAL
//Version:  1.00
//Comments: Initial Release Version
//******************************************************************************
#include <string.h>
#include "bsp.h"
#include "mrfi.h"
#include "nwk_types.h"
#include "nwk_globals.h"
#include "nwk_api.h"
#include "bsp_leds.h"
#include "bsp_buttons.h"
#include "vlo_rand.h"
#include "accel_spi.h"
//#include <ti/mcu/msp430/csl/CSL.h>

/*------------------------------------------------------------------------------
 * Defines
 *----------------------------------------------------------------------------*/
#define TRANSMIT_PERIOD_SECS 1	/* Number of seconds between packets in a burst */
#define MEASURE_GAP_SECS 15		/* Number of seconds between measurements */
#define NUM_PKTS_PER_AXIS 3		/* Number of packets to transmit for each axis (determines buffer size, max 7) */

#define APP_HEADER_LEN 4		/* Application header length */
#define MISSES_IN_A_ROW  5		/* How many times to try a TX and miss an acknowledge before doing a scan */

#define APP_PAYLOAD_LEN (MAX_APP_PAYLOAD-APP_HEADER_LEN)		/* Payload length */
#define ACCEL_BUFFER_LEN (NUM_PKTS_PER_AXIS * APP_PAYLOAD_LEN)	/* Size of sample buffer */

/* Message types */
#define MSG_TYPE_ACCEL_SPECTRA 0

/*------------------------------------------------------------------------------
 * Prototypes
 *----------------------------------------------------------------------------*/
static void init(void);
static void run(void);
static void selfMeasure(void);
static void sendMessage(uint8_t axis, uint8_t *results);
void buildPayload(mrfiPacket_t *mrfiPkt, uint8_t *msg, uint8_t len);
static void sendPacket(mrfiPacket_t *mrfiPkt, int len);
__interrupt void TimerA_ISR (void);
__interrupt void Port2_ISR (void);

/*------------------------------------------------------------------------------
* Globals
------------------------------------------------------------------------------*/
/* Temperature offset set at production */
volatile int * tempOffset = (int *)0x10F4;
/* Initialize radio address location */
char * Flash_Addr = (char *)0x10F0;
/* Work loop semaphores */
static volatile uint8_t sSelfMeasureSem = 0;
/* Accelerometer alarm interrupt flag */
static volatile uint8_t sAccelAlarm = 0;
/* Keeps track of missed acknowledgements across calls to selfMeasure() */
uint8_t missedAcks = 0;

/*------------------------------------------------------------------------------
 * Main
 *----------------------------------------------------------------------------*/
void main (void)
{
  /* Initialize board, radio, other peripherals and simpliciti
   */
  init();

  /* Start sample/transmit loop */
  run();
  // does not return
}

static void init()
{
// FLASH is unused between 0xad73 (end of .const) and 0xffe6 (start of int table) - about 20KB
// this is subject to link conditions

  /* Read out address from flash (hard-coded) */
  addr_t const *myaddr = nwk_getMyAddress();;

  /* Initialize board-specific hardware */
  // set chip selects for all SPI devices to inactive state
  MRFI_SPI_CONFIG_CSN_PIN_AS_OUTPUT();
  MRFI_SPI_DRIVE_CSN_HIGH();
  ACCEL_SPI_CONFIG_CSN_PIN_AS_OUTPUT();
  ACCEL_SPI_DRIVE_CSN_HIGH();
  BSP_Init();

  /* Make sure the radio is asleep */
  MRFI_Init();
  MRFI_Sleep();

  /* Set low frequency clock to VLO - drives ACLK (12KHz) */
  BCSCTL3 |= LFXT1S_2;                      // LFXT1 = VLO

  /* Complete initialization of TimerA */
  TACCTL0 = CCIE;                           // TACCR0 interrupt enabled
  TACCR0 = 12000;                           // ~ 1 sec
  TACTL = TASSEL_1 + MC_1;                  // ACLK, upmode

  /* BEGIN USER INITIALIZATION HERE */

  /* PORT USAGE:
   *
   * Port 1 is used by the board for LEDs and the button.
   * No pins are available to user code.
   *
   * Pins 2.0-2.4 are available to user app, but BE SURE not
   * to interfere with 2.6 and 2.7 which are used for the radio.
   *
   * Port 3 is mainly used for the SPI to the radio and any digital sensors.
   * The AP uses 3.4 and 3.5 for USB.  These can be used by the ED.
   *
   * Port 4 pins 4.3 through 4.6 are available to user code. All others are NC.
   * This port is not used by SimpliciTI for any purpose so there is no
   * possibility of conflict.
   */

   accelInit();
}

static void run()
{
  while (1)
  {
    /* Go to sleep, waiting for interrupt every second */
    __bis_SR_register(LPM3_bits);

    BSP_TURN_OFF_LED2();
    BSP_TURN_ON_LED1();
    BSP_DELAY_USECS(10000);
    BSP_TURN_OFF_LED1();

	/* Time to measure */
    if (sSelfMeasureSem >= MEASURE_GAP_SECS) {
      selfMeasure();
      sSelfMeasureSem = 0;
    }
  }
}

static void selfMeasure(void)
{
  uint8_t results[ACCEL_BUFFER_LEN];

  accelSpiWriteReg(DATA_FORMAT_ADDR, 0x80); // fixed 10 bit mode, range = +-2g, self-test

  /* Measure X */
  accelSpiReadDataBytes2(DATAX0_ADDR, results, ACCEL_BUFFER_LEN);
  sendMessage(0, results);

  /* Measure Y */
//  accelSpiReadDataBytes2(DATAY0_ADDR, results, ACCEL_BUFFER_LEN);
//  sendMessage(1, results);

  /* Measure Z */
//  accelSpiReadDataBytes2(DATAZ0_ADDR, results, ACCEL_BUFFER_LEN);
//  sendMessage(2, results);
}

static void sendMessage(uint8_t axis, uint8_t *results)
{
  uint8_t seqno = 1;
  int i;
  uint8_t msg[MAX_APP_PAYLOAD];
  mrfiPacket_t mrfiPkt;

  /* message format
	   -------------------------------------------------------------
	  | message type | missed acks | axis | sequence number |  data |
	   -------------------------------------------------------------
	          0             1          2           3           4-49
   */

  for (i = 0; i < NUM_PKTS_PER_AXIS; i++) {
    /* Go to sleep, waiting for interrupt */
    __bis_SR_register(LPM3_bits);

    BSP_TURN_OFF_LED1();

    if (sSelfMeasureSem >= TRANSMIT_PERIOD_SECS) {
      BSP_TURN_ON_LED2();
      sSelfMeasureSem = 0;

      msg[0] = MSG_TYPE_ACCEL_SPECTRA;
      msg[1] = 0;  // this will be set in sendWithAckReq() when APP_AUTO_ACK is TRUE and an ack is requested
      msg[2] = axis;
      msg[3] = seqno++;

      memcpy((char *) &msg[4], (char *) &results[i*APP_PAYLOAD_LEN], APP_PAYLOAD_LEN);

      buildPayload(&mrfiPkt, msg, sizeof(msg));
      sendPacket(&mrfiPkt, MAX_APP_PAYLOAD);

      BSP_TURN_OFF_LED2();
    }
  }
}


static addr_t const *sMyAddr = NULL;

void buildPayload(mrfiPacket_t *mrfiPkt, uint8_t *msg, uint8_t len)
{
  MRFI_SET_PAYLOAD_LEN(mrfiPkt, len);
  memcpy(MRFI_P_PAYLOAD(mrfiPkt), msg, len);
  memcpy(MRFI_P_SRC_ADDR(mrfiPkt), sMyAddr, MRFI_ADDR_SIZE);
}

void sendPacket(mrfiPacket_t *mrfiPkt, int len)
{
  /* Get radio ready...awakens in idle state */
  MRFI_WakeUp();

  /* Send the message */
  if (MRFI_Transmit(mrfiPkt, MRFI_TX_TYPE_CCA)) {
    BSP_TURN_ON_LED1();
  }

  BSP_TURN_OFF_LED2();

  /* Put radio back to sleep */
  MRFI_RxIdle();
  MRFI_Sleep();
}


/*------------------------------------------------------------------------------
 * Timer A0 interrupt service routine
 *----------------------------------------------------------------------------*/
#pragma vector=TIMERA0_VECTOR
__interrupt void TimerA_ISR (void)
{
  sSelfMeasureSem++;
  __bic_SR_register_on_exit(LPM3_bits);        // Clear LPM3 bit from 0(SR)
}

/*------------------------------------------------------------------------------
 * Accelerometer and radio interrupt service routine
 *----------------------------------------------------------------------------*/
void MRFI_GpioIsr(void); /* defined in mrfi_radio.c */
#pragma vector=PORT2_VECTOR
__interrupt void Port2_ISR (void)
{
  uint8_t flags = P2IFG, result = 0;

  // radio sync
  if (P2IFG & BIT6) {
    MRFI_GpioIsr();
  }

  // accelerometer alarm
  if (P2IFG & BIT1) {
    result = accelSpiReadReg(INT_SOURCE_ADDR);
    if (result & 0x10) {
        sAccelAlarm++;
    }
    P2IFG &= ~BIT1;
    accelSpiReadReg(INT_SOURCE_ADDR);
  }

  __bic_SR_register_on_exit(LPM3_bits);        // Clear LPM3 bit from 0(SR)
}
