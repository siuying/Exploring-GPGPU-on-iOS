//
//  LinearTests.m
//  ExploringGPGPU
//
//  Created by Francis Chong on 23/1/2017.
//  Copyright © 2017 Bartosz Ciechanowski. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <GLKit/GLKit.h>

#import "Tester.h"
#import "LinearTester.h"
#import "IterativeTester.h"

const int Count = 1 << 24;
const int ProfileIterations = 8;

@interface LinearTests : XCTestCase {
    GLuint gpuReadBuffer;
    GLuint gpuWriteBuffer;
    GLuint vao;

    float *cpuReadBuffer;
    float *cpuWriteBuffer;
}

@property (nonatomic, strong) EAGLContext *context;
@property (nonatomic, strong) Tester *tester;

@end

@implementation LinearTests

- (void)setUp {
    [super setUp];

    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (!self.context) {
        XCTFail(@"This application requires OpenGL ES 3.0");
    }

    GLKView *view = [[GLKView alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)];
    view.context = self.context;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat24;

    [EAGLContext setCurrentContext:self.context];

    self.tester = [IterativeTester new];

    self.tester.valuesCount = Count;
    [self.tester loadShaders];

    [self setupCPUBuffers];
    [self setupGPUBuffers];
    [self fillBuffers];
}

- (void)tearDown {
    [super tearDown];

    glBindBuffer(GL_ARRAY_BUFFER, gpuWriteBuffer);
    float *gpuMemoryBuffer = glMapBufferRange(GL_ARRAY_BUFFER, 0, sizeof(float) * Count, GL_MAP_READ_BIT);

    [self compareCPUBuffer:cpuWriteBuffer withGPUBuffer:gpuMemoryBuffer];

    glUnmapBuffer(GL_ARRAY_BUFFER);
}

- (void)testCPU {
    [self measureBlock:^{
        [self.tester calculateCPUWithReadBuffer:cpuReadBuffer writeBuffer:cpuWriteBuffer count:262144];
    }];
}

- (void)testGPU {
    // warm up gpu
    [self.tester calculateGPUWithReadVAO:vao writeBuffer:gpuWriteBuffer count:128];

    [self measureBlock:^{
        [self.tester calculateGPUWithReadVAO:vao writeBuffer:gpuWriteBuffer count:262144];
    }];
}


- (void)setupCPUBuffers
{
    cpuReadBuffer = malloc(sizeof(float) * Count);
    cpuWriteBuffer = malloc(sizeof(float) * Count);
}

- (void)setupGPUBuffers
{
    glGenBuffers(1, &gpuReadBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, gpuReadBuffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(float) * Count, cpuReadBuffer, GL_STREAM_DRAW);

    glGenVertexArraysOES(1, &vao);
    glBindVertexArrayOES(vao);

    int vectorOutputs = [self.tester vectorOutputs];

    for (int i = 0; i < vectorOutputs; i++) {
        glEnableVertexAttribArray(i);
        glVertexAttribPointer(i, 4, GL_FLOAT, GL_FALSE, (4 * vectorOutputs) * sizeof(float), (void *)(i * 4 * sizeof(float)));
    }
    glBindVertexArrayOES(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);


    glGenBuffers(1, &gpuWriteBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, gpuWriteBuffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(float) * Count, NULL, GL_STREAM_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

- (void)fillBuffers
{
    glBindBuffer(GL_ARRAY_BUFFER, gpuReadBuffer);
    float *gpuRead = glMapBufferRange(GL_ARRAY_BUFFER, 0, sizeof(float) * Count, GL_MAP_WRITE_BIT);

    [self.tester fillCPUBuffer:cpuReadBuffer GPUBuffer:gpuRead];

    glUnmapBuffer(GL_ARRAY_BUFFER);
}

- (void)compareCPUBuffer:(float *)cpuBuffer withGPUBuffer:(float *)gpuBuffer
{
    union Float_t {
        float f;
        int32_t i;
    };

    BOOL isCalculationCorrect = YES;

    float errorSum = 0.0f;
    float maxError = 0.0f;
    float minError = MAXFLOAT;

    int32_t ULPsum = 0;
    int32_t maxULP = 0;
    int32_t minULP = INT32_MAX;

    union Float_t cpu, gpu;

    for (int i = 0; i < Count; i++) {

        cpu.f = cpuBuffer[i];
        gpu.f = gpuBuffer[i];

        float error = fabsf((cpu.f - gpu.f)/cpu.f);

        maxError = MAX(maxError, error);
        minError = MIN(minError, error);

        errorSum += error;


        if ((cpu.i >> 31 != 0) != (gpu.i >> 31 != 0) ) {
            if (cpu.f != gpu.f) {
                isCalculationCorrect = NO; // different sings, can't compare, sorry
            }
        }

        int32_t ulpError = abs(cpu.i - gpu.i);
        maxULP = MAX(maxULP, ulpError);
        minULP = MIN(minULP, ulpError);

        ULPsum += ulpError;
    }

    if (isCalculationCorrect) {
        printf("ULP: avg:%g max: %d, min: %d\n", (double)ULPsum/Count, maxULP, minULP);
    } else {
        printf("WARNING: the ULP error evaluation failed due to sign mismatch\n");
    }

    printf("FLT: avg:%g max: %g, min: %g\n", errorSum/Count, maxError, minError);
}

@end
