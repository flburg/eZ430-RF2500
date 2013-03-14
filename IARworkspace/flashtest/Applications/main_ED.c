#include "bsp.h"

void flashEraseSegment(unsigned long FarPtr);
void saveSettings(void);
void loadSettings(void);

/*-------------------------------------------------------------
 *                       Macros
 * ------------------------------------------------------------*/
#define FLASH_UNLOCK    FCTL3 = FWKEY; FCTL1 = FWKEY + WRT;
#define FLASH_LOCK      FCTL1 = FWKEY; FCTL3 = FWKEY +  LOCK;

//-- user defined data stored in segment MYDATA in MSP430 Flash --
#pragma DATA_SECTION(variable1, ".mydata");
#pragma DATA_SECTION(variable2, ".mydata");
#pragma DATA_SECTION(variable3, ".mydata");
#pragma DATA_SECTION(variable4, ".mydata");
#pragma DATA_SECTION(variable5, ".mydata");
#pragma DATA_SECTION(variable6, ".mydata");
#pragma DATA_SECTION(variable7, ".mydata");
#pragma DATA_SECTION(variable8, ".mydata");
#pragma DATA_SECTION(variable9, ".mydata");


#pragma DATA_ALIGN(variable1, 1);
#pragma DATA_ALIGN(variable2, 1);
#pragma DATA_ALIGN(variable3, 2);
#pragma DATA_ALIGN(variable4, 1);
#pragma DATA_ALIGN(variable5, 1);
#pragma DATA_ALIGN(variable6, 2);
#pragma DATA_ALIGN(variable7, 1);
#pragma DATA_ALIGN(variable8, 1);
#pragma DATA_ALIGN(variable9, 2);

unsigned char variable1;
unsigned char variable2;
int variable3;
unsigned char variable4;
unsigned char variable5;
int variable6;
unsigned char variable7;
unsigned char variable8;
int  variable9;

// -- local variable set --
unsigned char variable1LOCAL = 0;
unsigned char variable2LOCAL = 0;
int variable3LOCAL = 0;
unsigned char variable4LOCAL = 0;
unsigned char variable5LOCAL = 0;
int variable6LOCAL = 0;
unsigned char variable7LOCAL = 0;
unsigned char variable8LOCAL = 0;
int  variable9LOCAL = 0;



/**********************************************************************//**
 * @brief  Erases a single segment of memory containing the address FarPtr.
 *
 * @param  FarPtr The address location within the segment of memory to be
 *                erased.
 *
 * @return none
 **************************************************************************/
void flashEraseSegment(unsigned long FarPtr)
{
  unsigned long *Flash_ptr;                         // local Flash pointer

  Flash_ptr = (unsigned long *) FarPtr;             // Initialize Flash pointer

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
void saveSettings(void)
{
  flashEraseSegment((unsigned long)&variable1);
  FLASH_UNLOCK;
  variable1 = variable1LOCAL ;
  variable2 = variable2LOCAL ;
  variable3 = variable3LOCAL ;
  variable4 = variable4LOCAL ;
  variable5 = variable5LOCAL;
  variable6 = variable6LOCAL ;
  variable7 = variable7LOCAL;
  variable8 = variable8LOCAL;
  variable9 = variable9LOCAL;
  FLASH_LOCK;
}

/**********************************************************************//**
 * @brief  Loads calibration and user-config data from flash segment.
 *
 * @param  none
 *
 * @return none
 *************************************************************************/
void loadSettings(void)
{
  variable1LOCAL = variable1;
  variable2LOCAL = variable2;
  variable3LOCAL = variable3;
  variable4LOCAL = variable4;
  variable5LOCAL = variable5;
  variable6LOCAL = variable6;
  variable7LOCAL = variable7;
  variable8LOCAL = variable8;
  variable9LOCAL = variable9;
}

void main(void)
{
  // some initialization for your MSP430F2274
  // disable watchdog timer
  //------------------------
  WDTCTL = WDTPW + WDTHOLD;               // Stop WDT

  // clock setting
  //------------------------
  DCOCTL = CALDCO_16MHZ;                  // Set DCO to 16MHz
  BCSCTL1 = CALBC1_16MHZ;                 // MCLC = SMCLK = DCOCLK = 16MHz
  BCSCTL1 |= DIVA_0;                      // ACLK = ACLK/1
  BCSCTL3 = LFXT1S_2;                     // LFXT1 = ACLK = VLO = ~12kHz
  BCSCTL3 &= ~LFXT1OF;                    // clear LFXT1OF flag, 0

  // flash memory controller
  FCTL2 = FWKEY + FSSEL_2 + FN5 + FN3;
                                          // SMCLK/40 for flash timing
                                          // generator

  P1DIR |= 0x01;                            // Set P1.0 to output direction

  for (;;)
  {
    volatile unsigned int i;

    P1OUT ^= 0x01;                          // Toggle P1.0 using exclusive-OR

    loadSettings(); // load settings from flash

    i = 50000;                              // Delay
    do (i--);
    while (i != 0);

    variable1LOCAL++;
    variable2LOCAL--;


    saveSettings(); // save settings to flash
    P1OUT ^= 0x01;                          // Toggle P1.0 using exclusive-OR
//    __NOP(); // place a breakpoint here to prevent damaging the flash because of continous writes!!!
  }
}


