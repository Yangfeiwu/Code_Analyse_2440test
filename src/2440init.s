;=========================================
; NAME: 2440INIT.S
; DESC: C start up codes
;       Configure memory, ISR ,stacks
;	Initialize C-variables
; HISTORY:
; 2002.02.25:kwtark: ver 0.0
; 2002.03.20:purnnamu: Add some functions for testing STOP,Sleep mode
; 2003.03.14:DonGo: Modified for 2440.
;=========================================

	GET option.inc			;定义芯片相关配置
	GET memcfg.inc			;定义存储器相关配置
	GET 2440addr.inc		;定义寄存器符号

BIT_SELFREFRESH EQU	(1<<22)		;用于节电模式中，SDRAM自动刷新

;Pre-defined constants		;处理器模式常量: CPSR寄存器的后5位决定目前处理器模式 M[4:0]
USERMODE    EQU 	0x10		;正常 ARM 程序执行状态
FIQMODE     EQU 	0x11		;为支持数据传输或通道处理设计
IRQMODE     EQU 	0x12		;用于一般用途的中断处理
SVCMODE     EQU 	0x13		;操作系统保护模式
ABORTMODE   EQU 	0x17		;数据或指令预取中止后进入
UNDEFMODE   EQU 	0x1b		;执行了一个未定义指令时进入
MODEMASK    EQU 	0x1f		;操作系统的特权用户模式 M[4:0]  
NOINT       EQU 	0xc0		;禁止中断 （FIQ 禁止、IRQ 禁止）


;定义处理器各模式下堆栈地址常量   
;The location of stacks	
UserStack	EQU	(_STACK_BASEADDRESS-0x3800)	;0x33ff4800 ~  _STACK_BASEADDRESS=0x33ff8000定义在option.inc中
SVCStack	EQU	(_STACK_BASEADDRESS-0x2800)	;0x33ff5800 ~
UndefStack	EQU	(_STACK_BASEADDRESS-0x2400)	;0x33ff5c00 ~
AbortStack	EQU	(_STACK_BASEADDRESS-0x2000)	;0x33ff6000 ~
IRQStack	EQU	(_STACK_BASEADDRESS-0x1000)	;0x33ff7000 ~
FIQStack	EQU	(_STACK_BASEADDRESS-0x0)	;0x33ff8000 ~


;arm处理器有两种工作状态 1.arm:32位 这种工作状态下执行字对准的arm指令 2.Thumb:16位 这种工作状
;态执行半字对准的Thumb指令
;因为处理器分为16位 32位两种工作状态 程序的编译器也是分16位和32两种编译方式 所以下面的程序用
;于根据处理器工作状态确定编译器编译方式
;code16伪指令指示汇编编译器后面的指令为16位的thumb指令
;code32伪指令指示汇编编译器后面的指令为32位的arm指令
;
;Arm上电时处于ARM状态，故无论指令为ARM集或Thumb集，都先强制成ARM集，待init.s初始化完成后
;再根据用户的编译配置转换成相应的指令模式。为此，定义变量THUMBCODE作为指示，跳转到main之前
;根据其值切换指令模式
;
;这段是为了统一目前的处理器工作状态和软件编译方式（16位编译环境使用tasm.exe编译
;Check if tasm.exe(armasm -16 ...@ADS 1.0) is used.
	GBLL    THUMBCODE	;定义THUMBCODE全局变量注意EQU所定义的宏与变量的区别
	[ {CONFIG} = 16		;如果发现是在用16位代码的话（编译选项中指定使用thumb指令）CONFIG变量由ADS中设置
THUMBCODE SETL  {TRUE}	;一方面把THUMBCODE设置为TURE
	    CODE32			;另一方面暂且把处理器设置成为ARM模式，以方便初始化
 		|				;（|表示else）如果编译选项本来就指定为ARM模式
THUMBCODE SETL  {FALSE}	;把THUMBCODE设置为FALSE就行了
    ]

