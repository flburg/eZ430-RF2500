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
#include <ti/mcu/msp430/csl/CSL.h>

/*------------------------------------------------------------------------------
 * Defines
 *----------------------------------------------------------------------------*/
/* How many times to try a TX and miss an acknowledge before doing a scan */
#define MISSES_IN_A_ROW  5
/* Number of seconds between transmissions */
#define TRANSMIT_PERIOD_SECS 1

/*------------------------------------------------------------------------------
 * Prototypes
 *----------------------------------------------------------------------------*/
static void init(void);
static void join(void);
static void link(void);
static void run(void);
static void selfMeasure(uint32_t seqno);
static smplStatus_t sendPacket(uint8_t *msg, int len, int ackreq);
static smplStatus_t sendBestEffort(uint8_t *mag, int len);
#ifdef APP_AUTO_ACK
static smplStatus_t sendWithAckReq(uint8_t *mag, int len);
#endif
void createRandomAddress(void);
__interrupt void ADC10_ISR(void);
__interrupt void TimerA_ISR (void);
__interrupt void Port2_ISR (void);

/*------------------------------------------------------------------------------
* Globals
------------------------------------------------------------------------------*/
static linkID_t sLinkID1 = 0;
/* Temperature offset set at production */
volatile int * tempOffset = (int *)0x10F4;
/* Initialize radio address location */
char * Flash_Addr = (char *)0x10F0;
/* Work loop semaphores */
static volatile uint8_t sSelfMeasureSem = 0;
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

  /* Keep trying to join (a side effect of successful initialization) until
   * successful. Toggle LEDS to indicate that joining has not occurred.
   */
  join();

  /* Unconditional link to AP which is listening due to successful join. */
  link();

  /* Start sample/transmit loop */
  run();
  // does not return
}

static void init()
{
  /* Read out address from flash (hard-coded) */
  addr_t const *myaddr = nwk_getMyAddress();;

  /* Initialize board-specific hardware */
  // set chip selects for all SPI devices to inactive state
  MRFI_SPI_CONFIG_CSN_PIN_AS_OUTPUT();
  MRFI_SPI_DRIVE_CSN_HIGH();
  ACCEL_SPI_CONFIG_CSN_PIN_AS_OUTPUT();
  ACCEL_SPI_DRIVE_CSN_HIGH();
  BSP_Init();

  /* Tell network stack the device address */
  SMPL_Ioctl(IOCTL_OBJ_ADDR, IOCTL_ACT_SET, (void *) myaddr);

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
}

static void join()
{
  while (SMPL_SUCCESS != SMPL_Init(0))
  {
    BSP_TOGGLE_LED1();
    BSP_TOGGLE_LED2();
    /* Go to sleep (LPM3 with interrupts enabled)
     * Timer A0 interrupt will wake CPU up every second to retry initializing
     */
    __bis_SR_register(LPM3_bits+GIE);  // LPM3 with interrupts enabled
  }

  /* LEDs on solid to indicate successful join. */
  BSP_TURN_ON_LED1();
  BSP_TURN_ON_LED2();
}

static void link()
{
  /* Keep trying to link... */
  while (SMPL_SUCCESS != SMPL_Link(&sLinkID1))
  {
    BSP_TOGGLE_LED1();
    BSP_TOGGLE_LED2();
    /* Go to sleep (LPM3 with interrupts enabled)
     * Timer A0 interrupt will wake CPU up every second to retry linking
     */
    __bis_SR_register(LPM3_bits+GIE);
  }

  /* Turn off LEDs. */
  BSP_TURN_OFF_LED1();
  BSP_TURN_OFF_LED2();

  /* Put the radio to sleep */
  SMPL_Ioctl(IOCTL_OBJ_RADIO, IOCTL_ACT_RADIO_SLEEP, 0);
}

static void run()
{
  uint32_t seqno = 1;

  while (1)
  {
    /* Go to sleep, waiting for interrupt every second */
    __bis_SR_register(LPM3_bits);

    /* Time to measure */
    if (sSelfMeasureSem >= TRANSMIT_PERIOD_SECS) {
      selfMeasure(seqno++);
    }
  }
}

