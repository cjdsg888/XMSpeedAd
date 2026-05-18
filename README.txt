XMSpeedAd — 喜马拉雅广告加速插件
===================================

方案: 检测到广告时自动 32 倍速 + 静音播放
适配版本: 喜马拉雅 9.4.69

==== 项目文件说明 ====

  XMSpeedAd/
    ├── Makefile     — Theos 编译配置
    ├── Tweak.xm     — 核心 Logos 源码
    ├── control      — 包信息
    └── README.txt   — 本文件

==== 编译方法 ====

方式一: Theos (推荐, macOS / Linux)
  1. 确认已安装 Theos (https://theos.dev/docs/installation)
  2. 确保环境变量 $THEOS 正确指向 Theos 路径
  3. cd XMSpeedAd/
  4. make clean && make package
  5. 编译产物: .theos/obj/debug/XMSpeedAd.dylib

方式二: GitHub Actions (无需本地环境)
  搜索 "theos build action" 用 GitHub 免费 CI 编译

方式三: 在线 Theos 编译
  可以使用云编译服务编译得到 .dylib

==== 注入方法 ====

将编译得到的 XMSpeedAd.dylib 与喜马拉雅 IPA 放一起,
使用注入器 (如 Azule, 巨魔注入器等) 打进 IPA 并重签名安装.

==== 工作原理 ====

1. 每 0.8 秒扫描当前界面的 ViewController
2. 通过类名关键词匹配识别广告 (Ad/Splash/GDT/BUNative 等)
3. 检测到广告时:
   - Hook AVPlayer.setRate:   → 强制 32 倍速
   - Hook AVPlayer.setVolume: → 强制 0 (静音)
   - Hook AVAudioPlayer 同理
4. 广告消失后恢复正常播放

==== 常见问题 ====

Q: 检测不到广告?
A: 喜马拉雅不同版本的广告类名可能不同, 可自行在 Tweak.xm
   的 -isAdRelatedName: 方法中添加新的关键词.

Q: 加速后广告还在播放?
A: 部分广告使用自定义播放器(非 AVPlayer), 可通过
   class-dump 获取具体类名后再补充 hook.

Q: 编译报错?
A: 确认 Theos 版本和 iOS SDK 路径正确.
