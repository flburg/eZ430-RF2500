/*
 * ======== Standard MSP430 includes ========
 */
#include <msp430.h>

/*
 * ======== Grace related declaration ========
 */
extern void CSL_init(void);

/*
 *  ======== main ========
 */
int main( void )
{
    CSL_init();                     // Activate Grace-generated configuration
    
    // >>>>> Fill-in user code here <<<<<
    
    return (0);
}