static void selfMeasure(uint32_t seqno)
{
  uint8_t msg[9];
  volatile long resval;
  int degC, volt, pressure;
  int results[3];

  /* Get temperature */
  ADC10CTL1 = INCH_10 + ADC10DIV_4;       // Temp Sensor ADC10CLK/5
  ADC10CTL0 = SREF_1 + ADC10SHT_3 + REFON + ADC10ON + ADC10IE + ADC10SR;
  /* Allow ref voltage to settle for at least 30us (30us * 8MHz = 240 cycles)
   * See SLAS504D for settling time spec
   */
  __delay_cycles(240);
  ADC10CTL0 |= ENC + ADC10SC;             // Sampling and conversion start
  __bis_SR_register(CPUOFF + GIE);        // LPM0 with interrupts enabled
  results[0] = ADC10MEM;                  // Retrieve result
  ADC10CTL0 &= ~ENC;

  /* Get voltage */
  ADC10CTL1 = INCH_11;                     // AVcc/2
  ADC10CTL0 = SREF_1 + ADC10SHT_2 + REFON + ADC10ON + ADC10IE + REF2_5V;
  __delay_cycles(240);
  ADC10CTL0 |= ENC + ADC10SC;             // Sampling and conversion start
  __bis_SR_register(CPUOFF + GIE);        // LPM0 with interrupts enabled
  results[1] = ADC10MEM;                  // Retrieve result
  ADC10CTL0 &= ~ENC;

  /* Get pressure */
  ADC10CTL1 = INCH_0;                     // A0 (P2.0)
  ADC10CTL0 = SREF_0 + ADC10SHT_2 + ADC10SR + ADC10ON + ADC10IE;
  ADC10AE0 = 0x1;
  __delay_cycles(240);
  ADC10CTL0 |= ENC + ADC10SC;             // Sampling and conversion start
  __bis_SR_register(CPUOFF + GIE);        // LPM0 with interrupts enabled
  results[2] = ADC10MEM;                  // Retrieve result

  /* Stop and turn off ADC */
  ADC10CTL0 &= ~ENC;
  ADC10CTL0 &= ~(REFON + ADC10ON);

  /* oC = ((A10/1024)*1500mV)-986mV)*1/3.55mV = A10*423/1024 - 278
   * the temperature is transmitted as an integer where 32.1 = 321
   * hence 4230 instead of 423
   */
  resval = results[0];
  degC = ((resval - 673) * 4230) / 1024;
  if( (*tempOffset) != 0xFFFF )
  {
    degC += (*tempOffset);
  }

  // send raw voltage for higher precision
  volt = results[1];
//  resval = results[1];
//  volt = (resval*25)/512;

  pressure = results[2];

  /* message format
   --------------------------------------------------------------------------
  | degC LSB,MSB | volt LSB,MSB | press LSB,MSB | seqno LSB,MSB | missedAcks |
   --------------------------------------------------------------------------
         0,1           2,3            4,5             6,7             8
  */

  msg[0] = degC & 0xFF;
  msg[1] = (degC >> 8) & 0xFF;
  msg[2] = volt & 0xFF;
  msg[3] = (volt >> 8) & 0xFF;
  msg[4] = pressure & 0xFF;
  msg[5] = (pressure >> 8) & 0x3;
  msg[6] = seqno & 0xFF;
  msg[7] = (seqno >> 8) & 0xFF;
  msg[8] = 0;  // this is also set below when APP_AUTO_ACK is TRUE and an ack is requested

  sendPacket(msg, sizeof(msg), 0);
}

static smplStatus_t sendPacket(uint8_t *msg, int len, int ackflag)
{
#ifdef APP_AUTO_ACK
  smplStatus_t retval;

  if (ackflag) {
    retval = sendWithAckReq(msg, len);
  } else {
    retval = sendBestEffort(msg, len);
  }

  return retval;
#else
  return sendBestEffort(msg, len);
#endif
}

static smplStatus_t sendBestEffort(uint8_t *msg, int len)
{
  smplStatus_t rc;

  /* Get radio ready...awakens in idle state */
  SMPL_Ioctl( IOCTL_OBJ_RADIO, IOCTL_ACT_RADIO_AWAKE, 0);

  /* No AP acknowledgement, just send a single message to the AP */
  rc = SMPL_SendOpt(sLinkID1, msg, len, SMPL_TXOPTION_NONE);

  /* Put radio back to sleep */
  SMPL_Ioctl( IOCTL_OBJ_RADIO, IOCTL_ACT_RADIO_SLEEP, 0);

  /* Done with measurement, disable measure flag */
  sSelfMeasureSem = 0;

  return rc;
}

