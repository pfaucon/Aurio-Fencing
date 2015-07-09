
// Framework includes
#import <UIKit/UIKit.h>

// Local includes
#import "AudioController.h"

@interface FrequencyManager : NSObject

@property (nonatomic) double frequency;
@property double theta;
@property AudioController *audioController;

- (NSString *)GetInput:(float&)frequency :(float&)amplitude;

@end
