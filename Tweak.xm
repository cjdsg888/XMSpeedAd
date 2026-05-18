/*
 * XMSpeedAd — 喜马拉雅广告加速插件
 * 方案A: 自动检测广告, 32 倍速静音播放
 *
 * 工作原理:
 * 1. 每隔 0.8 秒扫描当前界面 ViewController 层级
 * 2. 识别广告 VC / 广告 View (关键词匹配类名)
 * 3. 广告活跃期间:
 *    - hook AVPlayer.setRate:   强制为 32 倍速
 *    - hook AVPlayer.setVolume: 强制为 0 (静音)
 *    - hook AVAudioPlayer 同
 * 4. 广告消失后恢复正常
 *
 * 编译: make clean && make package
 */

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

#pragma mark - 广告状态检测器

@interface XMAdDetector : NSObject
@property (atomic, assign) BOOL adActive;       // 当前是否检测到广告
@property (atomic, weak)   NSString *adSource;  // 检测到的广告来源(debug)
+ (instancetype)shared;
- (void)start;
- (void)stop;
@end

@implementation XMAdDetector

+ (instancetype)shared {
    static XMAdDetector *inst;
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

- (void)stop {
    self.adActive = NO;
    self.adSource = nil;
}

// ---------- 扫描逻辑 ----------

- (void)scan {
    UIViewController *top = [self topMostViewController];
    BOOL found = NO;

    if (top) {
        NSString *vcName = NSStringFromClass([top class]);
        found = [self isAdRelatedName:vcName];
        if (found) {
            self.adSource = vcName;
        } else {
            found = [self viewContainsAd:top.view depth:4];
        }
    }

    if (found != self.adActive) {
        if (found) {
            NSLog(@"[XMSpeedAd] 广告开始: %@", self.adSource ?: @"unknown");
        } else {
            NSLog(@"[XMSpeedAd] 广告结束, 恢复正常");
        }
    }
    self.adActive = found;
}

// ---------- 命名匹配 ----------

- (BOOL)isAdRelatedName:(NSString *)name {
    if (!name) return NO;
    NSArray *keywords = @[
        @"Ad", @"ad", @"AD",
        @"Splash", @"splash",
        @"Interstitial",
        @"Reward", @"reward",
        @"GDT",              // 腾讯广点通
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
    for (NSString *kw in keywords) {
        if ([name containsString:kw]) return YES;
    }
    return NO;
}

- (BOOL)viewContainsAd:(UIView *)view depth:(int)depth {
    if (depth <= 0) return NO;
    NSString *cls = NSStringFromClass([view class]);
    if ([self isAdRelatedName:cls]) return YES;

    // 常见广告 SDK 容器 View 类名后缀
    if ([cls containsString:@"NativeAd"] ||
        [cls containsString:@"AdView"]    ||
        [cls containsString:@"AdContainer"]) {
        return YES;
    }

    for (UIView *sub in view.subviews) {
        if ([self viewContainsAd:sub depth:depth - 1]) return YES;
    }
    return NO;
}

// ---------- 取最上层 VC ----------

- (UIViewController *)topMostViewController {
    UIWindow *keyWindow = nil;

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in [(UIWindowScene *)scene windows]) {
                    if (w.isKeyWindow) { keyWindow = w; break; }
                }
            }
        }
    }
    if (!keyWindow) keyWindow = UIApplication.sharedApplication.keyWindow;

    return [self topFrom:keyWindow.rootViewController];
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

#pragma mark - AVPlayer 系列 Hook

%hook AVPlayer

// 截获 rate 设置 — 广告活跃时强制 32 倍
- (void)setRate:(float)rate {
    if ([XMAdDetector shared].adActive) {
        %orig(32.0);
    } else {
        %orig;
    }
}

// 截获音量设置 — 广告活跃时强制静音
- (void)setVolume:(float)volume {
    if ([XMAdDetector shared].adActive) {
        %orig(0.0);
    } else {
        %orig;
    }
}

// 开始播放时也强制设一次
- (void)play {
    %orig;
    if ([XMAdDetector shared].adActive) {
        self.rate = 32.0;
        self.volume = 0.0;
        NSLog(@"[XMSpeedAd] AVPlayer 强制 32x 静音");
    }
}

%end

%hook AVQueuePlayer
// AVQueuePlayer 继承自 AVPlayer，但单独 hook 确保覆写的情况下也生效
- (void)play {
    %orig;
    if ([XMAdDetector shared].adActive) {
        self.rate = 32.0;
        self.volume = 0.0;
    }
}
%end

#pragma mark - AVAudioPlayer Hook

%hook AVAudioPlayer

- (BOOL)play {
    if ([XMAdDetector shared].adActive) {
        self.enableRate = YES;
        self.rate = 32.0;
        self.volume = 0.0;
        NSLog(@"[XMSpeedAd] AVAudioPlayer 强制 32x 静音");
    }
    return %orig;
}

- (void)setRate:(float)rate {
    if ([XMAdDetector shared].adActive) {
        self.enableRate = YES;
        %orig(32.0);
    } else {
        %orig;
    }
}

- (void)setVolume:(float)volume {
    if ([XMAdDetector shared].adActive) {
        %orig(0.0);
    } else {
        %orig;
    }
}

%end

#pragma mark - 插件入口

%ctor {
    NSLog(@"[XMSpeedAd] ═══════════════════════════");
    NSLog(@"[XMSpeedAd] 插件加载成功");
    NSLog(@"[XMSpeedAd] 3 秒后启动广告检测...");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[XMAdDetector shared] start];
        NSLog(@"[XMSpeedAd] 广告检测已启动 (每 0.8s 扫描一次)");
    });
}
