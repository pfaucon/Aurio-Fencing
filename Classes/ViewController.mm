//
//  ViewController.m
//  aurioTouch
//
//  Created by PFaucon on 4/17/15.
//
//  Image stolen from http://vignette2.wikia.nocookie.net/hanna-barbera/images/c/c4/TOUCHE_TURTLE_2.jpg/revision/latest?cb=20110723092503

#import "ViewController.h"
#import "EAGLView.h"

@interface ViewController ()
@end

@implementation ViewController

NSTimer* mainTimer;
// counts touche duration
int ToucheCount = 0;
// Baseline Amplitude is used to make my touche calculation work
float baselineAmplitude = 0;
// AmpFactor is actually a threshhold. Both variables are used to determine whether the signal is a touche or not.
// Decrease AmpFactor for more leniency
// Increase FreqFactor for more leniency
const float AmpFactor = 25, FreqFactor = 0.01;

- (void)viewDidLoad {
    [super viewDidLoad];
    [self startCheckingValue];
    _OutFreqField.text = [[NSString alloc] initWithFormat:@"%d", ABS((int) (arc4random()%7001+3000))];
    [_glView ChangeFreq:[[_OutFreqField text] floatValue]];
    // Do any additional setup after loading the view.
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

-(void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

// The whole "resignfirstresponder" thing isn't working. Dunno why.
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [_glView ChangeFreq:[[_OutFreqField text] floatValue]];
    [textField resignFirstResponder];
    return YES;
}

// Zeroes out the amplitude input
- (IBAction)EstablishBaseline:(id)sender {
    float frequency = 0, amplitude = 0;
    _InFreqLabel.text = [_glView GetInput:frequency :amplitude];
    baselineAmplitude = -amplitude;
}

// stolen from http://stackoverflow.com/questions/11636461/continuously-check-for-data-method-ios
-(void)startCheckingValue
{
    mainTimer = [NSTimer timerWithTimeInterval:.01 target:self selector:@selector(checkValue:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:mainTimer forMode:NSDefaultRunLoopMode];
}

-(void)checkValue:(NSTimer *)mainTimer
{
    float frequency, amplitude = baselineAmplitude;
    _InFreqLabel.text = [_glView GetInput:frequency :amplitude];
    
    // Touche detection logic
    if (amplitude > AmpFactor && ABS(frequency-[[_OutFreqField text] floatValue]) < frequency*FreqFactor) {
        ToucheCount++;
        _LastTouchDurationLabel.text = [[NSString alloc] initWithFormat:@"Last Touche Duration: %f", ToucheCount*.01];
        if (ToucheCount >= 10)
            _ToucheImageView.alpha = 1;
        //NSLog(@"%d",ToucheCount);
    } else {
        ToucheCount = 0;
        _ToucheImageView.alpha = 0;
    }
}

@end
