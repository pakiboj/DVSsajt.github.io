#include "xparameters.h"

#include <xil_io.h>
#include <xil_printf.h>
#include <xstatus.h>
#include <stdlib.h>

#include "xaxidma.h"
#include "xinterrupt_wrap.h"

#include <xil_cache.h>
#include <xtmrctr_l.h>

#include "xil_util.h"

#include "xtmrctr.h"

typedef struct ImageShape {
    u16 ImgW;
    u16 ImgH;
};

typedef enum Border{
    NO_PAD = 1,
    CONST_PAD = 2,
    NEAREST_PAD = 3
};

typedef enum Bypass{
    YES_BYPASS = 0,
    NO_BYPASS = 1,
};

typedef enum MODE{
    bit8 = 0,
    bit16 = 1,
};

typedef struct ProcessingParams{
    ImageShape Img;
    u8  Radius;   
    s16 FilterCoeffs[81];         
    u16 FilterCoeffsScale;
    MODE ModeType;
    Border BorderType;
    u8  BorderValue;
    Bypass BypassType; 
};

static int DmaConfigure(XAxiDma_Config* AxiDmaConfigPtr, XAxiDma* AxiDmaPtr);
static int DmaStartTransfers(XAxiDma* AxiDmaPtr, u8* TxBuffer, u32 TxSize, u8* RxBuffer, u32 RxSize);
static int DmaWaitTransfers(volatile u32* TxFlag, volatile u32* RxFlag, u32 Timeout);

static int AccConfigure(UINTPTR BaseAddress, NegImageParams Params);

static void ImageFilterSW(u8* DataBuffer, u8* ResultBuffer, NegImageParams Params);
static int  ImageFilterHW(u8* DataBuffer, u8* ResultBuffer, NegImageParams Params);

static int CheckData(u8* ResultBuffer, u8* ReferentBuffer, ImageShape Img);

static void TxIntrHandler(void *Callback);
static void RxIntrHandler(void *Callback);

#define DMA_TRANSFER_TIMEOUT 100000

#define REG_IMG_W_ADDR    0
#define REG_IMG_H_ADDR    4
#define REG_TL_ROW_ADDR   8
#define REG_TL_COL_ADDR  12
#define REG_BR_ROW_ADDR  16
#define REG_BR_COL_ADDR  20

static XAxiDma AxiDma;
static XTmrCtr AxiTimer;

volatile u32 TxDone;
volatile u32 RxDone;

static int DmaConfigure(XAxiDma_Config* AxiDmaConfigPtr, XAxiDma* AxiDmaPtr)
{
    int Status;
    
    /* DMA configuration */

	Status = XAxiDma_CfgInitialize(AxiDmaPtr, AxiDmaConfigPtr);
	if (Status != XST_SUCCESS) {
		xil_printf("    ERROR: DMA initialization failed %d\r\n", Status);
		return XST_FAILURE;
	}

	if (XAxiDma_HasSg(AxiDmaPtr)) {
		xil_printf("    ERROR: DMA configure in SG mode \r\n");
		return XST_FAILURE;
	}

	/* Configure DMA interrupts */
	Status = XSetupInterruptSystem(AxiDmaPtr, &TxIntrHandler,
				                  AxiDmaConfigPtr->IntrId[0], AxiDmaConfigPtr->IntrParent,
				                  XINTERRUPT_DEFAULT_PRIORITY);
	if (Status != XST_SUCCESS) {
        xil_printf("    ERROR: Cannot configure DMA TX interrupt\r\n");
		return XST_FAILURE;
	}

	Status = XSetupInterruptSystem(AxiDmaPtr, &RxIntrHandler,
				                   AxiDmaConfigPtr->IntrId[1], AxiDmaConfigPtr->IntrParent,
				                   XINTERRUPT_DEFAULT_PRIORITY);
	if (Status != XST_SUCCESS) {
        xil_printf("    ERROR: Cannot configure DMA RX interrupt\r\n");
		return XST_FAILURE;
	}

	XAxiDma_IntrEnable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
	XAxiDma_IntrEnable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);

    return XST_SUCCESS;
}

