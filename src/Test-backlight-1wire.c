#include "def.h"
#include "2440addr.h"
#include "2440lib.h"
#include "1-wire.h"
#include "Test-backlight-1wire.h"

void Backlight_1wire_Test( void )
{
	U16 v = 127 ;

	if (!HasOneWire()) {
		Uart_Printf( "\nNO 1-Wire LCD dectected\n" );
		return;
	}	
	Uart_Printf( "\n1-Wire Backlight TEST\n" );
   	Uart_Printf( "Press +/- to increase/reduce the brightness of LCD\n" ) ;
	Uart_Printf( "Press 'ESC' key to Exit this program !\n\n" );
	
    while( 1 )
    {
		U8 key;
		SetBacklightOfLCD(v);
		key = Uart_Getch();

		if( key == '+' )
		{
			if( v < 127 )
				v++ ;
		}

		if( key == '-' )
		{
			if( v > 1)
				v-- ;
		}
		
		Uart_Printf( "\tBrightness = %d\n", v ) ;
		if( key == ESC_KEY )
		{
			SetBacklightOfLCD(127) ;
			return ;
		}

	}

}