#ifdef APP_AUTO_ACK
static smplStatus_t sendWithAckReq(uint8_t *msg, int len)
{
  uint8_t misses, done;
  uint8_t noAck;
  smplStatus_t rc;

  /* Get radio ready...awakens in idle state */
  SMPL_Ioctl( IOCTL_OBJ_RADIO, IOCTL_ACT_RADIO_AWAKE, 0);

  /* Request that the AP sends an ACK back to confirm data transmission
   * Note: Enabling this section more than DOUBLES the current consumption
   *       due to the amount of time IN RX waiting for the AP to respond
   */
  done = 0;
  while (!done)
  {
    noAck = 0;

    /* Try sending message MISSES_IN_A_ROW times looking for ack */
    for (misses=0; misses < MISSES_IN_A_ROW; ++misses)
    {
      /* missedAcks is (MISSES_IN_A_ROW * {0...n}) + noAck
       * MISSES_IN_A_ROW happens when a transmit completely fails
       * (code gives up until next selfMeasureSem).
       */
      msg[8] = missedAcks;
      if (SMPL_SUCCESS == (rc = SMPL_SendOpt(sLinkID1, msg, len, SMPL_TXOPTION_ACKREQ)))
      {
        /* Message acked. We're done. Toggle LED 1 to indicate ack received. */
//        BSP_TOGGLE_LED1();
        BSP_TURN_ON_LED1();
        missedAcks = 0;
        __delay_cycles(2000);
//        BSP_TURN_OFF_LED1();
        break;
      }
      if (SMPL_NO_ACK == rc)
      {
        BSP_TOGGLE_LED2();
        BSP_TURN_ON_LED2();
        __delay_cycles(10000);
//        BSP_TURN_OFF_LED2();
        /* Count ack failures. Could also fail becuase of CCA and
         * we don't want to scan in this case.
         */
        noAck++;
        missedAcks++;
      }
    }

    if (MISSES_IN_A_ROW == noAck)
    {
      /* Message not acked */
//      BSP_TURN_ON_LED2();
      __delay_cycles(2000);
//      BSP_TURN_OFF_LED2();
#ifdef FREQUENCY_AGILITY
      /* Assume we're on the wrong channel so look for channel by
       * using the Ping to initiate a scan when it gets no reply. With
       * a successful ping try sending the message again. Otherwise,
       * for any error we get we will wait until the next button
       * press to try again.
       */
      if (SMPL_SUCCESS != SMPL_Ping(sLinkID1))
      {
        done = 1;
      }
#else
      done = 1;
#endif  /* FREQUENCY_AGILITY */
    }
    else
    {
      /* Got the ack or we don't care. We're done. */
      done = 1;
    }
  }

  /* Put radio back to sleep */
  SMPL_Ioctl( IOCTL_OBJ_RADIO, IOCTL_ACT_RADIO_SLEEP, 0);

  /* Done with measurement, disable measure flag */
  sSelfMeasureSem = 0;

  return rc;
}
#endif /* APP_AUTO_ACK */

void createRandomAddress()
{
  unsigned int rand, rand2;
  do
  {
    rand = TI_getRandomIntegerFromVLO();    // first byte can not be 0x00 of 0xFF
  }
  while( (rand & 0xFF00)==0xFF00 || (rand & 0xFF00)==0x0000 );
  rand2 = TI_getRandomIntegerFromVLO();

  BCSCTL1 = CALBC1_1MHZ;                    // Set DCO to 1MHz
  DCOCTL = CALDCO_1MHZ;
  FCTL2 = FWKEY + FSSEL0 + FN1;             // MCLK/3 for Flash Timing Generator
  FCTL3 = FWKEY + LOCKA;                    // Clear LOCK & LOCKA bits
  FCTL1 = FWKEY + WRT;                      // Set WRT bit for write operation

  Flash_Addr[0]=(rand>>8) & 0xFF;
  Flash_Addr[1]=rand & 0xFF;
  Flash_Addr[2]=(rand2>>8) & 0xFF;
  Flash_Addr[3]=rand2 & 0xFF;

  FCTL1 = FWKEY;                            // Clear WRT bit
  FCTL3 = FWKEY + LOCKA + LOCK;             // Set LOCK & LOCKA bit
}

/*------------------------------------------------------------------------------
 * ADC10 interrupt service routine
 *----------------------------------------------------------------------------*/
#pragma vector=ADC10_VECTOR
__interrupt void ADC10_ISR(void)
{
  __bic_SR_register_on_exit(CPUOFF);        // Clear CPUOFF bit from 0(SR)
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
 * Accelerometer interrupt service routine
 *----------------------------------------------------------------------------*/
void MRFI_GpioIsr(void); /* defined in mrfi_radio.c */
#pragma vector=PORT2_VECTOR
__interrupt void Port2_ISR (void)
{
  uint8_t flags = P2IFG;

  // radio sync
  if (P2IFG & BIT6) {
    MRFI_GpioIsr();
  }

  __bic_SR_register_on_exit(LPM3_bits);        // Clear LPM3 bit from 0(SR)
}
