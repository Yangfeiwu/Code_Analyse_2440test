#include "2440addr.h"
#include "1-wire.h"

#define SAMPLE_BPS 9600

#define REQ_INFO		0x60U
#define REQ_TS   		0x40U

// Pin access
//
static void set_pin_up(void)
{
	unsigned tmp = rGPBUP;
	tmp &= ~(1U <<1);
	rGPBUP = tmp;
}

static void set_pin_as_input(void)
{
	unsigned tmp;
	tmp = rGPBCON;
	tmp &= ~(3 << 2);
	rGPBCON = tmp;
}

static void set_pin_as_output(void)
{
	unsigned tmp;
	tmp = rGPBCON;
	tmp = (tmp & ~(3U << 2)) | (1U << 2);
	rGPBCON = tmp;
}

static void set_pin_value(int v)
{
	unsigned tmp;
	tmp = rGPBDAT;
	if (v) {
		tmp |= (1 << 1);
	} else {
		tmp &= ~(1<<1);
	}
	rGPBDAT = tmp;
}

static int get_pin_value(void)
{
	int v;
	unsigned long tmp;
	tmp = rGPBDAT;
	v = !!(tmp & (1<<1));
	return v;
}


static unsigned TimerCount = 0;
static void InitTimer(void)
{
	rTCFG0 &= ~(0xff<<8);
	rTCFG0 |= 0<<8;			//prescaler = 0+1
	rTCFG1 &= ~(0xf<<12);
	rTCFG1 |= 0<<12;		//mux = 1/2
	
	// Init Timer 3
	if (TimerCount == 0) {
		TimerCount = (PCLK / (0 + 1)/ 2 / SAMPLE_BPS - 1);
	}
	rTCNTB3 = TimerCount;
	rTCMPB3 = TimerCount / 2;
}

static void StartTimer(void)
{
	rTCON &= ~(0xf<<16);    // Timer3 Stop
    rTCON |= (1<<17);    // update TCNTB3
    rTCON &= ~(1<<17);
    rTCON |= ((1<<19)|(1<<16));    // AutoReload mode, Timer3 Start
}

static void StopTimer(void)
{
	unsigned tcon;
    tcon = rTCON;
	tcon &= ~(1<<16);
	rTCON = tcon;
}

static void WaitTimerTick(void)
{
	unsigned val = TimerCount;
	while(rTCNTO3>= val / 2);
	while(rTCNTO3<  val / 2);
}

static unsigned char crc8(unsigned v, unsigned len);

static int OneWireSession(unsigned char req, unsigned char res[])
{
	unsigned Req;
	unsigned *Res;
	unsigned int i;
	InitTimer();
	
	Req = (req << 24) | (crc8(req << 24, 8) << 16);
	Res = (unsigned *)res;
	
	set_pin_value(1);
	set_pin_as_output();
	StartTimer();
	for (i = 0; i < 60; i++) {
		WaitTimerTick();
	}
	set_pin_value(0);
	for (i = 0; i < 2; i++) {
		WaitTimerTick();
	}
	for (i = 0; i < 16; i++) {
		int v = !!(Req & (1U <<31));
		Req <<= 1;
		set_pin_value(v);
		WaitTimerTick();
	}
	WaitTimerTick();
	set_pin_as_input();
	WaitTimerTick();
	for (i = 0; i < 32; i++) {
		(*Res) <<= 1;
		(*Res) |= get_pin_value();
		WaitTimerTick();
	}
	StopTimer();
	set_pin_value(1);
	set_pin_as_output();

	return crc8(*Res, 24) == res[0];
}

static int TryOneWireSession(unsigned char req, unsigned char res[])
{
	int i;
	for (i = 0; i < 3; i++) {
		if (OneWireSession(req, res)) {
			return 1;
		}
	}
	return 0;
}

void InitOneWire(void)
{
	set_pin_up();
}

int GetInfo(unsigned char *Lcd, unsigned short *FirmwareVer)
{
	unsigned char res[4];
	
#if 0
    // Debug loop
	for (;;) {
		int r = TryOneWireSession(0x40U, res);
		Uart_SendString(r ? "GetInfo " : "Dont GetInfo ");
		Uart_SendHexWORD( *(unsigned *)res );
		Uart_SendString("\r\n");
	}
#endif
	if (!TryOneWireSession(REQ_INFO, res)) {
		return 0;
	}
	if (Lcd) {
		*Lcd = res[3];
	}
	if (FirmwareVer) {
		*FirmwareVer = res[2] * 0x100 + res[1];
	}
	return 1;
}

int HasOneWire(void)
{
	int r;
	r = GetInfo(0, 0);
	return r;
}

int SetBacklightOfLCD(unsigned Brightness)
{
	unsigned char res[4];
	int ret;
	if (Brightness > 127) {
		Brightness = 127;
	}
	ret = TryOneWireSession(Brightness|0x80U, res);
	return ret;
}

int GetOneWirePoint(unsigned *Pressed, unsigned *x, unsigned *y)
{
	unsigned char res[4];
	int r;
	r = TryOneWireSession(REQ_TS, res);
	if (r) {
		*x =  ((res[3] >>   4U) << 8U) + res[2];
		*y =  ((res[3] &  0xFU) << 8U) + res[1];
		*Pressed = (*x != 0xFFFU) && (*y != 0xFFFU); 
	}
	return r;
}

static unsigned char crc8(unsigned v, unsigned len)
{
	unsigned char crc = 0xACU;
	while (len--) {
		if (( crc & 0x80U) != 0) {
			crc <<= 1;
			crc ^= 0x7U;
		} else {
			crc <<= 1;
		}
		if ( (v & (1U << 31)) != 0) {
			crc ^= 0x7U;
		}
		v <<= 1;
	}
	return crc;
}
