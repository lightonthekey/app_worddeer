import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // 窗口在 nib 加载阶段就被改成 430x900，Flutter 引擎拿到的仍是启动时的
    // 默认 800x600。等首帧后再做一次真实 resize，让引擎收到尺寸变更。
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
      self.setContentSize(NSSize(width: 430, height: 900 + 1))
      DispatchQueue.main.async {
        self.setContentSize(NSSize(width: 430, height: 900))
      }
    }
  }
}
