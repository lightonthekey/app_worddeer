import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// 对外法务页面地址。
///
/// 这些页面是网站上的静态 HTML（GoFrame 静态目录 `resource/public/legal/`），
/// 与 App Store Connect 里填的「隐私政策网址」「支持网址」**必须完全一致**——
/// 审核员会两边对照，不一致会被要求说明。
///
/// 别改成主站的 `tooldeer.com/privacy.html`：那是主站自己的隐私政策，
/// 内容与本 App 收集的信息对不上。
const kPrivacyUrl = 'https://platform.tooldeer.com/legal/privacy.html';
const kTermsUrl = 'https://platform.tooldeer.com/legal/terms.html';
const kSupportUrl = 'https://platform.tooldeer.com/legal/support.html';

/// 用系统浏览器打开外部链接。
///
/// 返回 false 表示没打开（无可用浏览器 / 平台不支持），此时已把地址复制到剪贴板，
/// 调用方据此给一句提示即可，不会出现「点了没反应」。
Future<bool> openLegal(String url) async {
  final uri = Uri.parse(url);
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return true;
  } catch (_) {
    // 落到下面的兜底
  }
  try {
    if (await launchUrl(uri)) return true;
  } catch (_) {
    // 落到下面的兜底
  }
  await Clipboard.setData(ClipboardData(text: url));
  return false;
}
