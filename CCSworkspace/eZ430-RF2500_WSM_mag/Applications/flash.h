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
#define FLASH_LOCK      FCTL1 = FWKEY; FCTL3 = FWKEY + LOCK;

void flashInit(void);
unsigned char readSample(unsigned int flashindx);
void saveSample(unsigned int flashindx, unsigned char value);
void flashEraseSegment(unsigned int segindx);
unsigned long *segAddress(unsigned int segindx);
void oneSpectrum(uint16_t adcchan);
void transmitSpectrum(void);

#endif /* FLASH_H_ */
