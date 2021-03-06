//#define TIMER

#include <stdlib.h>
#include <string.h>

#include "bsp.h"
#include "mrfi.h"
#include "bsp_leds.h"
#include "bsp_buttons.h"
#include "vlo_rand.h"

/*------------------------------------------------------------------------------
 * Prototypes
 *----------------------------------------------------------------------------*/
static void sampleAndSend(void);
static void takeSample(uint8_t *msg);
void buildPayload(mrfiPacket_t *mrfiPkt, uint8_t *msg, uint8_t len);
__interrupt void ADC10_ISR(void);
__interrupt void Timer_A (void);

/*------------------------------------------------------------------------------
* Globals
------------------------------------------------------------------------------*/
/* Temperature offset set at production */
volatile int * tempOffset = (int *)0x10F4;
/* Work loop semaphores - start with a sample */
static volatile uint8_t sSelfMeasureSem = 1;

#define PORT_4_SEL 0
#define PORT_4_DIR 0xff
#define PORT_4_IES 0
#define PORT_4_IE  0
#define PORT_4_OUT 0

/*------------------------------------------------------------------------------
 * Main
 *----------------------------------------------------------------------------*/
void main (void)
{
  /* Initialize board-specific hardware */
  BSP_Init();

  P4SEL = 0;
  P4OUT = 0;
  P4DIR = 0xff;
  P4REN = 0;

  /* Turn off LEDs. */
  BSP_TURN_OFF_LED1();
  BSP_TURN_OFF_LED2();

  /* Make sure the radio is asleep */
  MRFI_Init();
  MRFI_Sleep();

  /* Initialize TimerA and oscillator */
  BCSCTL3 |= LFXT1S_2;                      // LFXT1 = VLO
  TACCTL0 = CCIE;                           // TACCR0 interrupt enabled
  TACCR0 = 12000;                           // ~ 1 sec
  TACTL = TASSEL_1 + MC_1;                  // ACLK, upmode

  sampleAndSend();

  /* not reached */
  while(1);
}

static void sampleAndSend()
{
  uint8_t msg[3];
  mrfiPacket_t mrfiPkt;

  MRFI_WakeUp();

  while (1)
  {
#ifdef TIMER
    /* Time to measure */
    if (sSelfMeasureSem) {
#endif

      BSP_TURN_ON_LED2();

      P4OUT |= BIT3;

      takeSample(msg);

      P4OUT &= ~BIT3;

      buildPayload(&mrfiPkt, msg, sizeof(msg));

      P4OUT |= BIT3;

#ifdef TIMER
      /* Get radio ready...awakens in idle state */
      MRFI_WakeUp();
#endif

      P4OUT &= ~BIT3;

      /* Send the message */
      if (MRFI_Transmit(&mrfiPkt, MRFI_TX_TYPE_CCA)) {
        BSP_TURN_ON_LED1();
      }

      P4OUT |= BIT3;

      BSP_TURN_OFF_LED2();

#ifdef TIMER
      /* Put radio back to sleep */
      MRFI_RxIdle();
      MRFI_Sleep();

      /* Done with measurement, disable measure flag */
      sSelfMeasureSem = 0;
#endif

      P4OUT &= ~BIT3;

#ifdef TIMER
      /* Go to sleep, waiting for interrupt every second to acquire data */
      __bis_SR_register(LPM3_bits+GIE);
    }
#endif
  }
}

static void takeSample(uint8_t *msg)
{
  volatile long temp;
  int degC, volt;
  int results[2];

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

  /* message format,  UB = upper Byte, LB = lower Byte
  -------------------------------
  |degC LB | degC UB |  volt LB |
  -------------------------------
     0         1          2
  */
  temp = results[1];
  volt = (temp*25)/512;
  msg[0] = degC&0xFF;
  msg[1] = (degC>>8)&0xFF;
  msg[2] = volt;
}

typedef struct
{
  uint8_t  addr[MRFI_ADDR_SIZE];
} addr_t;

static addr_t const *sMyAddr = NULL;

void buildPayload(mrfiPacket_t *mrfiPkt, uint8_t *msg, uint8_t len)
{
  MRFI_SET_PAYLOAD_LEN(mrfiPkt, len);
  memcpy(MRFI_P_PAYLOAD(mrfiPkt), msg, len);
  memcpy(MRFI_P_SRC_ADDR(mrfiPkt), sMyAddr, MRFI_ADDR_SIZE);

  return;
}

/*------------------------------------------------------------------------------
 * ADC10 interrupt service routine
 *----------------------------------------------------------------------------*/
#pragma vector=ADC10_VECTOR
__interrupt void ADC10_ISR(void)
{
  __bic_SR_register_on_exit(CPUOFF);        // Clear CPUOFF bit from 0(SR)
}

#ifdef TIMER
/*------------------------------------------------------------------------------
 * Timer A0 interrupt service routine
 *----------------------------------------------------------------------------*/
#pragma vector=TIMERA0_VECTOR
__interrupt void Timer_A (void)
{
  sSelfMeasureSem = 1;
  __bic_SR_register_on_exit(LPM3_bits);        // Clear LPM3 bit from 0(SR)
}
#endif

void MRFI_RxCompleteISR()
{
  return;
}
