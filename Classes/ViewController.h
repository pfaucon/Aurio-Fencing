//
//  ViewController.h
//  aurioTouch
//
//  Created by PFaucon on 4/17/15.
//
//

#import <UIKit/UIKit.h>
#import "FrequencyManager.h"

@class EAGLView;

@interface ViewController : UIViewController <UITextFieldDelegate>

@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) FrequencyManager *frequencyManager;
@property (weak, nonatomic) IBOutlet UILabel *InFreqLabel;
@property (weak, nonatomic) IBOutlet UILabel *LastTouchDurationLabel;
@property (weak, nonatomic) IBOutlet UIImageView *ToucheImageView;
@property (weak, nonatomic) IBOutlet UITextField *OutFreqField;
- (IBAction)EstablishBaseline:(id)sender;

@end
