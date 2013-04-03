/** @file */
/*
 * flash.c
 *
 *  Created on: Mar 7, 2013
 *      Author: flb
 */

#include "bsp.h"

#ifndef ACCESS_POINT

#include "flash.h"

void flashtest(void);

#define ROOT_ADDR 0x8000

#define BLOCK_SIZE 64
#define SEG_SIZE 512
#define NUM_SEGS 32
#define HEADER_SIZE 4

#define BLOCKS_IN_SEG (SEG_SIZE / BLOCK_SIZE)
#define SAMPLE_BUFFER_SIZE (NUM_SEGS * SEG_SIZE)
#define REAL_PAYLOAD_SIZE (MAX_APP_PAYLOAD - HEADER_SIZE)
#define NUM_PACKETS (SAMPLE_BUFFER_SIZE / REAL_PAYLOAD_SIZE)

#define MSG_TYPE_MAG 1

#define SET_UP_BLOCK_WRITE() (FCTL1 |= FWKEY + BLKWRT + WRT);

//-- user defined data stored in segment MYDATA in MSP430 Flash --
#pragma DATA_SECTION(samplebuf, ".samplemem");
#pragma DATA_ALIGN(samplebuf, 1);

unsigned char samplebuf[16384];

unsigned long *segAddress(unsigned int segindx)
{
	unsigned long addr = ROOT_ADDR + (segindx * SEG_SIZE);
	return (unsigned long *) addr;
}

/**********************************************************************//**
 * @brief  Erases a single segment of memory containing the address FarPtr.
 *
 * @param  FarPtr The address location within the segment of memory to be
 *                erased.
 *
 * @return none
 **************************************************************************/
void flashEraseSegment(unsigned int segindx)
{
  unsigned long *Flash_ptr = segAddress(segindx);

//  Flash_ptr = (unsigned long *) FarPtr;             // Initialize Flash pointer

  FCTL3 = FWKEY;
  FCTL1 = FWKEY + ERASE;

  *Flash_ptr = 0;                         // dummy write to start erase

  while (FCTL3 & BUSY );
  FCTL1 = FWKEY;
  FCTL3 = FWKEY +  LOCK;
}

/**********************************************************************//**
 * @brief  Stores data into flash segment
 *
 * @param  none
 *
 * @return none
 *************************************************************************/
void saveSample(unsigned int flashindx, unsigned char value)
{
    samplebuf[flashindx] = value;
}

/**********************************************************************//**
 * @brief  Loads calibration and user-config data from flash segment.
 *
 * @param  none
 *
 * @return none
 *************************************************************************/
unsigned char readSample(unsigned int flashindx)
{
	return samplebuf[flashindx];
}

void flashInit(void)
{
	// Stop WDT
	WDTCTL = WDTPW + WDTHOLD;
	// flash memory controller
	FCTL2 = FWKEY + FSSEL_2 + FN4 + FN2;
}

void oneSpectrum(uint16_t adcchan)
{
  int segno;

  P2SEL = 0;
  P2DIR |= 0x0e; // Set P2.0, P2.1 and P2.2 to output direction
  P2OUT = 0;

  ADC10CTL0 = SREF_0 + ADC10SHT_3 + ADC10ON + ADC10IE;
  ADC10CTL1 = adcchan | ADC10SSEL_2;
  ADC10AE0 = 0x01;
  ADC10AE1 = 0x00;
  //  ADC10AE0 = 0x1f;
  //  ADC10AE1 = 0x70;
  __delay_cycles(240);
  ADC10CTL0 |= ENC;

  for (segno = 0; segno < NUM_SEGS; segno++) {
//	 P2OUT ^= 0x02;
	 flashEraseSegment(segno);
  }

  P2OUT |= 0x04;
  FLASH_UNLOCK;
  P2OUT &= ~0x04;

  for (segno = 0; segno < NUM_SEGS; segno++) {
    volatile unsigned int i;
    uint16_t result;

	P2OUT ^= 0x02;
    for (i = 0; i < SEG_SIZE; i++) {
#ifdef BLOCKWRITE
      for (j = 0; j < BLOCKS_IN_SEG; j++) {
    	  FCTL1 = FWKEY + BLKWRT + WRT;			// set BLKWRT and WRT bits
    	  for (k = 0; k < BLOCK_SIZE; k++) {
#endif
    	    P2OUT ^= 0x08;
            // START CONVERSION
   	        ADC10CTL0 |= ADC10SC;
            // WAIT FOR SAMPLE TO BE READY
    	    while (ADC10CTL1 & ADC10BUSY);
//            __bis_SR_register(CPUOFF + GIE);        // LPM0 with interrupts enabled
//            ADC10CTL0 &= ~ADC10IFG;
            // RETRIEVE AND TRIM SAMPLE
            result = (ADC10MEM >> 2) & 0xff;
//result = i;
            // SAVE SAMPLE TO FLASH
            saveSample((segno * SEG_SIZE) + i, result);
#ifdef BLOCKWRITE
            while (!(FCTL3 & WAIT));
    	  }
          FCTL1 = FWKEY + WRT;					// reset BLKWRT bit
          while (FCTL3 & BUSY);
       }
       FCTL1 = FWKEY;							// reset WRT bit
#endif
     }

//     i = 50000;                              // Delay
//     do (i--);
//     while (i != 0);

 //    __NOP(); // place a breakpoint here to prevent damaging the flash because of continous writes!!!
  }

  P2OUT |= 0x04;
  FLASH_LOCK;
  P2OUT &= ~0x04;

  /* Stop and turn off ADC */
  ADC10CTL0 &= ~ENC;
  ADC10CTL0 &= ~ADC10ON;

  P2OUT ^= 0x02;

  /* Test flash
  unsigned long retval;
  unsigned long isval = 0, error = 0, seg = 0, sbval = 0;
  for (segno = 0; segno < NUM_SEGS; segno++) {
     volatile unsigned int i;

     for (i = 0; i < SEG_SIZE; i++) {
         P2OUT ^= 0x01;
         if ((retval = readSample((segno * SEG_SIZE) + i)) != (i & 0xff)) {
        	 error = 1;
             seg = segno;
             sbval = i;
             isval = retval;
         }
     }
   }
*/
}

void transmitSpectrum(void)
{
  int i, j;
  uint16_t seqno = 0;
  uint8_t msg[MAX_APP_PAYLOAD];

  /* message format
   -------------------------------------------------------------------
  | message type | missed acks | sequence number | (LSB,MSB| adc data |
   -------------------------------------------------------------------
          0             1              2,3                4-49
  */

  msg[0] = MSG_TYPE_MAG;
  msg[1] = 0;  // this is also set in sendPacket() when APP_AUTO_ACK is TRUE and an ack is requested
  msg[2] = seqno & 0xFF;
  msg[3] = (seqno++ >> 8) & 0xFF;

  for (i = 0; i < NUM_PACKETS; i++) {
	  for (j = 4; j < REAL_PAYLOAD_SIZE; j++) {
        msg[j] = readSample((NUM_PACKETS * i) + j);
	  }
//	  sendPacket(msg, sizeof(msg), 0);
  }
}

#endif // ACCESS_POINT