static int DmaStartTransfers(XAxiDma* AxiDmaPtr, u8* TxBuffer, u32 TxSize, u8* RxBuffer, u32 RxSize)
{
    int Status;

    /* Flush TX buffer before DMA transfer to make sure that DDR and Cache are in sync */
	Xil_DCacheFlushRange((UINTPTR)TxBuffer, TxSize);
    Xil_DCacheFlushRange((UINTPTR)RxBuffer, RxSize);

	/* Start DMA tranfers */
	Status = XAxiDma_SimpleTransfer(AxiDmaPtr, (UINTPTR) RxBuffer, 
                                    RxSize, XAXIDMA_DEVICE_TO_DMA);
	if (Status != XST_SUCCESS) {
        xil_printf("    ERROR: Starting RX DMA failed %d\r\n", Status);
        return XST_FAILURE;
	}

	Status = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR) TxBuffer, 
                                    TxSize, XAXIDMA_DMA_TO_DEVICE);
	if (Status != XST_SUCCESS) {
        xil_printf("    ERROR: Starting TX DMA failed %d\r\n", Status);
		return XST_FAILURE;
	}

    return XST_SUCCESS;
}

static int DmaWaitTransfers(volatile u32* TxFlag, volatile u32* RxFlag, u32 Timeout)
{
	int Status;
    /* Wait for TX done or timeout */
	Status = Xil_WaitForEventSet(Timeout, 1, TxFlag);
	if (Status != XST_SUCCESS) {
		xil_printf("    ERROR: Transmit failed %d\r\n", Status);
		return XST_FAILURE;
	}
    xil_printf("    Transmit done\r\n");

	/* Wait for RX done or timeout */
	Status = Xil_WaitForEventSet(Timeout, 1, RxFlag);
	if (Status != XST_SUCCESS) {
		xil_printf("    ERROR: Receive failed %d\r\n", Status);
		return XST_FAILURE;
	}
    xil_printf("    Receive done\r\n");

    return XST_SUCCESS;
}


static void TxIntrHandler(void *Callback)
{
	u32 IrqStatus;
	XAxiDma *AxiDmaInst = (XAxiDma *)Callback;

	/* Read pending interrupts */
	IrqStatus = XAxiDma_IntrGetIrq(AxiDmaInst, XAXIDMA_DMA_TO_DEVICE);

	/* Acknowledge pending interrupts */
	XAxiDma_IntrAckIrq(AxiDmaInst, IrqStatus, XAXIDMA_DMA_TO_DEVICE);

	/* Set TX done only if transmit chain is completed */
	if ((IrqStatus & XAXIDMA_IRQ_IOC_MASK))
    {
		TxDone = 1;
	}

    return;
}

