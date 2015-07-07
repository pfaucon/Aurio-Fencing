/*
 
     File: EAGLView.mm
 Abstract: n/a
  Version: 2.0
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 
 
 */

#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGLDrawable.h>

#import "EAGLView.h"
#import "BufferManager.h"


#define USE_DEPTH_BUFFER 1
#define SPECTRUM_BAR_WIDTH 4


#ifndef CLAMP
#define CLAMP(min,x,max) (x < min ? min : (x > max ? max : x))
#endif


// value, a, r, g, b
GLfloat colorLevels[] = {
    0., 1., 0., 0., 0.,
    .333, 1., .7, 0., 0.,
    .667, 1., 0., 0., 1.,
    1., 1., 0., 1., 1.,
};

#define kMinDrawSamples 64
#define kMaxDrawSamples 4096



typedef enum aurioTouchDisplayMode {
	aurioTouchDisplayModeOscilloscopeWaveform,
	aurioTouchDisplayModeOscilloscopeFFT,
	aurioTouchDisplayModeSpectrum
} aurioTouchDisplayMode;



@interface EAGLView () {
    
    
    AudioComponentInstance toneUnit;
    
    
    
    /* The pixel dimensions of the backbuffer */
	GLint backingWidth;
	GLint backingHeight;
	
	EAGLContext *context;
	
	/* OpenGL names for the renderbuffer and framebuffers used to render to this view */
	GLuint viewRenderbuffer, viewFramebuffer;
	
	/* OpenGL name for the depth buffer that is attached to viewFramebuffer, if it exists (0 if it does not exist) */
	GLuint depthRenderbuffer;
    
	NSTimer                     *animationTimer;
	NSTimeInterval              animationInterval;
	NSTimeInterval              animationStarted;
    
    BOOL                        applicationResignedActive;
    
    UIImageView*				sampleSizeOverlay;
	UILabel*					sampleSizeText;
    
	BOOL						initted_oscilloscope, initted_spectrum;
	UInt32*						texBitBuffer;
	CGRect						spectrumRect;
	
	GLuint						bgTexture;
	GLuint						muteOffTexture, muteOnTexture;
	GLuint						fftOffTexture, fftOnTexture;
	GLuint						sonoTexture;
	
	aurioTouchDisplayMode		displayMode;
    
	UIEvent*					pinchEvent;
	CGFloat						lastPinchDist;
	Float32*					l_fftData;
	GLfloat*					oscilLine;
    
    AudioController*            audioController;
    
}
@end

@implementation EAGLView

// You must implement this
+ (Class) layerClass
{
	return [CAEAGLLayer class];
}

//The GL view is stored in the nib file. When it's unarchived it's sent -initWithCoder:
- (id)initWithCoder:(NSCoder*)coder
{
	if((self = [super initWithCoder:coder])) {
    
        audioController = [[AudioController alloc] init];
        audioController.muteAudio = true; // The tone unit is a separate entity, so I can just leave it muted and not have to figure out how to keep it from duplicating all the audio like the original AurioTouch
        l_fftData = (Float32*) calloc([audioController getBufferManagerInstance]->GetFFTOutputBufferLength(), sizeof(Float32));
        
        BufferManager* bufferManager = [audioController getBufferManagerInstance];
        displayMode = aurioTouchDisplayModeOscilloscopeFFT;
        bufferManager->SetDisplayMode(aurioTouchDisplayModeOscilloscopeFFT);
        [audioController startIOUnit];
        _frequency = 0;
        if (!toneUnit) // this code creates the tone unit
        {
            [self createToneUnit];
            
            // Stop changing parameters on the unit
            OSErr err = AudioUnitInitialize(toneUnit);
            NSAssert1(err == noErr, @"Error initializing unit: %ld", err);
            
            // Start playback
            err = AudioOutputUnitStart(toneUnit);
            NSAssert1(err == noErr, @"Error starting unit: %ld", err);
        }
    }
	return self;
}

// Used to define the frequency
- (void)ChangeFreq:(double)input {
    _frequency = input;
}

// returns the amplitude and frequency, as well as a nicely formatted string
// Yes, I am lazy and made them pointers.
- (NSString *)GetInput:(float&)frequency :(float&)amplitude
{
    if (![audioController audioChainIsBeingReconstructed])  //hold off on drawing until the audio chain has been reconstructed
    {
        BufferManager* bufferManager = [audioController getBufferManagerInstance];
        if (bufferManager->HasNewFFTData())
        {
            bufferManager->GetFFTOutput(l_fftData);
        }
        // credit goes to http://stackoverflow.com/questions/4364823/how-do-i-obtain-the-frequencies-of-each-value-in-a-fft
        Float32 *checking = (Float32*) calloc(bufferManager->GetFFTOutputBufferLength(), sizeof(Float32));
        bufferManager->GetFFTOutput(checking);
        NSMutableArray *Sorter = [[NSMutableArray alloc] initWithCapacity:bufferManager->GetFFTOutputBufferLength()];
        for (uint i = 0; i < bufferManager->GetFFTOutputBufferLength(); i++){
            [Sorter insertObject:[[NSNumber alloc] initWithDouble:checking[i]] atIndex:i];
        }
        NSSortDescriptor *sd = [[NSSortDescriptor alloc] initWithKey:nil ascending:NO];
        NSArray *sorted = [Sorter sortedArrayUsingDescriptors:@[sd]];
        
        // Now that we have the array sorted, we can find the index/frequency we want.
        // The array is double the length it needs to be, so we have to divide by 2
        uint index =[Sorter indexOfObject:[sorted objectAtIndex:0]];
        frequency = (index/2)*[audioController sessionSampleRate]/(bufferManager->GetFFTOutputBufferLength());
        amplitude += [[sorted objectAtIndex:0] floatValue];
        
        return [[NSString alloc] initWithFormat:@"Current Frequency: %d\nCurrent Amplitude: %d", (int)frequency, (int)amplitude];
    }
    return @"-1";
}

