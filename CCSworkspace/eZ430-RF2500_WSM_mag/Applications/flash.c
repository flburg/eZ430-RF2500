/** @file */
/*
 * flash.c
 *
 *  Created on: Mar 7, 2013
 *      Author: flb
 */

#include "flash.h"

#pragma DATA_SECTION(sample_buffer, ".samplemem");
#pragma DATA_ALIGN(sample_buffer, 1);
static uint8_t sample_buffer[9216];

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
//  flashEraseSegment((unsigned long)&variable1);
  FLASH_UNLOCK;
//  variable1 = variable1LOCAL ;
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
//  variable1LOCAL = variable1;
}



