/** @file */
/*
 * flash.c
 *
 *  Created on: Mar 7, 2013
 *      Author: flb
 */

#include "flash.h"

void flashtest(void);

#define ROOT_ADDR 0x8000
#define SEG_SIZE 512
#define NUM_SEGS 32

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
 * @brief  Stores calibration and user-config data into flash segment
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

void flashtest(void)
{
  int segno;
  unsigned long retval, isval = 0, error = 0, seg = 0, sbval = 0;

  P2DIR |= 0x03; // Set P2.0 and P2.1 to output direction
  P2OUT = 0;

  flashInit();

  for (segno = 0; segno < NUM_SEGS; segno++)
   {
     volatile unsigned int i;

     P2OUT ^= 0x01;

     flashEraseSegment(segno);

     P2OUT ^= 0x02;
     FLASH_UNLOCK;
     P2OUT ^= 0x02;

     for (i = 0; i < SEG_SIZE; i++) {
         P2OUT ^= 0x01;
         saveSample((segno * SEG_SIZE) + i, i);
     }

     P2OUT ^= 0x02;
     FLASH_LOCK;
     P2OUT ^= 0x02;

     i = 50000;                              // Delay
     do (i--);
     while (i != 0);

     P2OUT = 0;

 //    __NOP(); // place a breakpoint here to prevent damaging the flash because of continous writes!!!
   }

  for (segno = 0; segno < NUM_SEGS; segno++)
   {
     volatile unsigned int i;

     P2OUT ^= 0x01;

     for (i = 0; i < SEG_SIZE; i++) {
         P2OUT ^= 0x01;
         if ((retval = readSample((segno * SEG_SIZE) + i)) != (i & 0xff)) {
        	 error = 1;
             seg = segno;
             sbval = i;
             isval = retval;
         }
     }

     i = 50000;                              // Delay
     do (i--);
     while (i != 0);

     P2OUT = 0;

 //    __NOP(); // place a breakpoint here to prevent damaging the flash because of continous writes!!!
   }

}


