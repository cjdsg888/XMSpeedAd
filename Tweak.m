/*
 * XMSpeedAd — 喜马拉雅广告加速插件
 * 方案 A: 检测到广告时 32 倍速 + 静音
 *
 * 零外部依赖, 纯 Objective-C runtime hook
 * 编译: clang -arch arm64 -fobjc-arc ... (详见 Makefile / GitHub Actions)
 */

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#pragma mark - 广告检测器

@interface XMAdDetector : NSObject
@property (atomic, assign) BOOL adActive;
+ (instancetype)shared;
- (void)start;
@end

@implementation XMAdDetector

+ (instancetype)shared {
    static id inst;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ inst = [[self alloc] init]; });
    return inst;
}

- (void)start {
    [self scan];
    [NSTimer scheduledTimerWithTimeInterval:0.8
                                     target:self
                                   selector:@selector(scan)
                                   userInfo:nil
                                    repeats:YES];
}

// 每次扫描: 取最上层 VC → 判断类名是否广告相关 → 递归检查子 View
- (void)scan {
    UIViewController *top = [self topVC];
    BOOL found = NO;
    if (top) {
        found = [self isAdName:NSStringFromClass([top class])];
        if (!found) found = [self viewHasAd:top.view depth:4];
    }
    if (found != self.adActive) {
        NSLog(@"[XMSpeedAd] %s", found ? "Ad START" : "Ad END");
    }
    self.adActive = found;
}

// 广告相关类名关键词匹配
- (BOOL)isAdName:(NSString *)n {
    if (!n) return NO;
    NSArray *kws = @[
        @"Ad", @"ad", @"AD",
        @"Splash", @"splash",
        @"Interstitial",
        @"Reward",
        @"GDT",              // 广点通
        @"BUNative", @"BUAd", // 穿山甲
        @"KSAd",             // 快手
        @"XMAd",
        @"FeedAd", @"ExpressAd",
        @"IXAd",
        @"CommerceAd",
        @"Advertisement",
        @"UnionAd",
        @"开屏", @"广告", @"插屏",
    ];
    for (NSString *k in kws)
        if ([n containsString:k]) return YES;
    return NO;
}

// 递归扫描子 View 是否有广告
- (BOOL)viewHasAd:(UIView *)v depth:(int)d {
    if (d <= 0) return NO;
    NSString *cls = NSStringFromClass([v class]);
    if ([self isAdName:cls]) return YES;
    if ([cls containsString:@"NativeAd"] ||
        [cls containsString:@"AdView"]    ||
        [cls containsString:@"AdContainer"])
        return YES;
    for (UIView *s in v.subviews)
        if ([self viewHasAd:s depth:d - 1]) return YES;
    return NO;
}

// 获取最上层 ViewController (支持 SceneDelegate)
- (UIViewController *)topVC {
    UIWindow *w = nil;
    // 用 NSClassFromString 替代 @available, 避免 __isPlatformVersionAtLeast
    Class sceneClass = NSClassFromString(@"UIWindowScene");
    if (sceneClass) {
        id scenes = UIApplication.sharedApplication.connectedScenes;
        for (id s in scenes)
            if ([s isKindOfClass:sceneClass])
                for (UIWindow *ww in [(id)s windows])
                    if (ww.isKeyWindow) { w = ww; break; }
    }
    if (!w) w = UIApplication.sharedApplication.keyWindow;
    return [self topFrom:w.rootViewController];
}

- (UIViewController *)topFrom:(UIViewController *)vc {
    if (!vc) return nil;
    if (vc.presentedViewController)
        return [self topFrom:vc.presentedViewController];
    if ([vc isKindOfClass:[UINavigationController class]])
        return [self topFrom:[(UINavigationController *)vc topViewController]];
    if ([vc isKindOfClass:[UITabBarController class]])
        return [self topFrom:[(UITabBarController *)vc selectedViewController]];
    return vc;
}

@end

#pragma mark - Method Hooking (纯 runtime, 0 外部依赖)

static IMP orig_AVPlayer_play;
static IMP orig_AVPlayer_setRate;
static IMP orig_AVPlayer_setVolume;
static IMP orig_AVAudioPlayer_play;
static IMP orig_AVAudioPlayer_setRate;
static IMP orig_AVAudioPlayer_setVolume;

static void hookInstanceMethod(Class cls, SEL sel, IMP newIMP, IMP *outOrig) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    *outOrig = method_getImplementation(m);
    method_setImplementation(m, newIMP);
}

__attribute__((constructor)) static void initialize() {
    NSLog(@"[XMSpeedAd] Loading...");

    // ====== AVPlayer hooks ======
    hookInstanceMethod([AVPlayer class], @selector(play),
        imp_implementationWithBlock(^(id self, SEL _cmd) {
            ((void(*)(id,SEL))orig_AVPlayer_play)(self, _cmd);
            if ([XMAdDetector shared].adActive) {
                [self setRate:32.0];
                [self setVolume:0.0];
            }
        }),
        (IMP *)&orig_AVPlayer_play);

    hookInstanceMethod([AVPlayer class], @selector(setRate:),
        imp_implementationWithBlock(^(id self, SEL _cmd, float rate) {
            ((void(*)(id,SEL,float))orig_AVPlayer_setRate)(
                self, _cmd, [XMAdDetector shared].adActive ? 32.0 : rate);
        }),
        (IMP *)&orig_AVPlayer_setRate);

    hookInstanceMethod([AVPlayer class], @selector(setVolume:),
        imp_implementationWithBlock(^(id self, SEL _cmd, float vol) {
            ((void(*)(id,SEL,float))orig_AVPlayer_setVolume)(
                self, _cmd, [XMAdDetector shared].adActive ? 0.0 : vol);
        }),
        (IMP *)&orig_AVPlayer_setVolume);

    // ====== AVAudioPlayer hooks ======
    hookInstanceMethod([AVAudioPlayer class], @selector(play),
        imp_implementationWithBlock(^BOOL(id self, SEL _cmd) {
            if ([XMAdDetector shared].adActive) {
                [self setEnableRate:YES];
                [self setRate:32.0];
                [self setVolume:0.0];
            }
            return ((BOOL(*)(id,SEL))orig_AVAudioPlayer_play)(self, _cmd);
        }),
        (IMP *)&orig_AVAudioPlayer_play);

    hookInstanceMethod([AVAudioPlayer class], @selector(setRate:),
        imp_implementationWithBlock(^(id self, SEL _cmd, float rate) {
            if ([XMAdDetector shared].adActive) {
                [self setEnableRate:YES];
                ((void(*)(id,SEL,float))orig_AVAudioPlayer_setRate)(self, _cmd, 32.0);
            } else {
                ((void(*)(id,SEL,float))orig_AVAudioPlayer_setRate)(self, _cmd, rate);
            }
        }),
        (IMP *)&orig_AVAudioPlayer_setRate);

    hookInstanceMethod([AVAudioPlayer class], @selector(setVolume:),
        imp_implementationWithBlock(^(id self, SEL _cmd, float vol) {
            ((void(*)(id,SEL,float))orig_AVAudioPlayer_setVolume)(
                self, _cmd, [XMAdDetector shared].adActive ? 0.0 : vol);
        }),
        (IMP *)&orig_AVAudioPlayer_setVolume);

    // 延迟启动检测, 给应用初始化时间
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[XMAdDetector shared] start];
        NSLog(@"[XMSpeedAd] 广告检测已启动 (每 0.8s 扫描)");
    });
}