;MACRO伪操作标识宏定义的开始，MEND标识宏定义的结束。
;用MACRO及MEND定义一段代码，称为宏定义体，这样在程序中就可以通过宏指令多次调用该代码段。 

 		MACRO	;一个根据THUMBCODE把PC寄存的值保存到LR的宏
	MOV_PC_LR	;宏名称(完成子程序返回)
 		[ THUMBCODE	;如果定义了THUMBCODE，则
	    bx lr	;在ARM模式中要使用BX指令转跳到THUMB指令,并转换模式. bx指令会根据PC最后1位来确定是否进入thumb状态
 		|			;否则
	    mov	pc,lr	;如果目标地址也是ARM指令的话就采用这种方式
 		]
	MEND			;宏定义结束标志

 		MACRO		;和上面的宏一样,只是多了一个相等的条件
	MOVEQ_PC_LR
 		[ THUMBCODE
        bxeq lr
 		|
	    moveq pc,lr
 		]
	MEND
		;=======================================================================================
		;下面这个宏是用于第一次查表过程的实现中断向量的重定向,如果你比较细心的话就会发现
		;在_ISR_STARTADDRESS=0x33FF_FF00里定义的第一级中断向量表是采用型如Handle***的方式的.
		;而在程序的ENTRY处(程序开始处)采用的是b Handler***的方式.
		;在这里Handler***就是通过HANDLER这个宏和Handle***建立联系的.
		;这种方式的优点就是正真定义的向量数据在内存空间里,而不是在ENTRY处的ROM(FLASH)空间里,
		;这样,我们就可以在程序里灵活的改动向量的数据了.
		;========================================================================================
		;;这段程序用于把中断服务程序的首地址装载到pc中，有人称之为“加载程序”。
		;本初始化程序定义了一个数据区（在文件最后），34个字空间，存放相应中断服务程序的首地址。每个字
		;空间都有一个标号，以Handle***命名。
		;在向量中断模式下使用“加载程序”来执行中断服务程序。
		;这里就必须讲一下向量中断模式和非向量中断模式的概念
		;向量中断模式是当cpu读取位于0x18处的IRQ中断指令的时候，系统自动读取对应于该中断源确定地址上的;
		;指令取代0x18处的指令，通过跳转指令系统就直接跳转到对应地址
		;函数中 节省了中断处理时间提高了中断处理速度度 例如 ADC中断的向量地址为0xC0,则在0xC0处放如下
		;代码：ldr PC,=HandlerADC 当ADC中断产生的时候系统会
		;自动跳转到HandlerADC函数中
		;非向量中断模式处理方式是一种传统的中断处理方法，当系统产生中断的时候，系统将interrupt
		;pending寄存器中对应标志位置位 然后跳转到位于0x18处的统一中断
		;函数中 该函数通过读取interrupt pending寄存器中对应标志位 来判断中断源 并根据优先级关系再跳到
		;对应中断源的处理代码中
		;
		;H|------|			 H|------|		  H|------| 		  H|------| 		H|------|		
		; |/ / / |			  |/ / / |		   |/ / / | 		   |/ / / | 		 |/ / / |		
		; |------|<----sp	  |------|		   |------| 		   |------| 		 |------|<------sp 
		;L| 	 |			  |------|<----sp L|------| 		   |-isr--| 		 |------| isr==>pc
		; | 	 |			  | 	 |		   |--r0--|<----sp	   |---r0-|<----sp	L|------| r0==>r0
		;	 (0)				(1) 			 (2)				  (3)				(4)

;[各中断跳转处理，跳转到我们最后面定义的中断地址去处理]		 
 		MACRO
