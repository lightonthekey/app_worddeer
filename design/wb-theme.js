/* 词鹿 · 主题系统（原型用，无构建）
 * 用法：<script src="wb-theme.js"></script> 放在 <head> 里，页面 CSS 全用 var(--xxx)
 * 取色优先级：?t=key > localStorage('wb.theme') > 默认 indigo
 * 切换：WB.apply('teal')；渲染选择器：WB.mount(document.getElementById('grid'))
 */
(function () {
  var THEMES = [
    { key: 'indigo', name: '靛蓝', tag: '冷静专注',
      pri: '#4B6FF0', deep: '#3A5AD8', soft: '#EEF3FF', bg: '#F7F9FF',
      line: '#E4EAF8', dash: '#CCD8FB', ink: '#1C2231', muted: '#7C87A3' },
    { key: 'teal', name: '青绿', tag: '清爽护眼',
      pri: '#109E90', deep: '#0A7A70', soft: '#E5F6F3', bg: '#F0F8F7',
      line: '#DCEBE8', dash: '#BCE2DC', ink: '#1B2B29', muted: '#6E8A86' },
    { key: 'bamboo', name: '竹绿', tag: '亲切自然',
      pri: '#4FA845', deep: '#3A7F33', soft: '#EBF6E7', bg: '#F4F9F1',
      line: '#E1EDDB', dash: '#C4E3BB', ink: '#22301E', muted: '#7B8F74' },
    { key: 'orange', name: '暖橙', tag: '有精神',
      pri: '#EE7A2B', deep: '#C75C12', soft: '#FDF0E3', bg: '#FDF7F1',
      line: '#F2E5D8', dash: '#F5D2B0', ink: '#33261B', muted: '#9C8874' },
    { key: 'coral', name: '珊瑚', tag: '少见好记',
      pri: '#E8604C', deep: '#C4432F', soft: '#FDECE9', bg: '#FDF5F3',
      line: '#F2E0DC', dash: '#F4C9C3', ink: '#33221F', muted: '#9B8078' },
    { key: 'purple', name: '经典紫', tag: '原来那版',
      pri: '#6D5AE0', deep: '#4A41C4', soft: '#F1EFFC', bg: '#F4F2FA',
      line: '#E8E5F4', dash: '#CFC8F3', ink: '#22202B', muted: '#8A86A0' }
  ];

  var DEFAULT = 'indigo';
  var STORE = 'wb.theme';

  function bytes(hex) {
    var h = hex.replace('#', '');
    if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
    return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
  }
  function hex(rgb) {
    return '#' + rgb.map(function (v) {
      var s = Math.round(Math.max(0, Math.min(255, v))).toString(16);
      return s.length === 1 ? '0' + s : s;
    }).join('').toUpperCase();
  }
  /* w = 后一个颜色的占比 */
  function mix(a, b, w) {
    var A = bytes(a), B = bytes(b);
    return hex([0, 1, 2].map(function (i) { return A[i] + (B[i] - A[i]) * w; }));
  }
  function rgbOf(h) { return bytes(h).join(','); }

  function vars(t) {
    return {
      '--primary': t.pri,
      '--primary-deep': t.deep,
      '--primary-50': t.soft,
      '--bg': t.bg,
      '--ink': t.ink,
      '--muted': t.muted,
      '--line': t.line,
      '--dash': t.dash,
      '--hero-a': t.pri,
      '--hero-b': t.deep,
      /* 派生色：6 套主题靠同一套公式，避免逐套手调跑偏 */
      '--pri-line': mix('#FFFFFF', t.pri, 0.28),
      '--done-bg': mix('#FFFFFF', t.pri, 0.07),
      '--done-line': mix('#FFFFFF', t.pri, 0.20),
      '--done-text': mix(t.deep, '#000000', 0.20),
      '--cur-edge': mix(t.deep, '#000000', 0.16),
      '--track': mix(t.bg, t.pri, 0.10),
      '--edge': mix(t.bg, t.ink, 0.10),
      /* 中性灰也跟着主题偏色，暖色主题里才不会冒蓝灰 */
      '--n1': mix(t.bg, t.ink, 0.05),
      '--n2': mix(t.bg, t.ink, 0.10),
      '--n3': mix(t.bg, t.ink, 0.52),
      '--pri-rgb': rgbOf(t.pri),
      '--deep-rgb': rgbOf(t.deep)
    };
  }

  function styleEl() {
    var el = document.getElementById('wb-theme-vars');
    if (!el) {
      el = document.createElement('style');
      el.id = 'wb-theme-vars';
      document.head.appendChild(el);
    }
    return el;
  }

  function find(key) {
    for (var i = 0; i < THEMES.length; i++) if (THEMES[i].key === key) return THEMES[i];
    return THEMES[0];
  }

  function apply(key, silent) {
    var t = find(key);
    var v = vars(t);
    var body = ':root{' + Object.keys(v).map(function (k) { return k + ':' + v[k]; }).join(';') + '}';
    styleEl().textContent = body;
    document.documentElement.setAttribute('data-theme', t.key);
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', t.bg);
    if (!silent) {
      try { localStorage.setItem(STORE, t.key); } catch (e) {}
    }
    document.querySelectorAll('[data-wb-theme]').forEach(function (b) {
      b.classList.toggle('on', b.getAttribute('data-wb-theme') === t.key);
    });
    window.WB.current_ = t.key;
    return t;
  }

  function param(k) {
    var m = new RegExp('[?&]' + k + '=([^&]+)').exec(location.search);
    return m ? decodeURIComponent(m[1]) : '';
  }

  function saved() {
    try { return localStorage.getItem(STORE) || ''; } catch (e) { return ''; }
  }

  /* 渲染 6 个选项；每个选项内部结构由 CSS 负责 */
  function mount(el, opts) {
    if (!el) return;
    opts = opts || {};
    el.classList.add('wb-themes');
    el.innerHTML = THEMES.map(function (t) {
      return '<button type="button" class="wb-theme" data-wb-theme="' + t.key + '" ' +
        'style="--c1:' + t.pri + ';--c2:' + t.deep + ';--c3:' + t.soft + '">' +
        '<i class="wb-dot"></i>' +
        '<b>' + t.name + '</b>' +
        '<s>' + t.tag + '</s>' +
        '</button>';
    }).join('');
    el.addEventListener('click', function (e) {
      var b = e.target.closest ? e.target.closest('[data-wb-theme]') : null;
      if (!b) return;
      apply(b.getAttribute('data-wb-theme'));
      if (opts.onPick) opts.onPick(window.WB.current_);
    });
    el.querySelectorAll('[data-wb-theme]').forEach(function (b) {
      b.classList.toggle('on', b.getAttribute('data-wb-theme') === window.WB.current_);
    });
  }

  window.WB = {
    themes: THEMES,
    apply: apply,
    mount: mount,
    current: function () { return window.WB.current_ || DEFAULT; },
    current_: '',
    vars: vars,
    mix: mix
  };

  var startKey = param('t') || saved() || DEFAULT;
  var start = find(startKey);
  /* 首帧就写变量，避免闪一下默认色 */
  var pre = document.createElement('style');
  var v0 = vars(start);
  pre.textContent = ':root{' + Object.keys(v0).map(function (k) { return k + ':' + v0[k]; }).join(';') + '}';
  document.head.appendChild(pre);
  window.WB.current_ = start.key;
  document.documentElement.setAttribute('data-theme', start.key);
  if (document.readyState !== 'loading') {
    if (document.body) document.documentElement.className += '';
  }
  document.addEventListener('DOMContentLoaded', function () { apply(start.key, true); });
})();