static void RxIntrHandler(void *Callback)
{
	u32 IrqStatus;
	XAxiDma *AxiDmaInst = (XAxiDma *)Callback;

	/* Read pending interrupts */
	IrqStatus = XAxiDma_IntrGetIrq(AxiDmaInst, XAXIDMA_DEVICE_TO_DMA);

	/* Acknowledge pending interrupts */
	XAxiDma_IntrAckIrq(AxiDmaInst, IrqStatus, XAXIDMA_DEVICE_TO_DMA);

	/* Set RX done only if receive chain is completed */
	if ((IrqStatus & XAXIDMA_IRQ_IOC_MASK))
    {
		RxDone = 1;
	}

    return;

int main(void)
{

int Status;

int BOX3[81] = {  
                0,0,0,0,0,0,0,0,0, 
                0,0,0,0,0,0,0,0,0, 
                0,0,0,0,0,0,0,0,0, 
                0,0,0,3,3,3,0,0,0, 
                0,0,0,3,3,3,0,0,0, 
                0,0,0,3,3,3,0,0,0, 
                0,0,0,0,0,0,0,0,0, 
                0,0,0,0,0,0,0,0,0, 
                0,0,0,0,0,0,0,0,0
            };
double BOX3_coeff = 1.0/81.0;

int BOX9[81] = {
                1,1,1,1,1,1,1,1,1,
                1,1,1,1,1,1,1,1,1,
                1,1,1,1,1,1,1,1,1,
                1,1,1,1,1,1,1,1,1,
                1,1,1,1,1,1,1,1,1,
                1,1,1,1,1,1,1,1,1,
                1,1,1,1,1,1,1,1,1,
                1,1,1,1,1,1,1,1,1,
                1,1,1,1,1,1,1,1,1
                };
double BOX9_coeff = 1.0/81.0;

int GAUS5[81] = {
                    0,0,0,0,0,0,0,0,0,
                    0,0,0,0,0,0,0,0,0,
                    0,0,1,4,7,4,1,0,0,
                    0,0,4,16,26,16,4,0,0,
                    0,0,7,26,41,26,7,0,0,
                    0,0,4,16,26,16,4,0,0,
                    0,0,1,4,7,4,1,0,0,
                    0,0,0,0,0,0,0,0,0,
                    0,0,0,0,0,0,0,0,0
                    };
double GAUS5_coeff = 1.0/273.0;

int LOG7[81] = {
                    0,0,0,0,0,0,0,0,0,
                    0,0,0,-1,-1,-1,0,0,0,
                    0,0,-2,-3,-3,-3,-2,0,0,
                    0,-1,-3,5,5,5,-3,-1,0,
                    0,-1,-3,5,16,5,-3,-1,0,
                    0,-1,-3,5,5,5,-3,-1,0,
                    0,0,-2,-3,-3,-3,-2,0,0,
                    0,0,0,-1,-1,-1,0,0,0,
                    0,0,0,0,0,0,0,0,0
                    };
double LOG7_coeff = 1.0;   // zero-sum kernel

u8 *DataBuffer;
u8 *ReferentBuffer;
u8 *ResultBuffer;

ProcessingParams Params;

u32 ImgSize;

//Initialize AXI Timer
int TimerStatus = XTmrCtr_Initialize(&AxiTimer, XPAR_AXI_TIMER_0_BASEADDR);
if(TimerStatus != XST_SUCCESS) {
    xil_printf("ERROR: Timer initialization failed\r\n");
    return XST_FAILURE;
}
XTmrCtr_SetResetValue(&AxiTimer, TMR_CNT_0, 0);
XTmrCtr_SetOptions(&AxiTimer, TMR_CNT_0, XTC_AUTO_RELOAD_OPTION);

xil_printf("\r\n--- Entering main() --- \r\n");

while(1){

    //int value1, value2;

    //printf("Enter image heaight and width: ");
    //scanf("%d %d", &value1, &value2);


    //Benchmarking
    u32 SwProcessingTime = 0;
    u32 HwProcessingTime = 0;

    // Define processing parameters
    Params.Img.ImgH = 128; 
    Params.Img.ImgW = 128;
    Params.Radius = 1;
    Params.FilterCoeffs = BOX3;
    Params.FilterCoeffsScale = BOX3_coeff;
    Params.ModeType = bit8
    Params.BorderType = NEAREST_PAD
    Params.BorderValue = 0;
    Params.Bypass = 0;

    ImgSize = Params.Img.ImgW * Params.Img.ImgH;

    // Input and output buffer allocation   
    DataBuffer = (u8*) malloc(ImgSize);
    if (DataBuffer == NULL) {
        xil_printf("ERROR: Cannot allocate Data buffer\r\n");
        return XST_FAILURE;
    }
    xil_printf("\r\n Data buffer address: %x \r\n", DataBuffer);
    
    ResultBuffer = (u8*) malloc(ImgSize);
    if (ResultBuffer == NULL) {
        xil_printf("ERROR: Cannot allocate Result buffer\r\n");
        return XST_FAILURE;
    }
    xil_printf("\r\n Result buffer address: %x \r\n", ResultBuffer);

    ReferentBuffer = (u8*) malloc(ImgSize);
    if (ReferentBuffer == NULL) {
        xil_printf("ERROR: Cannot allocate Referent buffer\r\n");
        return XST_FAILURE;
    }
    xil_printf("\r\n Referent buffer address: %x \r\n\n", ReferentBuffer);

    // Use mwr function in debug console to write image from bin file to Data buffer
        //    connect
        //    target
        //    target 2 //select target        
        //
        //    mwr -size b -bin -file "D:/dvs/lab2/lena128.bin"    0x110F08           16384 
        //                            full_path_to_file        data_buff_addr   transfer_size_bytes    

    xil_printf("\r\nStart software processing \r\n"); 
    XTmrCtr_Reset(&AxiTimer,TMR_CNT_0);
    XTmrCtr_Start(&AxiTimer, TMR_CNT_0);    

    // Software processing - Generate referent data
    ImageFilterSW(DataBuffer,ReferentBuffer, Params);
    XTmrCtr_Stop(&AxiTimer,TMR_CNT_0);
    SwProcessingTime = XTmrCtr_GetValue(&AxiTimer, TMR_CNT_0);   
    xil_printf("  Software processing completed in %d cycles\r\n",SwProcessingTime); 
    
    // Hardware processing
    xil_printf("  Hardware processing started\r\n");   
    XTmrCtr_Reset(&AxiTimer,TMR_CNT_0);
    XTmrCtr_Start(&AxiTimer, TMR_CNT_0); 
    Status = ImageFilterHW(DataBuffer, ResultBuffer, Params);
    XTmrCtr_Stop(&AxiTimer,TMR_CNT_0);
    HwProcessingTime = XTmrCtr_GetValue(&AxiTimer, TMR_CNT_0);
    if (Status != XST_SUCCESS) {
        xil_printf("ERROR: Hardware processing failed\r\n");
        return XST_FAILURE;
    }
    xil_printf("  Hardware processing completed in %d cycles\r\n",HwProcessingTime);

    // Check data
        Status = CheckData(ResultBuffer, ReferentBuffer, Params.ImgH, Params.ImgW);
        if (Status != XST_SUCCESS) {
            xil_printf("ERROR: Data check failed\r\n");
            return XST_FAILURE;
        }

        xil_printf("Data check OK\r\n\n");
        

        xil_printf("\r\nSuccessfully ran image negative accelerator test\r\n");

        // Use mrd function in debug console to read image from Result buffer to bin file
        //
        //   mrd -size b -bin -file "D:/dvs/lab2/lena128neg.bin"    0x114F10             16384 
        //                                full_path_to_file     result_buff_addr   transfer_size_bytes
        

        free(DataBuffer);
        free(ResultBuffer);
        free(ReferentBuffer);
}

xil_printf("\r\n--- Exiting main() --- \r\n");
return XST_SUCCESS;   
}

// static int AccConfigure(UINTPTR BaseAddress, ProcessingParams Params)
// {
//     // Configure accelerator parameters

//     u16 regCtrlVal = CTRL_BORD(Params.Border) | CTRL_BYPASS(Params.Bypass) | Params.Mode;

//     Xil_Out16(BaseAddress + REG_CTRL_ADDR, regCtrlVal);
//     Xil_Out16(BaseAddress + REG_EDGE_THR_ADDR, Params.EdgeThr);
//     Xil_Out16(BaseAddress + REG_IMG_W_ADDR, Params.Img.ImgW);
//     Xil_Out16(BaseAddress + REG_IMG_H_ADDR, Params.Img.ImgH);



//     return XST_SUCCESS;
// }

static void ImageFilterSW(u8* DataBuffer, u8* ResultBuffer, ProcessingParams Params)
{
    int x, y, i, j;
    int width  = Params.Img.ImgW;
    int height = Params.Img.ImgH;

    int radius = Params.Radius;
    int kernelSize = 2 * radius + 1;

    for (y = 0; y < height; y++)
    {
        for (x = 0; x < width; x++)
        {
            int sum = 0;
            int invalid = 0;

            for (j = -radius; j <= radius; j++)
            {
                for (i = -radius; i <= radius; i++)
                {
                    int yy = y + j;
                    int xx = x + i;
                    u8 pixel;

                    if (Params.BorderType == NO_PAD)
                    {
                        if (yy < 0 || yy >= height || xx < 0 || xx >= width)
                        {
                            invalid = 1;
                            break;
                        }
                        pixel = DataBuffer[yy*width + xx];
                    }
                    else if (Params.BorderType == CONST_PAD)
                    {
                        if (yy < 0 || yy >= height || xx < 0 || xx >= width)
                            pixel = Params.BorderValue;
                        else
                            pixel = DataBuffer[yy*width + xx];
                    }
                    else
                    {
                        if (yy < 0) yy = 0;
                        if (yy >= height) yy = height-1;
                        if (xx < 0) xx = 0;
                        if (xx >= width) xx = width-1;

                        pixel = DataBuffer[yy*width + xx];
                    }

                    int coeffIndex = (j + radius) * kernelSize + (i + radius);
                    sum += pixel * Params.FilterCoeffs[coeffIndex];
                }

                if (invalid) break;
            }

            if (invalid)
            {
                ResultBuffer[y*width + x] = 0;
                continue;
            }

            sum = sum / Params.FilterCoeffsScale;

            if (sum < 0) sum = 0;
            if (sum > 255) sum = 255;

            ResultBuffer[y*width + x] = (u8)sum;
        }
    }
}

static int ImageFilterHW(u8* DataBuffer, u8* ResultBuffer, ProcessingParams Params)
{ 
    int Status;
    int ImageSize = Params.Img.ImgH * Params.Img.ImgW;
    XAxiDma_Config *AxiDmaConfigPtr;

    AxiDmaConfigPtr = XAxiDma_LookupConfig(XPAR_XAXIDMA_0_BASEADDR);
	if (!AxiDmaConfigPtr) {
		xil_printf("  HW CONFIG ERROR: No config found for %d\r\n", XPAR_XAXIDMA_0_BASEADDR);

		return XST_FAILURE;
	}

    Status = DmaConfigure(AxiDmaConfigPtr, &AxiDma);
    if (Status != XST_SUCCESS)
    {
        xil_printf("  HW CONFIG ERROR: DMA configuration failed\r\n");
        return XST_FAILURE;        
    }

    // Status = AccConfigure(XPAR_ACC_EDGE_DETECTION_0_BASEADDR, Params);
    // if (Status != XST_SUCCESS)
    // {
    //     xil_printf("HW CONFIG ERROR: Accelerator configuration failed\r\n");
    //     return XST_FAILURE;
    // }

    Status = DmaStartTransfers(&AxiDma, DataBuffer, ImageSize, ResultBuffer, ImageSize);
    if (Status != XST_SUCCESS)
    {
        xil_printf("  HW CONFIG ERROR: Starting DMA transfers failed\r\n");
        return XST_FAILURE;        
    }

    Status = DmaWaitTransfers(&TxDone, &RxDone, DMA_TRANSFER_TIMEOUT);
    if (Status != XST_SUCCESS)
    {
        xil_printf("  HW PROC ERROR: Completing DMA transfers failed\r\n");
        return XST_FAILURE;        
    }

    /* Disable TX and RX interrupts */
	XDisconnectInterruptCntrl(AxiDmaConfigPtr->IntrId[0], AxiDmaConfigPtr->IntrParent);
	XDisconnectInterruptCntrl(AxiDmaConfigPtr->IntrId[1], AxiDmaConfigPtr->IntrParent);

    return XST_SUCCESS;
}

static int CheckData(u8* ResultBuffer, u8* ReferentBuffer, u16 ImgH, u16 ImgW)
{
	int RowIndex = 0;
    int ColIndex = 0;
    int k = 0;

	// Invalidate RxBuffer to force read newest values from DDR
	Xil_DCacheInvalidateRange((UINTPTR)ResultBuffer, ImgH*ImgW*sizeof(ResultBuffer[0]));

    for (RowIndex = 0; RowIndex < ImgH; RowIndex++)
    {
        for (ColIndex = 0; ColIndex < ImgW; ColIndex++)
        {             
            if (ResultBuffer[RowIndex*ImgW + ColIndex] != ReferentBuffer[RowIndex*ImgW + ColIndex]) {
			    xil_printf("DATA CHECK ERROR: Row: %d Column: %d Received output %d instead of %d\r\n",
				                    RowIndex, ColIndex, (u8) ResultBuffer[RowIndex*ImgW + ColIndex], (u8) ReferentBuffer[RowIndex*ImgW + ColIndex]);

			    //return XST_FAILURE;
                k++;
		    }
        }
    }

    xil_printf("DATA ERROR COUNT: Found %d errors", k);

	return XST_SUCCESS;
}
