 
#ifndef __1_WIRE_H__
#define __1_WIRE_H__

void InitOneWire(void);

int SetBacklightOfLCD(unsigned Brightness);
int GetInfo(unsigned char *Lcd, unsigned short *FirmwareVer);
int GetOneWirePoint(unsigned *Pressed, unsigned *x, unsigned *y);
int HasOneWire(void);

#endif
