#ifndef ACCEL_SPI_H
#define ACCEL_SPI_H

/* ------------------------------------------------------------------------------------------------
 *                                         Includes
 * ------------------------------------------------------------------------------------------------
 */
#include "bsp.h"
#include "radios/family1/mrfi_spi.h"
#include "bsp_external/mrfi_board_defs.h"

/* ------------------------------------------------------------------------------------------------
 *                                          Defines
 * ------------------------------------------------------------------------------------------------
 */

#define DUMMY_BYTE                  0xDB
#define READ_BIT                    0x80
#define BURST_BIT                   0x40

#define SPI_IS_INITIALIZED() MRFI_SPI_IS_INITIALIZED()
#define SPI_READ_BYTE()      MRFI_SPI_READ_BYTE()
#define SPI_WRITE_BYTE(x)    MRFI_SPI_WRITE_BYTE(x)
#define SPI_WAIT_DONE()      MRFI_SPI_WAIT_DONE()

/* egister map */
#define DEVID_ADDR          0x00
#define THRESH_TAP_ADDR     0x1d
#define OFSX_ADDR           0x1e
#define OFSY_ADDR           0x1f
#define OFSZ_ADDR           0x20
#define DUR_ADDR            0x21
#define LATENT_ADDR         0x22
#define WINDOW_ADDR         0x23
#define THRESH_ACT_ADDR     0x24  /* Activity threshold, 62.5mg/bit */
#define THRESH_INACT_ADDR   0x25
#define TIME_INACT_ADDR     0x26
#define ACT_INACT_CTL_ADDR  0x27  /* Axis select (= 0x70) */
#define THRESH_FF_ADDR      0x28
#define TIME_FF_ADDR        0x29
#define TAP_AXES_ADDR       0x2a
#define ACT_TAP_STATUS_ADDR 0x2b
#define BW_RATE_ADDR        0x2c  /* Power mode / Tx rate (= 0xa) */
#define POWER_CTL_ADDR      0x2d  /* Sleep mode / Auto wakeup (= 0x08) */
#define INT_ENABLE_ADDR     0x2e  /* IRQ enable (= 0x10) */
#define INT_MAP_ADDR        0x2f  /* IRQ pin select (= 0x00 - all INT1) */
#define INT_SOURCE_ADDR     0x30  /* read to clear interrupt */
#define DATA_FORMAT_ADDR    0x31
#define DATAX0_ADDR         0x32
#define DATAX1_ADDR         0x33
#define DATAY0_ADDR         0x34
#define DATAY1_ADDR         0x35
#define DATAZ0_ADDR         0x36
#define DATAZ1_ADDR         0x37
#define FIFO_CTL_ADDR       0x38
#define FIFO_STATUS_ADDR    0x39



/* ------------------------------------------------------------------------------------------------
 *                                         Prototypes
 * ------------------------------------------------------------------------------------------------
 */
//void accelSpiInit(void);

void accelInit(void);
uint8_t accelSpiCmdStrobe(uint8_t addr);
uint8_t accelSpiReadReg(uint8_t addr);
void accelSpiWriteReg(uint8_t addr, uint8_t value);

//void mrfiSpiWriteTxFifo(uint8_t * pWriteData, uint8_t len);
//void mrfiSpiReadRxFifo(uint8_t * pReadData, uint8_t len);


/**************************************************************************************************
 */
#endif
