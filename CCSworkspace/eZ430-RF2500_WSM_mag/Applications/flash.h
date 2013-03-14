/*
 * flash.h
 *
 *  Created on: Mar 7, 2013
 *      Author: flb
 */

#include "bsp.h"

#ifndef FLASH_H_
#define FLASH_H_

/* Flash macros */
#define FLASH_UNLOCK    FCTL3 = FWKEY; FCTL1 = FWKEY + WRT;
#define FLASH_LOCK      FCTL1 = FWKEY; FCTL3 = FWKEY +  LOCK;

#define SEG_1 0x8000
#define SEG_2 (SEG_1 + 0x200)


#endif /* FLASH_H_ */
