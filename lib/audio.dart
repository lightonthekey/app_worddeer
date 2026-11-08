import 'package:audioplayers/audioplayers.dart';

/// 发音源：默认走线上 tooldeer.com（真机可用）。
/// 本地开发改成本机服务：
///   flutter run -d chrome --dart-define=AUDIO_BASE=http://127.0.0.1:1000
/// 上线前建议换成本地音频包或自有 CDN。
const String kAudioBase = String.fromEnvironment(
  'AUDIO_BASE',
  defaultValue: 'https://tooldeer.com',
);

class Voice {
  static final AudioPlayer _p = AudioPlayer();

  static Future<void> say(String word, {String type = 'us'}) async {
    try {
      await _p.stop();
      final url = '$kAudioBase/api/v1/engmatch/audio'
          '?word=${Uri.encodeComponent(word)}&type=$type';
      await _p.play(UrlSource(url));
    } catch (_) {
      // 发音失败不阻断答题
    }
  }
}
