#ifndef ACCESS_POINT

#include "accel_spi.h"

/* ------------------------------------------------------------------------------------------------
 *                                       Local Prototypes
 * ------------------------------------------------------------------------------------------------
 */
static uint8_t spiRegAccess(uint8_t addrByte, uint8_t writeValue);

/**************************************************************************************************
 * @fn          accelInit
 *
 * @brief       Initialize accelerometer.
 *
 * @param       none
 *
 * @return      none
 **************************************************************************************************
 */
void accelInit(void)
{
  uint8_t x;
  // The SPI interface is initialized by SimpliciTI
  /* Accelerometer wiring
         CS (Acc)   -> Pin 8  (4.3)
         INT1       -> Pin 4  (2.1)
         INT2       -> Pin 5  (2.2)
         SDO (Acc)  -> Pin 15 (3.2)
         SDA(Acc)   -> Pin 18 (3.1)
         SCL(Acc)   -> Pin 16 (3.3)
  */

  // MASK port bits! Port 2 is shared with radio, and port 4 may be shared.

  P2IES &= 0xc0;                             // INT1&2 on low-high transition
  P2IE |= BIT1;                              // enable interrupt on P2.1
  P2IE &= ~BIT2;                             // no interrupts on INT2 for now

  accelSpiWriteReg(THRESH_ACT_ADDR,    0xf0); // 62.5mg/bit
  accelSpiWriteReg(ACT_INACT_CTL_ADDR, 0xf0); // enable X,Y,Z activity, AC mode
  accelSpiWriteReg(BW_RATE_ADDR,       0x0a); // set serial rate to 100Hz
  accelSpiWriteReg(POWER_CTL_ADDR,     0x08); // select measurement mode
  accelSpiWriteReg(INT_ENABLE_ADDR,    0x10); // enable activity interrupt
  accelSpiWriteReg(INT_MAP_ADDR,       0x00); // all interrupts on INT1

  x = accelSpiReadReg(INT_SOURCE_ADDR);
  x = accelSpiReadReg(INT_SOURCE_ADDR);

  x = accelSpiReadReg(THRESH_ACT_ADDR);
  x = accelSpiReadReg(ACT_INACT_CTL_ADDR);
  x = accelSpiReadReg(BW_RATE_ADDR);
  x = accelSpiReadReg(POWER_CTL_ADDR);
  x = accelSpiReadReg(INT_ENABLE_ADDR);
  x = accelSpiReadReg(INT_MAP_ADDR);

}

/**************************************************************************************************
 * @fn          accelSpiCmdStrobe
 *
 * @brief       Send command strobe to the accelerometer.  Returns status byte read during transfer
 *              of strobe command.
 *
 * @param       addr - address of register to strobe
 *
 * @return      status byte
 **************************************************************************************************
 */
uint8_t accelSpiCmdStrobe(uint8_t addr)
{
  uint8_t statusByte;
  mrfiSpiIState_t s;

  BSP_ASSERT( BSP_SPI_IS_INITIALIZED() );
  BSP_ASSERT(addr <= ACCEL_MAX_ADDR);

  /* disable interrupts that use SPI */
  BSP_ENTER_CRITICAL_SECTION(s);

  /* make sure clock phase and polarity are correct for accelerometer */
  ACCEL_SPI_CLK_CONFIG();

  /* turn chip select "off" and then "on" to clear any current SPI access */
  ACCEL_SPI_DRIVE_CSN_HIGH();
  ACCEL_SPI_DRIVE_CSN_LOW();

  /* send the command strobe, wait for SPI access to complete */
  BSP_SPI_WRITE_BYTE(addr);
  BSP_SPI_WAIT_DONE();

  /* read the readio status byte returned by the command strobe */
  statusByte = BSP_SPI_READ_BYTE();

  /* turn off chip select; enable interrupts that call SPI functions */
  ACCEL_SPI_DRIVE_CSN_HIGH();

  BSP_EXIT_CRITICAL_SECTION(s);

  /* return the status byte */
  return(statusByte);
}


/**************************************************************************************************
 * @fn          accelSpiReadReg
 *
 * @brief       Read value from accelerometer register.
 *
 * @param       addr - address of register
 *
 * @return      register value
 **************************************************************************************************
 */
uint8_t accelSpiReadReg(uint8_t addr)
{
  BSP_ASSERT(addr <= ACCEL_MAX_ADDR);

  /*
   *  The burst bit is set to allow access to read-only status registers.
   *  This does not affect normal register reads.
   */
  return( spiRegAccess(addr | BSP_SPI_READ_BIT, BSP_SPI_DUMMY_BYTE) );
}


/**************************************************************************************************
 * @fn          accelSpiWriteReg
 *
 * @brief       Write value to accelerometer register.
 *
 * @param       addr  - address of register
 * @param       value - register value to write
 *
 * @return      none
 **************************************************************************************************
 */
void accelSpiWriteReg(uint8_t addr, uint8_t value)
{
  BSP_ASSERT(addr <= ACCEL_MAX_ADDR);

  spiRegAccess(addr, value);
}


/*=================================================================================================
 * @fn          spiRegAccess
 *
 * @brief       This function performs a read or write.  The
 *              calling code must configure the read/write bit of the register's address byte.
 *              This bit is set or cleared based on the type of access.
 *
 * @param       regAddrByte - address byte of register; the read/write bit already configured
 *
 * @return      register value
 *=================================================================================================
 */
static uint8_t spiRegAccess(uint8_t addrByte, uint8_t writeValue)
{
  uint8_t readValue;
  mrfiSpiIState_t s;

  BSP_ASSERT( BSP_SPI_IS_INITIALIZED() );

  /* disable interrupts that use SPI */
  BSP_ENTER_CRITICAL_SECTION(s);

  /* make sure clock phase and polarity are correct for accelerometer */
  ACCEL_SPI_CLK_CONFIG();

  /* turn chip select "off" and then "on" to clear any current SPI access */
  ACCEL_SPI_DRIVE_CSN_HIGH();
  ACCEL_SPI_DRIVE_CSN_LOW();

  /* send register address byte, the read/write bit is already configured */
  BSP_SPI_WRITE_BYTE(addrByte);
  BSP_SPI_WAIT_DONE();

  /*
   *  Send the byte value to write.  If this operation is a read, this value
   *  is not used and is just dummy data.  Wait for SPI access to complete.
   */
  BSP_SPI_WRITE_BYTE(writeValue);
  BSP_SPI_WAIT_DONE();

  /*
   *  If this is a read operation, SPI data register now contains the register
   *  value which will be returned.  For a write operation, it contains junk info
   *  that is not used.
   */
  readValue = BSP_SPI_READ_BYTE();

  /* turn off chip select; enable interrupts that call SPI functions */
  ACCEL_SPI_DRIVE_CSN_HIGH();
  BSP_EXIT_CRITICAL_SECTION(s);

  /* return the register value */
  return(readValue);
}

#endif // access point