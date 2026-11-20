import 'package:app_worddeer/audio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 发音缓存文件名规则。
///
/// 这三处必须永远一致，否则会出现「服务器上明明有文件，App 却一直下载失败」：
///   - tools/fetch_eng_audio.py 的 safe_name
///   - internal/controller/app/audio.go 的 audioSafeName
///   - lib/audio.dart 的 cacheName
void main() {
  test('文件名规则：非字母数字一律换下划线', () {
    expect(Voice.cacheName('abandon', 'us'), 'abandon_us.mp3');
    expect(Voice.cacheName('first-floor', 'uk'), 'first_floor_uk.mp3');
    expect(Voice.cacheName("don't", 'us'), 'don_t_us.mp3');
    expect(Voice.cacheName('a lot', 'uk'), 'a_lot_uk.mp3');
    // 大小写保留（服务器按原样存）
    expect(Voice.cacheName('A1', 'us'), 'A1_us.mp3');
    // 首尾的下划线要去掉，否则 '_hello_' 和 'hello' 会存成两个文件
    expect(Voice.cacheName('_hello_', 'us'), 'hello_us.mp3');
  });

  test('脏输入兜底成 word，不会拼出空文件名', () {
    expect(Voice.cacheName('', 'us'), 'word_us.mp3');
    expect(Voice.cacheName('---', 'uk'), 'word_uk.mp3');
  });

  test('空词直接返回，不当成失败提示', () async {
    final before = Voice.failTick.value;
    await Voice.say('');
    expect(Voice.failTick.value, before);
  });
}