$HandlerLabel HANDLER $HandleLabel		;注意$HandlerLabel符号 比后面的$HandleLabel符号 多一个字母‘r’ ，相当于函数的形参
;$HandlerLabel为ARM体现中统一定义的几种异常中断
;$HandleLabel为ARM处理器中每个中断的定义，见中断向量表
$HandlerLabel	 ;标号
	sub	sp,sp,#4	;(1)减少sp，预留一个用来存储PC地址（因为stmfd是递减入栈的，又是arm（32位）模式所以减4）
	stmfd	sp!,{r0}	;(2)把工作寄存器压入栈(lr does not push because it return to original address)
	ldr     r0,=$HandleLabel	;将HandleXXX的址址放入r0
	ldr     r0,[r0]	 			;把HandleXXX所指向的内容(也就是中断程序的入口地址)放入r0
	str     r0,[sp,#4]       ;(3)中断服务函数的起始地址入栈
	ldmfd   sp!,{r0,pc}     ;(4)将事先保存的r0寄存器和中断函数首地址出栈，并使系统跳转到相应的中断处理函数（跳转到下面的IsrIRQ函数处）
	MEND

	;首先这段程序是个宏定义，HANDLER是宏名，不要想歪了
	;其次后面程序遇到的HandlerXXX HANDLER HandleXXX这些语句将都被上面这段程序展开
			
		;=========================================================================================
		;在这里用IMPORT伪指令(和c语言的extren一样)引入|Image$$RO$$Base|,|Image$$RO$$Limit|...
		;这些变量是通过ADS的工程设置里面设定的RO Base和RW Base设定的,
		;最终由编译脚本和连接程序导入程序.
		;那为什么要引入这玩意呢,最简单的用处是可以根据它们拷贝自已
		;==========================================================================================
		;Image$$RO$$Base等比较古怪的变量是编译器生成的。RO, RW, ZI这三个段都保存在Flash中，但RW，ZI在Flash中
		;的地址肯定不是程序运行时变量所存储的位置，因此我们的程序在初始化时应该把Flash中的RW，ZI拷贝到RAM的对应位置。
		;一般情况下，我们可以利用编译器替我们实现这个操作。比如我们跳转到main()时，使用 b	__Main,编译器就会在__Main
		;和Main之间插入一段汇编代码，来替我们完成RW，ZI段的初始化。 如果我们使用 b	Main， 那么初始化工作要我们自己做。
		;编译器会生成如下变量告诉我们RO，RW，ZI三个段应该位于什么位置，但是它并没有告诉我们RW，ZI在Flash中存储在什么位置，
		;实际上RW，ZI在Flash中的位置就紧接着RO存储。我们知道了Image$$RO$$Base，Image$$RO$$Limit，那么Image$$RO$$Limit就
		;是RW（ROM data）的开始。

	IMPORT  |Image$$RO$$Base|	;RO起始地址
	IMPORT  |Image$$RO$$Limit|  ;RO结束地址
	IMPORT  |Image$$RW$$Base|   ;RW段起始地址
	IMPORT  |Image$$ZI$$Base|   ;ZI段起始地址
	IMPORT  |Image$$ZI$$Limit|  ;ZI段结束地址

	IMPORT	MMU_SetAsyncBusMode
	IMPORT	MMU_SetFastBusMode	;

	IMPORT  Main    ; The main entry of mon program
	IMPORT  CopyProgramFromNand

	AREA    Init,CODE,READONLY

	ENTRY
	
	EXPORT	__ENTRY
__ENTRY
ResetEntry
	;1)The code, which converts to Big-endian, should be in little endian code.
	;2)The following little endian code will be compiled in Big-Endian mode.
	;  The code byte order should be changed as the memory bus width.
	;3)The pseudo instruction,DCD can not be used here because the linker generates error.
	ASSERT	:DEF:ENDIAN_CHANGE
	[ ENDIAN_CHANGE
	    ASSERT  :DEF:ENTRY_BUS_WIDTH
	    [ ENTRY_BUS_WIDTH=32
		b	ChangeBigEndian	    ;DCD 0xea000007
	    ]

	    [ ENTRY_BUS_WIDTH=16
		andeq	r14,r7,r0,lsl #20   ;DCD 0x0007ea00
	    ]

	    [ ENTRY_BUS_WIDTH=8
		streq	r0,[r0,-r10,ror #1] ;DCD 0x070000ea
	    ]
	|
	    b	ResetHandler
    ]
	b	HandlerUndef	;handler for Undefined mode
	b	HandlerSWI	;handler for SWI interrupt
	b	HandlerPabort	;handler for PAbort
	b	HandlerDabort	;handler for DAbort
	b	.		;reserved
	b	HandlerIRQ	;handler for IRQ interrupt
	b	HandlerFIQ	;handler for FIQ interrupt

;@0x20
	b	EnterPWDN	; Must be @0x20.
ChangeBigEndian
;@0x24
	[ ENTRY_BUS_WIDTH=32
	    DCD	0xee110f10	;0xee110f10 => mrc p15,0,r0,c1,c0,0
	    DCD	0xe3800080	;0xe3800080 => orr r0,r0,#0x80;  //Big-endian
	    DCD	0xee010f10	;0xee010f10 => mcr p15,0,r0,c1,c0,0
	]
	[ ENTRY_BUS_WIDTH=16
	    DCD 0x0f10ee11
	    DCD 0x0080e380
	    DCD 0x0f10ee01
	]
	[ ENTRY_BUS_WIDTH=8
	    DCD 0x100f11ee
	    DCD 0x800080e3
	    DCD 0x100f01ee
    ]
	DCD 0xffffffff  ;swinv 0xffffff is similar with NOP and run well in both endian mode.
	DCD 0xffffffff
	DCD 0xffffffff
	DCD 0xffffffff
	DCD 0xffffffff
	b ResetHandler
	
HandlerFIQ      HANDLER HandleFIQ
HandlerIRQ      HANDLER HandleIRQ
HandlerUndef    HANDLER HandleUndef
HandlerSWI      HANDLER HandleSWI
HandlerDabort   HANDLER HandleDabort
HandlerPabort   HANDLER HandlePabort

IsrIRQ
	sub	sp,sp,#4       ;reserved for PC
	stmfd	sp!,{r8-r9}

	ldr	r9,=INTOFFSET
	ldr	r9,[r9]
	ldr	r8,=HandleEINT0
	add	r8,r8,r9,lsl #2
	ldr	r8,[r8]
	str	r8,[sp,#8]
	ldmfd	sp!,{r8-r9,pc}


	LTORG

;=======
; ENTRY
;=======
ResetHandler
	ldr	r0,=WTCON       ;watch dog disable
	ldr	r1,=0x0
	str	r1,[r0]

	ldr	r0,=INTMSK
	ldr	r1,=0xffffffff  ;all interrupt disable
	str	r1,[r0]

	ldr	r0,=INTSUBMSK
	ldr	r1,=0x7fff		;all sub interrupt disable
	str	r1,[r0]

	[ {TRUE}
	;rGPFDAT = (rGPFDAT & ~(0xf<<4)) | ((~data & 0xf)<<4);
	; Led_Display
	ldr	r0,=GPBCON
	ldr	r1,=0x00555555
	str	r1,[r0]
	ldr	r0,=GPBDAT
	ldr	r1,=0x07fe
	str	r1,[r0]
	]

	;To reduce PLL lock time, adjust the LOCKTIME register.
	ldr	r0,=LOCKTIME
	ldr	r1,=0xffffff
	str	r1,[r0]

    [ PLL_ON_START
	; Added for confirm clock divide. for 2440.
	; Setting value Fclk:Hclk:Pclk
	ldr	r0,=CLKDIVN
	ldr	r1,=CLKDIV_VAL		; 0=1:1:1, 1=1:1:2, 2=1:2:2, 3=1:2:4, 4=1:4:4, 5=1:4:8, 6=1:3:3, 7=1:3:6.
	str	r1,[r0]
;	MMU_SetAsyncBusMode and MMU_SetFastBusMode over 4K, so do not call here
;	call it after copy
;	[ CLKDIV_VAL>1 		; means Fclk:Hclk is not 1:1.
;	bl MMU_SetAsyncBusMode
;	|
;	bl MMU_SetFastBusMode	; default value.
;	]
	;program has not been copied, so use these directly
	[ CLKDIV_VAL>1 		; means Fclk:Hclk is not 1:1.
	mrc p15,0,r0,c1,c0,0
	orr r0,r0,#0xc0000000;R1_nF:OR:R1_iA
	mcr p15,0,r0,c1,c0,0
	|
	mrc p15,0,r0,c1,c0,0
	bic r0,r0,#0xc0000000;R1_iA:OR:R1_nF
	mcr p15,0,r0,c1,c0,0
	]
	
	;Configure UPLL
	ldr	r0,=UPLLCON
	ldr	r1,=((U_MDIV<<12)+(U_PDIV<<4)+U_SDIV)  
	str	r1,[r0]
	nop	; Caution: After UPLL setting, at least 7-clocks delay must be inserted for setting hardware be completed.
	nop
	nop
	nop
	nop
	nop
	nop
	;Configure MPLL
	ldr	r0,=MPLLCON
	ldr	r1,=((M_MDIV<<12)+(M_PDIV<<4)+M_SDIV)  ;Fin=16.9344MHz
	str	r1,[r0]
    ]

	;Check if the boot is caused by the wake-up from SLEEP mode.
	ldr	r1,=GSTATUS2
	ldr	r0,[r1]
	tst	r0,#0x2
	;In case of the wake-up from SLEEP mode, go to SLEEP_WAKEUP handler.
	bne	WAKEUP_SLEEP

	EXPORT StartPointAfterSleepWakeUp
StartPointAfterSleepWakeUp

	;Set memory control registers
 	;ldr	r0,=SMRDATA
 	adrl	r0, SMRDATA	;be careful!
	ldr	r1,=BWSCON	;BWSCON Address
	add	r2, r0, #52	;End address of SMRDATA

0
	ldr	r3, [r0], #4
	str	r3, [r1], #4
	cmp	r2, r0
	bne	%B0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;       When EINT0 is pressed,  Clear SDRAM 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; check if EIN0 button is pressed

       ldr	r0,=GPFCON
	ldr	r1,=0x0
	str	r1,[r0]
	ldr	r0,=GPFUP
	ldr	r1,=0xff
	str	r1,[r0]

	ldr	r1,=GPFDAT
	ldr	r0,[r1]
       bic	r0,r0,#(0x1e<<1)  ; bit clear
	tst	r0,#0x1
	bne %F1
	
	

; Clear SDRAM Start
  
	ldr	r0,=GPFCON
	ldr	r1,=0x55aa
	str	r1,[r0]
;	ldr	r0,=GPFUP
;	ldr	r1,=0xff
;	str	r1,[r0]
	ldr	r0,=GPFDAT
	ldr	r1,=0x0
	str	r1,[r0]	;LED=****

	mov r1,#0
	mov r2,#0
	mov r3,#0
	mov r4,#0
	mov r5,#0
	mov r6,#0
	mov r7,#0
	mov r8,#0
	
	ldr	r9,=0x4000000   ;64MB
	ldr	r0,=0x30000000
0	
	stmia	r0!,{r1-r8}
	subs	r9,r9,#32 
	bne	%B0

;Clear SDRAM End

1

 		;Initialize stacks
	bl	InitStacks

;===========================================================
	
	ldr	r0, =BWSCON
	ldr	r0, [r0]
	ands	r0, r0, #6		;OM[1:0] != 0, NOR FLash boot
	bne	copy_proc_beg		;do not read nand flash
	adr	r0, ResetEntry		;OM[1:0] == 0, NAND FLash boot
	cmp	r0, #0				;if use Multi-ice, 
	bne	copy_proc_beg		;do not read nand flash for boot
	;nop
;===========================================================
nand_boot_beg
	[ {TRUE}
	bl CopyProgramFromNand
	|
	mov	r5, #NFCONF
	;set timing value
	ldr	r0,	=(7<<12)|(7<<8)|(7<<4)
	str	r0,	[r5]
	;enable control
	ldr	r0, =(0<<13)|(0<<12)|(0<<10)|(0<<9)|(0<<8)|(1<<6)|(1<<5)|(1<<4)|(1<<1)|(1<<0)
	str	r0, [r5, #4]
	
	bl	ReadNandID
	mov	r6, #0
	ldr	r0, =0xec73
	cmp	r5,	r0
	beq	%F1
	ldr	r0, =0xec75
	cmp	r5, r0
	beq	%F1
	mov	r6, #1
1	
	bl	ReadNandStatus
	
	mov	r8, #0
	ldr	r9, =ResetEntry
2	
	ands	r0, r8, #0x1f
	bne		%F3
	mov		r0, r8
	bl		CheckBadBlk
	cmp		r0, #0
	addne	r8, r8, #32
	bne		%F4
3	
	mov	r0, r8
	mov	r1, r9
	bl	ReadNandPage
	add	r9, r9, #512
	add	r8, r8, #1
4	
	cmp	r8, #5120
	bcc	%B2
	
	mov	r5, #NFCONF			;DsNandFlash
	ldr	r0, [r5, #4]
	bic r0, r0, #1
	str	r0, [r5, #4]
	]
	ldr	pc, =copy_proc_beg
;===========================================================
copy_proc_beg
	adr	r0, ResetEntry
	ldr	r2, BaseOfROM
	cmp	r0, r2
	ldreq	r0, TopOfROM
	beq	InitRam	
	ldr r3, TopOfROM
0	
	ldmia	r0!, {r4-r7}
	stmia	r2!, {r4-r7}
	cmp	r2, r3
	bcc	%B0
	
	sub	r2, r2, r3
	sub	r0, r0, r2				
		
InitRam	
	ldr	r2, BaseOfBSS
	ldr	r3, BaseOfZero	
0
	cmp	r2, r3
	ldrcc	r1, [r0], #4
	strcc	r1, [r2], #4
	bcc	%B0	

	mov	r0,	#0
	ldr	r3,	EndOfBSS
1	
	cmp	r2,	r3
	strcc	r0, [r2], #4
	bcc	%B1
	
	ldr	pc, =%F2		;goto compiler address
2
	
;	[ CLKDIV_VAL>1 		; means Fclk:Hclk is not 1:1.
;	bl	MMU_SetAsyncBusMode
;	|
;	bl MMU_SetFastBusMode	; default value.
;	]
	
	;bl	Led_Test

;===========================================================
  	; Setup IRQ handler
	ldr	r0,=HandleIRQ       ;This routine is needed
	ldr	r1,=IsrIRQ	  ;if there is not 'subs pc,lr,#4' at 0x18, 0x1c
	str	r1,[r0]

;	;Copy and paste RW data/zero initialized data
;	ldr	r0, =|Image$$RO$$Limit| ; Get pointer to ROM data
;	ldr	r1, =|Image$$RW$$Base|  ; and RAM copy
;	ldr	r3, =|Image$$ZI$$Base|
;
;	;Zero init base => top of initialised data
;	cmp	r0, r1      ; Check that they are different
;	beq	%F2
;1
;	cmp	r1, r3      ; Copy init data
;	ldrcc	r2, [r0], #4    ;--> LDRCC r2, [r0] + ADD r0, r0, #4
;	strcc	r2, [r1], #4    ;--> STRCC r2, [r1] + ADD r1, r1, #4
;	bcc	%B1
;2
;	ldr	r1, =|Image$$ZI$$Limit| ; Top of zero init segment
;	mov	r2, #0
;3
;	cmp	r3, r1      ; Zero init
;	strcc	r2, [r3], #4
;	bcc	%B3


    [ :LNOT:THUMBCODE
 		bl	Main	;Do not use main() because ......
 		;ldr	pc, =Main	;
 		b	.
    ]

    [ THUMBCODE	 ;for start-up code for Thumb mode
 		orr	lr,pc,#1
 		bx	lr
 		CODE16
 		bl	Main	;Do not use main() because ......
 		b	.
		CODE32
    ]


;function initializing stacks
InitStacks
	;Do not use DRAM,such as stmfd,ldmfd......
	;SVCstack is initialized before
	;Under toolkit ver 2.5, 'msr cpsr,r1' can be used instead of 'msr cpsr_cxsf,r1'
	mrs	r0,cpsr
	bic	r0,r0,#MODEMASK
	orr	r1,r0,#UNDEFMODE|NOINT
	msr	cpsr_cxsf,r1		;UndefMode
	ldr	sp,=UndefStack		; UndefStack=0x33FF_5C00

	orr	r1,r0,#ABORTMODE|NOINT
	msr	cpsr_cxsf,r1		;AbortMode
	ldr	sp,=AbortStack		; AbortStack=0x33FF_6000

	orr	r1,r0,#IRQMODE|NOINT
	msr	cpsr_cxsf,r1		;IRQMode
	ldr	sp,=IRQStack		; IRQStack=0x33FF_7000

	orr	r1,r0,#FIQMODE|NOINT
	msr	cpsr_cxsf,r1		;FIQMode
	ldr	sp,=FIQStack		; FIQStack=0x33FF_8000

	bic	r0,r0,#MODEMASK|NOINT
	orr	r1,r0,#SVCMODE
	msr	cpsr_cxsf,r1		;SVCMode
	ldr	sp,=SVCStack		; SVCStack=0x33FF_5800

	;USER mode has not be initialized.

	mov	pc,lr
	;The LR register will not be valid if the current mode is not SVC mode.
	
;===========================================================
	[ {TRUE}
	|
ReadNandID
	mov      r7,#NFCONF
	ldr      r0,[r7,#4]		;NFChipEn();
	bic      r0,r0,#2
	str      r0,[r7,#4]
	mov      r0,#0x90		;WrNFCmd(RdIDCMD);
	strb     r0,[r7,#8]
	mov      r4,#0			;WrNFAddr(0);
	strb     r4,[r7,#0xc]
1							;while(NFIsBusy());
	ldr      r0,[r7,#0x20]
	tst      r0,#1
	beq      %B1
	ldrb     r0,[r7,#0x10]	;id  = RdNFDat()<<8;
	mov      r0,r0,lsl #8
	ldrb     r1,[r7,#0x10]	;id |= RdNFDat();
	orr      r5,r1,r0
	ldr      r0,[r7,#4]		;NFChipDs();
	orr      r0,r0,#2
	str      r0,[r7,#4]
	mov		 pc,lr	
	
ReadNandStatus
	mov		 r7,#NFCONF
	ldr      r0,[r7,#4]		;NFChipEn();
	bic      r0,r0,#2
	str      r0,[r7,#4]
	mov      r0,#0x70		;WrNFCmd(QUERYCMD);
	strb     r0,[r7,#8]	
	ldrb     r1,[r7,#0x10]	;r1 = RdNFDat();
	ldr      r0,[r7,#4]		;NFChipDs();
	orr      r0,r0,#2
	str      r0,[r7,#4]
	mov		 pc,lr

WaitNandBusy
	mov      r0,#0x70		;WrNFCmd(QUERYCMD);
	mov      r1,#NFCONF
	strb     r0,[r1,#8]
1							;while(!(RdNFDat()&0x40));	
	ldrb     r0,[r1,#0x10]
	tst      r0,#0x40
	beq		 %B1
	mov      r0,#0			;WrNFCmd(READCMD0);
	strb     r0,[r1,#8]
	mov      pc,lr

CheckBadBlk
	mov		r7, lr
	mov		r5, #NFCONF
	
	bic      r0,r0,#0x1f	;addr &= ~0x1f;
	ldr      r1,[r5,#4]		;NFChipEn()
	bic      r1,r1,#2
	str      r1,[r5,#4]

	mov      r1,#0x50		;WrNFCmd(READCMD2)
	strb     r1,[r5,#8]
	mov      r1, #5;6		;6->5
	strb     r1,[r5,#0xc]	;WrNFAddr(5);(6) 6->5
	strb     r0,[r5,#0xc]	;WrNFAddr(addr)
	mov      r1,r0,lsr #8	;WrNFAddr(addr>>8)
	strb     r1,[r5,#0xc]
	cmp      r6,#0			;if(NandAddr)		
	movne    r0,r0,lsr #16	;WrNFAddr(addr>>16)
	strneb   r0,[r5,#0xc]
	
;	bl		WaitNandBusy	;WaitNFBusy()
	;do not use WaitNandBusy, after WaitNandBusy will read part A!
	mov	r0, #100
1
	subs	r0, r0, #1
	bne	%B1
2
	ldr	r0, [r5, #0x20]
	tst	r0, #1
	beq	%B2	

	ldrb	r0, [r5,#0x10]	;RdNFDat()
	sub		r0, r0, #0xff
	
	mov      r1,#0			;WrNFCmd(READCMD0)
	strb     r1,[r5,#8]
	
	ldr      r1,[r5,#4]		;NFChipDs()
	orr      r1,r1,#2
	str      r1,[r5,#4]
	
	mov		pc, r7
	
ReadNandPage
	mov		 r7,lr
	mov      r4,r1
	mov      r5,#NFCONF

	ldr      r1,[r5,#4]		;NFChipEn()
	bic      r1,r1,#2
	str      r1,[r5,#4]	

	mov      r1,#0			;WrNFCmd(READCMD0)
	strb     r1,[r5,#8]	
	strb     r1,[r5,#0xc]	;WrNFAddr(0)
	strb     r0,[r5,#0xc]	;WrNFAddr(addr)
	mov      r1,r0,lsr #8	;WrNFAddr(addr>>8)
	strb     r1,[r5,#0xc]	
	cmp      r6,#0			;if(NandAddr)		
	movne    r0,r0,lsr #16	;WrNFAddr(addr>>16)
	strneb   r0,[r5,#0xc]
	
	ldr      r0,[r5,#4]		;InitEcc()
	orr      r0,r0,#0x10
	str      r0,[r5,#4]
	
	bl       WaitNandBusy	;WaitNFBusy()
	
	mov      r0,#0			;for(i=0; i<512; i++)
1
	ldrb     r1,[r5,#0x10]	;buf[i] = RdNFDat()
	strb     r1,[r4,r0]
	add      r0,r0,#1
	bic      r0,r0,#0x10000
	cmp      r0,#0x200
	bcc      %B1
	
	ldr      r0,[r5,#4]		;NFChipDs()
	orr      r0,r0,#2
	str      r0,[r5,#4]
		
	mov		 pc,r7
	]


;===========================================================

	LTORG

;GCS0->SST39VF1601
;GCS1->16c550
;GCS2->IDE
;GCS3->CS8900
;GCS4->DM9000
;GCS5->CF Card
;GCS6->SDRAM
;GCS7->unused

SMRDATA DATA
; Memory configuration should be optimized for best performance
; The following parameter is not optimized.
; Memory access cycle parameter strategy
; 1) The memory settings is  safe parameters even at HCLK=75Mhz.
; 2) SDRAM refresh period is for HCLK<=75Mhz.

	DCD (0+(B1_BWSCON<<4)+(B2_BWSCON<<8)+(B3_BWSCON<<12)+(B4_BWSCON<<16)+(B5_BWSCON<<20)+(B6_BWSCON<<24)+(B7_BWSCON<<28))
	DCD ((B0_Tacs<<13)+(B0_Tcos<<11)+(B0_Tacc<<8)+(B0_Tcoh<<6)+(B0_Tah<<4)+(B0_Tacp<<2)+(B0_PMC))   ;GCS0
	DCD ((B1_Tacs<<13)+(B1_Tcos<<11)+(B1_Tacc<<8)+(B1_Tcoh<<6)+(B1_Tah<<4)+(B1_Tacp<<2)+(B1_PMC))   ;GCS1
	DCD ((B2_Tacs<<13)+(B2_Tcos<<11)+(B2_Tacc<<8)+(B2_Tcoh<<6)+(B2_Tah<<4)+(B2_Tacp<<2)+(B2_PMC))   ;GCS2
	DCD ((B3_Tacs<<13)+(B3_Tcos<<11)+(B3_Tacc<<8)+(B3_Tcoh<<6)+(B3_Tah<<4)+(B3_Tacp<<2)+(B3_PMC))   ;GCS3
	DCD ((B4_Tacs<<13)+(B4_Tcos<<11)+(B4_Tacc<<8)+(B4_Tcoh<<6)+(B4_Tah<<4)+(B4_Tacp<<2)+(B4_PMC))   ;GCS4
	DCD ((B5_Tacs<<13)+(B5_Tcos<<11)+(B5_Tacc<<8)+(B5_Tcoh<<6)+(B5_Tah<<4)+(B5_Tacp<<2)+(B5_PMC))   ;GCS5
	DCD ((B6_MT<<15)+(B6_Trcd<<2)+(B6_SCAN))    ;GCS6
	DCD ((B7_MT<<15)+(B7_Trcd<<2)+(B7_SCAN))    ;GCS7
	DCD ((REFEN<<23)+(TREFMD<<22)+(Trp<<20)+(Tsrc<<18)+(Tchr<<16)+REFCNT)

	DCD 0x32	    ;SCLK power saving mode, BANKSIZE 128M/128M

	DCD 0x30	    ;MRSR6 CL=3clk
	DCD 0x30	    ;MRSR7 CL=3clk
	
BaseOfROM	DCD	|Image$$RO$$Base|
TopOfROM	DCD	|Image$$RO$$Limit|
BaseOfBSS	DCD	|Image$$RW$$Base|
BaseOfZero	DCD	|Image$$ZI$$Base|
EndOfBSS	DCD	|Image$$ZI$$Limit|

	ALIGN
	
;Function for entering power down mode
; 1. SDRAM should be in self-refresh mode.
; 2. All interrupt should be maksked for SDRAM/DRAM self-refresh.
; 3. LCD controller should be disabled for SDRAM/DRAM self-refresh.
; 4. The I-cache may have to be turned on.
; 5. The location of the following code may have not to be changed.

;void EnterPWDN(int CLKCON);
EnterPWDN
	mov r2,r0		;r2=rCLKCON
	tst r0,#0x8		;SLEEP mode?
	bne ENTER_SLEEP

ENTER_STOP
	ldr r0,=REFRESH
	ldr r3,[r0]		;r3=rREFRESH
	mov r1, r3
	orr r1, r1, #BIT_SELFREFRESH
	str r1, [r0]		;Enable SDRAM self-refresh

	mov r1,#16			;wait until self-refresh is issued. may not be needed.
0	subs r1,r1,#1
	bne %B0

	ldr r0,=CLKCON		;enter STOP mode.
	str r2,[r0]

	mov r1,#32
0	subs r1,r1,#1	;1) wait until the STOP mode is in effect.
	bne %B0		;2) Or wait here until the CPU&Peripherals will be turned-off
			;   Entering SLEEP mode, only the reset by wake-up is available.

	ldr r0,=REFRESH ;exit from SDRAM self refresh mode.
	str r3,[r0]

	MOV_PC_LR

ENTER_SLEEP
	;NOTE.
	;1) rGSTATUS3 should have the return address after wake-up from SLEEP mode.

	ldr r0,=REFRESH
	ldr r1,[r0]		;r1=rREFRESH
	orr r1, r1, #BIT_SELFREFRESH
	str r1, [r0]		;Enable SDRAM self-refresh

	mov r1,#16			;Wait until self-refresh is issued,which may not be needed.
0	subs r1,r1,#1
	bne %B0

	ldr	r1,=MISCCR
	ldr	r0,[r1]
	orr	r0,r0,#(7<<17)  ;Set SCLK0=0, SCLK1=0, SCKE=0.
	str	r0,[r1]

	ldr r0,=CLKCON		; Enter sleep mode
	str r2,[r0]

	b .			;CPU will die here.


WAKEUP_SLEEP
	;Release SCLKn after wake-up from the SLEEP mode.
	ldr	r1,=MISCCR
	ldr	r0,[r1]
	bic	r0,r0,#(7<<17)  ;SCLK0:0->SCLK, SCLK1:0->SCLK, SCKE:0->=SCKE.
	str	r0,[r1]

	;Set memory control registers
 	ldr	r0,=SMRDATA	;be careful! 
	ldr	r1,=BWSCON	;BWSCON Address
	add	r2, r0, #52	;End address of SMRDATA
0
	ldr	r3, [r0], #4
	str	r3, [r1], #4
	cmp	r2, r0
	bne	%B0

	mov r1,#256
0	subs r1,r1,#1	;1) wait until the SelfRefresh is released.
	bne %B0

	ldr r1,=GSTATUS3 	;GSTATUS3 has the start address just after SLEEP wake-up
	ldr r0,[r1]

	mov pc,r0
	
;=====================================================================
; Clock division test
; Assemble code, because VSYNC time is very short
;=====================================================================
	EXPORT CLKDIV124
	EXPORT CLKDIV144
	
CLKDIV124
	
	ldr     r0, = CLKDIVN
	ldr     r1, = 0x3		; 0x3 = 1:2:4
	str     r1, [r0]
;	wait until clock is stable
	nop
	nop
	nop
	nop
	nop

	ldr     r0, = REFRESH
	ldr     r1, [r0]
	bic		r1, r1, #0xff
	bic		r1, r1, #(0x7<<8)
	orr		r1, r1, #0x470	; REFCNT135
	str     r1, [r0]
	nop
	nop
	nop
	nop
	nop
	mov     pc, lr

CLKDIV144
	ldr     r0, = CLKDIVN
	ldr     r1, = 0x4		; 0x4 = 1:4:4
	str     r1, [r0]
;	wait until clock is stable
	nop
	nop
	nop
	nop
	nop

	ldr     r0, = REFRESH
	ldr     r1, [r0]
	bic		r1, r1, #0xff
	bic		r1, r1, #(0x7<<8)
	orr		r1, r1, #0x630	; REFCNT675 - 1520
	str     r1, [r0]
	nop
	nop
	nop
	nop
	nop
	mov     pc, lr


	ALIGN

	AREA RamData, DATA, READWRITE

	^   _ISR_STARTADDRESS		; _ISR_STARTADDRESS=0x33FF_FF00
HandleReset 	#   4
HandleUndef 	#   4
HandleSWI		#   4
HandlePabort    #   4
HandleDabort    #   4
HandleReserved  #   4
HandleIRQ		#   4
HandleFIQ		#   4

;Do not use the label 'IntVectorTable',
;The value of IntVectorTable is different with the address you think it may be.
;IntVectorTable
;@0x33FF_FF20
HandleEINT0		#   4
HandleEINT1		#   4
HandleEINT2		#   4
HandleEINT3		#   4
HandleEINT4_7	#   4
HandleEINT8_23	#   4
HandleCAM		#   4		; Added for 2440.
HandleBATFLT	#   4
HandleTICK		#   4
HandleWDT		#   4
HandleTIMER0 	#   4
HandleTIMER1 	#   4
HandleTIMER2 	#   4
HandleTIMER3 	#   4
HandleTIMER4 	#   4
HandleUART2  	#   4
;@0x33FF_FF60
HandleLCD 		#   4
HandleDMA0		#   4
HandleDMA1		#   4
HandleDMA2		#   4
HandleDMA3		#   4
HandleMMC		#   4
HandleSPI0		#   4
HandleUART1		#   4
HandleNFCON		#   4		; Added for 2440.
HandleUSBD		#   4
HandleUSBH		#   4
HandleIIC		#   4
HandleUART0 	#   4
HandleSPI1 		#   4
HandleRTC 		#   4
HandleADC 		#   4
;@0x33FF_FFA0
	END