// Stop animating and release resources when they are no longer needed.
- (void)dealloc
{	
	if([EAGLContext currentContext] == context) {
		[EAGLContext setCurrentContext:nil];
	}
	context = nil;
    free(oscilLine);
}



// The rest of the code in this docuent was stolen from http://www.cocoawithlove.com/2010/10/ios-tone-generator-introduction-to.html
OSStatus RenderTone(
                    void *inRefCon,
                    AudioUnitRenderActionFlags 	*ioActionFlags,
                    const AudioTimeStamp 		*inTimeStamp,
                    UInt32 						inBusNumber,
                    UInt32 						inNumberFrames,
                    AudioBufferList 			*ioData)

{
    // Fixed amplitude is good enough for our purposes
    const double amplitude = 0.25;
    
    // Get the tone parameters out of the view controller
    EAGLView *viewController =
    (__bridge EAGLView *)inRefCon;
    double theta = viewController->_theta;
    double theta_increment = 2.0 * M_PI * viewController->_frequency / [viewController->audioController sessionSampleRate];
    
    // This is a mono tone generator so we only need the first buffer
    const int channel = 0;
    Float32 *buffer = (Float32 *)ioData->mBuffers[channel].mData;
    
    // Generate the samples
    for (UInt32 frame = 0; frame < inNumberFrames; frame++)
    {
        buffer[frame] = sin(theta) * amplitude;
        
        theta += theta_increment;
        if (theta > 2.0 * M_PI)
        {
            theta -= 2.0 * M_PI;
        }
    }
    
    // Store the theta back in the view controller
    viewController->_theta = theta;
    
    return noErr;
}

- (void)createToneUnit
{
    // Configure the search parameters to find the default playback output unit
    // (called the kAudioUnitSubType_RemoteIO on iOS but
    // kAudioUnitSubType_DefaultOutput on Mac OS X)
    AudioComponentDescription defaultOutputDescription;
    defaultOutputDescription.componentType = kAudioUnitType_Output;
    defaultOutputDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    defaultOutputDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    defaultOutputDescription.componentFlags = 0;
    defaultOutputDescription.componentFlagsMask = 0;
    
    // Get the default playback output unit
    AudioComponent defaultOutput = AudioComponentFindNext(NULL, &defaultOutputDescription);
    NSAssert(defaultOutput, @"Can't find default output");
    
    // Create a new unit based on this that we'll use for output
    OSErr err = AudioComponentInstanceNew(defaultOutput, &toneUnit);
    NSAssert1(toneUnit, @"Error creating unit: %ld", err);
    
    __weak EAGLView *weakself = self;
    // Set our tone rendering function on the unit
    AURenderCallbackStruct input;
    input.inputProc = RenderTone;
    input.inputProcRefCon = (__bridge void *)weakself;
    err = AudioUnitSetProperty(toneUnit,
                               kAudioUnitProperty_SetRenderCallback,
                               kAudioUnitScope_Input,
                               0,
                               &input,
                               sizeof(input));
    NSAssert1(err == noErr, @"Error setting callback: %ld", err);
    
    // Set the format to 32 bit, single channel, floating point, linear PCM
    const int four_bytes_per_float = 4;
    const int eight_bits_per_byte = 8;
    AudioStreamBasicDescription streamFormat;
    streamFormat.mSampleRate = [audioController sessionSampleRate];
    streamFormat.mFormatID = kAudioFormatLinearPCM;
    streamFormat.mFormatFlags =
    kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
    streamFormat.mBytesPerPacket = four_bytes_per_float;
    streamFormat.mFramesPerPacket = 1;
    streamFormat.mBytesPerFrame = four_bytes_per_float;
    streamFormat.mChannelsPerFrame = 1;
    streamFormat.mBitsPerChannel = four_bytes_per_float * eight_bits_per_byte;
    err = AudioUnitSetProperty (toneUnit,
                                kAudioUnitProperty_StreamFormat,
                                kAudioUnitScope_Input,
                                0,
                                &streamFormat,
                                sizeof(AudioStreamBasicDescription));
    NSAssert1(err == noErr, @"Error setting stream format: %ld", err);
}


@end
