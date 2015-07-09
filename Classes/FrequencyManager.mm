/*
 * This class wraps around lower level models so that we can pass in a frequency and have it generated on the output buffers.  We can also read in the top frequencies.
 */

#import "FrequencyManager.h"
#import "BufferManager.h"

@interface FrequencyManager () {
    AudioComponentInstance toneUnit;
    
    Float32*					l_fftData;
}
@end

@implementation FrequencyManager

// You must implement this
+ (Class) layerClass
{
	return [CAEAGLLayer class];
}

- (id)init
{
	if((self = [super init])) {
    
        self.audioController = [[AudioController alloc] init];
        self.audioController.muteAudio = true; // The tone unit is a separate entity, so I can just leave it muted and not have to figure out how to keep it from duplicating all the audio like the original AurioTouch
        l_fftData = (Float32*) calloc([self.audioController getBufferManagerInstance]->GetFFTOutputBufferLength(), sizeof(Float32));
        
        [self.audioController startIOUnit];
        _frequency = 0;
        if (!toneUnit) // this code creates the tone unit
        {
            [self createToneUnit];
            
            // Stop changing parameters on the unit
            OSErr err = AudioUnitInitialize(toneUnit);
            NSAssert1(err == noErr, @"Error initializing unit: %hd", err);
            
            // Start playback
            err = AudioOutputUnitStart(toneUnit);
            NSAssert1(err == noErr, @"Error starting unit: %hd", err);
        }
    }
	return self;
}

// Used to define the frequency
- (void)setFrequency:(double)frequency {
    _frequency = frequency;
}

// returns the amplitude and frequency, as well as a nicely formatted string
// Yes, I am lazy and made them pointers.
- (NSString *)GetInput:(float&)frequency :(float&)amplitude
{
    if (![self.audioController audioChainIsBeingReconstructed])  //hold off on drawing until the audio chain has been reconstructed
    {
        BufferManager* bufferManager = [self.audioController getBufferManagerInstance];
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
        NSUInteger index =[Sorter indexOfObject:[sorted objectAtIndex:0]];
        frequency = (index/2)*[self.audioController sessionSampleRate]/(bufferManager->GetFFTOutputBufferLength());
        amplitude += [[sorted objectAtIndex:0] floatValue];
        
        return [[NSString alloc] initWithFormat:@"Current Frequency: %d\nCurrent Amplitude: %d", (int)frequency, (int)amplitude];
    }
    return @"-1";
}

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
    FrequencyManager *host =
    (__bridge FrequencyManager *)inRefCon;
    double theta = host.theta;
    double theta_increment = 2.0 * M_PI * host.frequency / [host.audioController sessionSampleRate];
    
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
    host.theta = theta;
    
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
    NSAssert1(toneUnit, @"Error creating unit: %hd", err);
    
    __weak FrequencyManager *weakself = self;
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
    NSAssert1(err == noErr, @"Error setting callback: %hd", err);
    
    // Set the format to 32 bit, single channel, floating point, linear PCM
    const int four_bytes_per_float = 4;
    const int eight_bits_per_byte = 8;
    AudioStreamBasicDescription streamFormat;
    streamFormat.mSampleRate = [self.audioController sessionSampleRate];
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
    NSAssert1(err == noErr, @"Error setting stream format: %hd", err);
}


@end
