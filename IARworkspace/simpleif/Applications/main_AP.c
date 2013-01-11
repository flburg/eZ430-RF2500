
#include <string.h>
#include "bsp.h"
#include "mrfi.h"
#include "bsp_leds.h"
#include "bsp_buttons.h"
#include "nwk_types.h"
#include "nwk_api.h"
#include "nwk_frame.h"
#include "nwk.h"
#include "virtual_com_cmds.h"

/*------------------------------------------------------------------------------
 * Prototypes
 *----------------------------------------------------------------------------*/
void takeSample(char*);
__interrupt void ADC10_ISR(void);
__interrupt void Timer_A (void);
void MRFI_RxCompleteISR();

/*------------------------------------------------------------------------------
 * Globals
 *----------------------------------------------------------------------------*/

/* work loop semaphores */
static volatile uint8_t sPktSem = 0;
static volatile uint8_t sSelfMeasureSem = 0;

/* data for terminal output */
const char splash[] = {"\r\n--------------------------------------------------  \r\n     ****\r\n     ****           eZ430-RF2500\r\n     ******o****    Temperature Sensor Network\r\n********_///_****   Copyright 2009\r\n ******/_//_/*****  Texas Instruments Incorporated\r\n  ** ***(__/*****   All rights reserved.\r\n      *********     SimpliciTI1.1.1\r\n       *****\r\n        ***\r\n--------------------------------------------------\r\n"};
volatile int * tempOffset = (int *)0x10F4;

/*------------------------------------------------------------------------------
 * Main
 *----------------------------------------------------------------------------*/
void main (void)
{
//  bspIState_t intState;

  /* Initialize board */
  BSP_Init();

  /* Initialize TimerA and oscillator */
  BCSCTL3 |= LFXT1S_2;                      // LFXT1 = VLO
  TACCTL0 = CCIE;                           // TACCR0 interrupt enabled
  TACCR0 = 12000;                           // ~1 second
  TACTL = TASSEL_1 + MC_1;                  // ACLK, upmode

  /* Initialize serial port */
  COM_Init();

  //Transmit splash screen and network init notification
  TXString( (char*)splash, sizeof splash);
  TXString( "\r\nInitializing Network....", 26 );

  /* Make sure the radio is receiving */
  MRFI_Init();
  MRFI_WakeUp();
  MRFI_RxOn();

  // network initialized
  TXString( "Done\r\n", 6);

  /* Turn off LEDs. */
  BSP_TURN_OFF_LED1();
  BSP_TURN_OFF_LED2();

  /* main work loop */
  while (1)
  {
    /* Have we received a packet ?
     * No critical section -- it doesn't really matter much if we miss a poll
     */
    if (sPktSem)
    {
      mrfiPacket_t mrfiPkt;
      char msg[6];

      BSP_TOGGLE_LED2();

      MRFI_Receive(&mrfiPkt);

      memcpy(msg, MRFI_P_PAYLOAD(&mrfiPkt), 3);

      /* Send payload over serial port */
      transmitData(1, 0, msg);

      --sPktSem;
    }

    // if it is time to measure our own temperature...
    if(sSelfMeasureSem)
    {
      char msg[6];
      char addr[] = {"HUB0"};
      char rssi[] = {"000"};

      takeSample(msg);

      /* Send sample over serial port */
      transmitDataString(1, addr, rssi, msg );

      /* Done with measurement, disable measure flag */
      sSelfMeasureSem = 0;
    }
  }
}

void takeSample(char *msg)
{
      int degC, volt;
      volatile long temp;
      int results[2];

      BSP_TOGGLE_LED1();

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

      /* Stop and turn off ADC */
      ADC10CTL0 &= ~ENC;
      ADC10CTL0 &= ~(REFON + ADC10ON);

      /* oC = ((A10/1024)*1500mV)-986mV)*1/3.55mV = A10*423/1024 - 278
       * the temperature is transmitted as an integer where 32.1 = 321
       * hence 4230 instead of 423
       */
      temp = results[0];
      degC = ((temp - 673) * 4230) / 1024;
      if( (*tempOffset) != 0xFFFF )
      {
        degC += (*tempOffset);
      }

      temp = results[1];
      volt = (temp*25)/512;

      /* Package up the data */
      msg[0] = degC&0xFF;
      msg[1] = (degC>>8)&0xFF;
      msg[2] = volt;
}

/*------------------------------------------------------------------------------
* ADC10 interrupt service routine
------------------------------------------------------------------------------*/
#pragma vector=ADC10_VECTOR
__interrupt void ADC10_ISR(void)
{
  __bic_SR_register_on_exit(CPUOFF);        // Clear CPUOFF bit from 0(SR)
}

/*------------------------------------------------------------------------------
* Timer A0 interrupt service routine
------------------------------------------------------------------------------*/
#pragma vector=TIMERA0_VECTOR
__interrupt void Timer_A (void)
{
  sSelfMeasureSem = 1;
}

/*------------------------------------------------------------------------------
* Radio Rx sync interrupt service routine
------------------------------------------------------------------------------*/
void MRFI_RxCompleteISR()
{
  sPktSem++;
}

//    if (BSP_BUTTON1())
//    {
//      __delay_cycles(2000000);  /* debounce (0.25 seconds) */
//      changeChannel();
//    }

//#pragma vector=PORT2_VECTOR
//__interrupt void Port2_ISR(void)
//{
//  MRFI_GpioIsr();
//}

