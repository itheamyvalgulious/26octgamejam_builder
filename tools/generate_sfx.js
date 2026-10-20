const fs = require('fs');
const path = require('path');
const sfxr = require('./jsfxr/sfxr.js');

const OUTPUT_DIR = path.resolve(__dirname, '../assets/audio/sfx');
const PREVIEW_HTML_PATH = path.resolve(__dirname, '../assets/audio/sfx/preview.html');

if (!fs.existsSync(OUTPUT_DIR)) {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

// Frequency to jsfxr base_freq parameter helper
function freqToParam(f) {
  return Math.sqrt(Math.max(0, f / 3528.0 - 0.001));
}

// Generate single sine note buffer
function makeSineNote(freq, durSec, punch = 0.25, vol = 0.38) {
  const p = new sfxr.Params();
  p.sample_size = 16;
  p.sample_rate = 44100;
  p.wave_type = 2; // SINE
  p.p_base_freq = freqToParam(freq);
  p.p_env_attack = 0.0;
  p.p_env_sustain = 0.04;
  p.p_env_decay = Math.sqrt(durSec / 2.267);
  p.p_env_punch = punch;
  p.p_lpf_freq = 0.95;
  p.sound_vol = vol;
  return new sfxr.SoundEffect(p).getRawBuffer().normalized;
}

// Mix multiple timed note events into a 16-bit WAV Buffer
function mixNotesToWav(noteEvents, totalSec) {
  const sampleRate = 44100;
  const totalSamples = Math.floor(totalSec * sampleRate);
  const out = new Float32Array(totalSamples);
  for (const ev of noteEvents) {
    const startSample = Math.floor(ev.time * sampleRate);
    const buf = ev.buffer;
    const vol = ev.vol !== undefined ? ev.vol : 1.0;
    for (let i = 0; i < buf.length && (startSample + i) < totalSamples; i++) {
      out[startSample + i] += buf[i] * vol;
    }
  }

  // Peak normalization with headroom
  let maxAmp = 0;
  for (let i = 0; i < totalSamples; i++) {
    const a = Math.abs(out[i]);
    if (a > maxAmp) maxAmp = a;
  }
  const gain = maxAmp > 0 ? (0.85 / Math.max(maxAmp, 0.85)) : 1.0;

  const pcm16 = Buffer.alloc(totalSamples * 2);
  for (let i = 0; i < totalSamples; i++) {
    let s = Math.floor(out[i] * gain * 32767);
    if (s > 32767) s = 32767;
    if (s < -32768) s = -32768;
    pcm16.writeInt16LE(s, i * 2);
  }

  return createWav(pcm16, sampleRate, 1, 16);
}

function createWav(pcmBuffer, sampleRate = 44100, channels = 1, bitDepth = 16) {
  const header = Buffer.alloc(44);
  header.write('RIFF', 0);
  header.writeUInt32LE(36 + pcmBuffer.length, 4);
  header.write('WAVE', 8);
  header.write('fmt ', 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20); // PCM format
  header.writeUInt16LE(channels, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(sampleRate * channels * (bitDepth / 8), 28);
  header.writeUInt16LE(channels * (bitDepth / 8), 32);
  header.writeUInt16LE(bitDepth, 34);
  header.write('data', 36);
  header.writeUInt32LE(pcmBuffer.length, 40);
  return Buffer.concat([header, pcmBuffer]);
}

// ---------------------------------------------------------------------------
// 声音库定义 (8大核心音效已完全锁定 + 3项重点重制候选)
// ---------------------------------------------------------------------------
const SOUND_DEFINITIONS = [
  // -------------------------------------------------------------
  // 1. UI 点击 (UI Click) - 已确定
  // -------------------------------------------------------------
  {
    category: 'ui_click',
    name: 'ui_click_wood',
    label: 'UI点击 - 原木方块轻敲 (已选定 ✓)',
    desc: '温润质朴的木块轻击声，无尖锐高频，极度耐听舒适。',
    status: 'selected',
    params: {
      wave_type: 2, // SINE
      p_env_attack: 0.0,
      p_env_sustain: 0.05,
      p_env_punch: 0.38,
      p_env_decay: 0.14,
      p_base_freq: 0.44,
      p_freq_ramp: -0.14,
      p_lpf_freq: 0.8,
      sound_vol: 0.36,
      sample_rate: 44100,
      sample_size: 16
    }
  },

  // -------------------------------------------------------------
  // 2. 滑动条音效 (Slider Sound) - 已确定
  // -------------------------------------------------------------
  {
    category: 'ui_slider',
    name: 'ui_slider_marimba',
    label: '滑动条 - 拇指琴微拨 (已选定 ✓)',
    desc: '极弱温和的清脆微音(~25ms)，连续滑动时如滑过拇指琴琴键，柔和舒缓。',
    status: 'selected',
    params: {
      wave_type: 2, // SINE
      p_env_attack: 0.0,
      p_env_sustain: 0.03,
      p_env_punch: 0.15,
      p_env_decay: 0.10,
      p_base_freq: 0.52,
      p_freq_ramp: -0.05,
      p_lpf_freq: 0.75,
      sound_vol: 0.22,
      sample_rate: 44100,
      sample_size: 16
    }
  },

  // -------------------------------------------------------------
  // 3. 细胞放置音效 (Cell Placement) - 已确定
  // -------------------------------------------------------------
  {
    category: 'cell_place',
    name: 'cell_place_jelly',
    label: '细胞放置 - 萌弹果冻着陆 (已选定 ✓)',
    desc: '软糯果冻细胞轻轻落座的弹性音，伴随微小共鸣滑音，软萌生动。',
    status: 'selected',
    params: {
      wave_type: 2, // SINE
      p_env_attack: 0.0,
      p_env_sustain: 0.08,
      p_env_punch: 0.35,
      p_env_decay: 0.18,
      p_base_freq: 0.38,
      p_freq_ramp: 0.08,
      p_arp_mod: 0.22,
      p_arp_speed: 0.45,
      p_lpf_freq: 0.8,
      sound_vol: 0.40,
      sample_rate: 44100,
      sample_size: 16
    }
  },

  // -------------------------------------------------------------
  // 4. 细胞删除音效 (Cell Deletion) - 用户要求：硬一点，不要气声了！
  // -------------------------------------------------------------
  {
    category: 'cell_delete',
    name: 'cell_delete_woodsnap',
    label: '细胞删除 - 原木解嵌清脆咔嗒 (硬质候选 A - 干脆榫卯脱扣)',
    desc: '彻底去除气声！纯正正弦波硬质下沉微击（托~），模拟原木榫卯积木被清脆拔下脱扣的瞬间，极度干脆爽快。',
    status: 'candidate',
    params: {
      wave_type: 2, // SINE
      p_env_attack: 0.0,
      p_env_sustain: 0.035,
      p_env_punch: 0.65, // 强打击瞬态
      p_env_decay: 0.12,  // 极快干脆收尾
      p_base_freq: 0.52,
      p_freq_ramp: -0.38, // 快速下潜解嵌感
      p_lpf_freq: 0.85,
      sound_vol: 0.42,
      sample_rate: 44100,
      sample_size: 16
    }
  },
  {
    category: 'cell_delete',
    name: 'cell_delete_hardpop',
    label: '细胞删除 - 坚实弹脱卡簧响 (硬质候选 B - 紧致弹扣)',
    desc: '带有轻度低通滤波的方波硬质弹脱声（克嗒~），清脆结实，像拆下紧扣的乐高积木。',
    status: 'candidate',
    params: {
      wave_type: 0, // SQUARE (filtered)
      p_duty: 0.32,
      p_env_attack: 0.0,
      p_env_sustain: 0.03,
      p_env_punch: 0.60,
      p_env_decay: 0.11,
      p_base_freq: 0.46,
      p_freq_ramp: -0.32,
      p_lpf_freq: 0.58, // 去掉毛刺，保留硬核
      sound_vol: 0.38,
      sample_rate: 44100,
      sample_size: 16
    }
  },
  {
    category: 'cell_delete',
    name: 'cell_delete_plink',
    label: '细胞删除 - 清朗弹脱短音 (硬质候选 C - 纯净脆弹)',
    desc: '略带高音的短促下行纯音跳水，像手指轻轻弹下一块积木小磁铁，清澈无杂音。',
    status: 'candidate',
    params: {
      wave_type: 2, // SINE
      p_env_attack: 0.0,
      p_env_sustain: 0.03,
      p_env_punch: 0.5,
      p_env_decay: 0.10,
      p_base_freq: 0.60,
      p_freq_ramp: -0.42,
      sound_vol: 0.40,
      sample_rate: 44100,
      sample_size: 16
    }
  },

  // -------------------------------------------------------------
  // 5. 推进器工作音效 (Pusher / Thruster) - 已确定
  // -------------------------------------------------------------
  {
    category: 'pusher_action',
    name: 'pusher_spring',
    label: '推进器 - 卡通弹簧推搡 (已选定 ✓)',
    desc: '卡通弹簧机关欢快向前一顶（噔咚~），俏皮活泼，赋予推进器蓬勃生机。',
    status: 'selected',
    params: {
      wave_type: 2, // SINE
      p_env_attack: 0.0,
      p_env_sustain: 0.12,
      p_env_punch: 0.45,
      p_env_decay: 0.24,
      p_base_freq: 0.32,
      p_freq_ramp: 0.15,
      p_lpf_freq: 0.8,
      sound_vol: 0.42,
      sample_rate: 44100,
      sample_size: 16
    }
  },

  // -------------------------------------------------------------
  // 6. 复制器工作音效 (Replicator / Mitosis) - 用户已确定选 C！
  // -------------------------------------------------------------
  {
    category: 'replicator_action',
    name: 'replicator_gentle_bubble',
    label: '复制器 - 软弹双水珠分瓣 (已选定 ✓ 用户选C)',
    desc: '柔和舒缓的两次水珠分生声，间距宽松柔和（咕嘟-咕嘟），治愈可爱。',
    status: 'selected',
    customGenerator: () => {
      const p = new sfxr.Params();
      p.sample_size = 16;
      p.sample_rate = 44100;
      p.wave_type = 2; // SINE
      p.p_base_freq = 0.46;
      p.p_freq_ramp = 0.14;
      p.p_env_attack = 0.0;
      p.p_env_sustain = 0.04;
      p.p_env_punch = 0.2;
      p.p_env_decay = 0.12;
      p.sound_vol = 0.38;
      const b1 = new sfxr.SoundEffect(p).getRawBuffer().normalized;

      const p2 = new sfxr.Params();
      p2.fromJSON(p);
      p2.p_base_freq = 0.52;
      p2.p_freq_ramp = 0.16;
      const b2 = new sfxr.SoundEffect(p2).getRawBuffer().normalized;

      return mixNotesToWav([
        { time: 0.00, buffer: b1 },
        { time: 0.09, buffer: b2 }
      ], 0.28);
    }
  },

  // -------------------------------------------------------------
  // 7. 怪物行动音效 (Wanderer / Monster) - 已确定
  // -------------------------------------------------------------
  {
    category: 'monster_action',
    name: 'monster_waddle',
    label: '怪物 - 呆萌小步蹒跚 (已选定 ✓)',
    desc: '像小企鹅或小仓鼠憨态可掬迈出一步的圆润轻响（噗哒~），可爱呆萌，毫不恐怖。',
    status: 'selected',
    params: {
      wave_type: 2, // SINE
      p_env_attack: 0.0,
      p_env_sustain: 0.09,
      p_env_punch: 0.35,
      p_env_decay: 0.20,
      p_base_freq: 0.26,
      p_freq_ramp: -0.14,
      p_lpf_freq: 0.65,
      sound_vol: 0.42,
      sample_rate: 44100,
      sample_size: 16
    }
  },

  // -------------------------------------------------------------
  // 8. 摧毁器工作音效 (Destroyer) - 用户要求：硬一点，不要气声了！
  // -------------------------------------------------------------
  {
    category: 'destroyer_action',
    name: 'destroyer_nutcracker',
    label: '摧毁器 - 坚实核桃夹脆裂 (硬质候选 A - 硬核夹碎)',
    desc: '彻底去除气声！结实硬朗的木夹/坚果夹击破声（喀嚓-邦！），冲击力十足，极具打击感与破坏满足感。',
    status: 'candidate',
    params: {
      wave_type: 0, // SQUARE
      p_duty: 0.38,
      p_env_attack: 0.0,
      p_env_sustain: 0.06,
      p_env_punch: 0.82, // 强烈硬质打击感
      p_env_decay: 0.16,
      p_base_freq: 0.33,
      p_freq_ramp: -0.36,
      p_lpf_freq: 0.52,
      sound_vol: 0.46,
      sample_rate: 44100,
      sample_size: 16
    }
  },
  {
    category: 'destroyer_action',
    name: 'destroyer_clamp_smash',
    label: '摧毁器 - 机械重钳咬合打击 (硬质候选 B - 饱满重击)',
    desc: '低频沉重打底+上方脆硬卡咬的复合硬质音效（铿-嗒！），硬朗干脆，咬碎感极为明显。',
    status: 'candidate',
    customGenerator: () => {
      // Bass thud
      const pBass = new sfxr.Params();
      pBass.sample_size = 16;
      pBass.sample_rate = 44100;
      pBass.wave_type = 2; // SINE
      pBass.p_base_freq = 0.22;
      pBass.p_freq_ramp = -0.3;
      pBass.p_env_attack = 0.0;
      pBass.p_env_sustain = 0.05;
      pBass.p_env_punch = 0.8;
      pBass.p_env_decay = 0.18;
      pBass.sound_vol = 0.48;
      const bBass = new sfxr.SoundEffect(pBass).getRawBuffer().normalized;

      // Crisp snap
      const pSnap = new sfxr.Params();
      pSnap.sample_size = 16;
      pSnap.sample_rate = 44100;
      pSnap.wave_type = 0; // SQUARE
      pSnap.p_duty = 0.45;
      pSnap.p_base_freq = 0.42;
      pSnap.p_freq_ramp = -0.4;
      pSnap.p_env_attack = 0.0;
      pSnap.p_env_sustain = 0.03;
      pSnap.p_env_punch = 0.7;
      pSnap.p_env_decay = 0.12;
      pSnap.p_lpf_freq = 0.6;
      pSnap.sound_vol = 0.42;
      const bSnap = new sfxr.SoundEffect(pSnap).getRawBuffer().normalized;

      return mixNotesToWav([
        { time: 0.00, buffer: bSnap },
        { time: 0.01, buffer: bBass }
      ], 0.24);
    }
  },
  {
    category: 'destroyer_action',
    name: 'destroyer_hard_chomp',
    label: '摧毁器 - 卡通硬壳大口咬下 (硬质候选 C - 紧凑大嚼)',
    desc: '紧凑利落的硬朗卡通大口咬击（咔嘣！），干爽无风声，兼顾硬朗打击度与游戏趣味性。',
    status: 'candidate',
    params: {
      wave_type: 0, // SQUARE
      p_duty: 0.28,
      p_env_attack: 0.0,
      p_env_sustain: 0.05,
      p_env_punch: 0.75,
      p_env_decay: 0.14,
      p_base_freq: 0.36,
      p_freq_ramp: -0.30,
      p_lpf_freq: 0.60,
      sound_vol: 0.44,
      sample_rate: 44100,
      sample_size: 16
    }
  },

  // -------------------------------------------------------------
  // 9. 转向器工作音效 (Rotator) - 已确定
  // -------------------------------------------------------------
  {
    category: 'rotator_action',
    name: 'rotator_spin',
    label: '转向器 - 纸风车旋转回鸣 (已选定 ✓)',
    desc: '微风吹拂纸风车转过一圈的轻快扬起音，自然流畅。',
    status: 'selected',
    params: {
      wave_type: 2, // SINE
      p_env_attack: 0.01,
      p_env_sustain: 0.10,
      p_env_punch: 0.25,
      p_env_decay: 0.18,
      p_base_freq: 0.36,
      p_freq_ramp: 0.16,
      sound_vol: 0.38,
      sample_rate: 44100,
      sample_size: 16
    }
  },

  // -------------------------------------------------------------
  // 10. 抑制器音效 (Inhibitor) - 用户已确定选 A 组！
  // -------------------------------------------------------------
  {
    category: 'inhibitor_action',
    name: 'inhibitor_engage_sleep',
    label: '抑制器 - 阻断生效/休眠 (已选定 ✓ A组对音1)',
    desc: '突触阻断信号生效时的温和下行提示音（咪-多~），像给后方方块盖上宁静休眠小被子。',
    status: 'selected',
    customGenerator: () => {
      const n1 = makeSineNote(659.25, 0.14, 0.2, 0.35); // E5
      const n2 = makeSineNote(523.25, 0.22, 0.25, 0.38); // C5
      return mixNotesToWav([
        { time: 0.00, buffer: n1 },
        { time: 0.07, buffer: n2 }
      ], 0.32);
    }
  },
  {
    category: 'inhibitor_action',
    name: 'inhibitor_release_wake',
    label: '抑制器 - 阻断解除/苏醒 (已选定 ✓ A组对音2)',
    desc: '阻断解除时的欢快上行唤醒音（多-唆~），象征后方方块苏醒恢复机能。',
    status: 'selected',
    customGenerator: () => {
      const n1 = makeSineNote(523.25, 0.12, 0.2, 0.35); // C5
      const n2 = makeSineNote(783.99, 0.22, 0.3, 0.40); // G5
      return mixNotesToWav([
        { time: 0.00, buffer: n1 },
        { time: 0.07, buffer: n2 }
      ], 0.32);
    }
  },

  // -------------------------------------------------------------
  // 11. 宝藏收集音效 (Treasure Collect) - 已确定
  // -------------------------------------------------------------
  {
    category: 'treasure_collect',
    name: 'treasure_chime',
    label: '宝藏 - 晶莹风铃微响 (已选定 ✓)',
    desc: '微风拂过高能营养核时清透纯净的双音水晶铃鸣。',
    status: 'selected',
    params: {
      wave_type: 2, // SINE
      p_env_attack: 0.0,
      p_env_sustain: 0.16,
      p_env_punch: 0.35,
      p_env_decay: 0.32,
      p_base_freq: 0.60,
      p_freq_ramp: 0.06,
      p_arp_mod: 0.38,
      p_arp_speed: 0.42,
      sound_vol: 0.42,
      sample_rate: 44100,
      sample_size: 16
    }
  },

  // -------------------------------------------------------------
  // 12. 关卡胜利音效 (Level Victory) - 用户要求：节奏要快！极速上扬！表现纯粹快乐！
  // -------------------------------------------------------------
  {
    category: 'level_victory',
    name: 'victory_joyful_rush',
    label: '关卡胜利 - 极速雀跃狂欢乐章 (全新候选 A - 180BPM 快乐飞扬)',
    desc: '节奏极快、一路向上狂飙的超快乐庆祝短曲！十六分音符滚奏阶梯上扬，小马里奥/星之卡比通关般的爆棚快乐感与盛大高音和声（~1.8秒）。',
    status: 'candidate',
    customGenerator: () => {
      // 180 BPM, Sixteenth note = 0.083s, Eighth note = 0.166s
      const notes = [
        // 第1节：十六分音符极速阶梯上卷 (C6 -> D6 -> E6 -> G6 -> C7!)
        { time: 0.00, buffer: makeSineNote(1046.50, 0.22, 0.35, 0.45) }, // C6
        { time: 0.08, buffer: makeSineNote(1174.66, 0.22, 0.35, 0.45) }, // D6
        { time: 0.16, buffer: makeSineNote(1318.51, 0.22, 0.38, 0.48) }, // E6
        { time: 0.24, buffer: makeSineNote(1567.98, 0.25, 0.40, 0.50) }, // G6
        { time: 0.33, buffer: makeSineNote(2093.00, 0.35, 0.45, 0.55) }, // C7 重音!

        // 第2节：阳光雀跃小跳跃 (G6 -> C7 -> E7 -> G7 登顶!)
        { time: 0.52, buffer: makeSineNote(1567.98, 0.25, 0.35, 0.48) }, // G6
        { time: 0.65, buffer: makeSineNote(2093.00, 0.28, 0.40, 0.52) }, // C7
        { time: 0.78, buffer: makeSineNote(2637.02, 0.30, 0.42, 0.55) }, // E7
        { time: 0.92, buffer: makeSineNote(3135.96, 0.40, 0.48, 0.60) }, // G7 极高华彩!

        // 第3节：盛大喜庆大三度和弦齐鸣 + 晶莹长铃收束
        { time: 1.15, buffer: makeSineNote(2093.00, 0.75, 0.45, 0.50) }, // C7 (和声根音)
        { time: 1.15, buffer: makeSineNote(2637.02, 0.75, 0.45, 0.55) }, // E7 (和声三音)
        { time: 1.15, buffer: makeSineNote(3135.96, 0.80, 0.50, 0.58) }, // G7 (和声五音)
        { time: 1.30, buffer: makeSineNote(4186.01, 0.55, 0.35, 0.40) }  // C8 (超高音彩带铃星)
      ];
      return mixNotesToWav(notes, 1.9);
    }
  },
  {
    category: 'level_victory',
    name: 'victory_bouncy_carnival',
    label: '关卡胜利 - 阳光欢跳嘉年华 (全新候选 B - 170BPM 弹跳狂欢)',
    desc: '弹跳节奏极强的快节奏八音盒大狂欢！附点跳音持续拔高，带着感染力十足的欢呼律动升入高空（~2.1秒）。',
    status: 'candidate',
    customGenerator: () => {
      // 170 BPM
      const notes = [
        // 第1节：前冲跳跃
        { time: 0.00, buffer: makeSineNote(783.99, 0.20, 0.3, 0.40) },   // G5
        { time: 0.10, buffer: makeSineNote(1046.50, 0.20, 0.35, 0.45) }, // C6
        { time: 0.20, buffer: makeSineNote(1318.51, 0.22, 0.35, 0.48) }, // E6
        { time: 0.30, buffer: makeSineNote(1567.98, 0.28, 0.40, 0.50) }, // G6
        { time: 0.45, buffer: makeSineNote(1318.51, 0.20, 0.35, 0.45) }, // E6
        { time: 0.58, buffer: makeSineNote(2093.00, 0.35, 0.45, 0.52) }, // C7

        // 第2节：持续高扬拔高
        { time: 0.75, buffer: makeSineNote(1975.53, 0.22, 0.38, 0.48) }, // B6
        { time: 0.88, buffer: makeSineNote(2093.00, 0.25, 0.40, 0.52) }, // C7
        { time: 1.02, buffer: makeSineNote(2349.32, 0.28, 0.42, 0.54) }, // D7
        { time: 1.18, buffer: makeSineNote(2637.02, 0.35, 0.45, 0.58) }, // E7

        // 第3节：盛大礼花喷发和弦
        { time: 1.38, buffer: makeSineNote(1567.98, 0.70, 0.35, 0.45) }, // G6
        { time: 1.38, buffer: makeSineNote(2093.00, 0.75, 0.45, 0.52) }, // C7
        { time: 1.38, buffer: makeSineNote(3135.96, 0.80, 0.50, 0.58) }  // G7
      ];
      return mixNotesToWav(notes, 2.2);
    }
  }
];

// Generate WAV files
const generatedAudios = [];

console.log('Generating updated sound effects...');
for (const s of SOUND_DEFINITIONS) {
  let wavBuffer;
  let b58 = '';

  if (s.customGenerator) {
    wavBuffer = s.customGenerator();
  } else {
    const p = new sfxr.Params();
    p.fromJSON(s.params);
    b58 = p.toB58();
    const sound = new sfxr.SoundEffect(p).generate();
    const base64Data = sound.dataURI.split(',')[1];
    wavBuffer = Buffer.from(base64Data, 'base64');
  }

  s.b58 = b58;
  const fileName = `${s.name}.wav`;
  const filePath = path.join(OUTPUT_DIR, fileName);
  fs.writeFileSync(filePath, wavBuffer);

  const durationSec = (wavBuffer.length - 44) / (44100 * 2);
  s.fileName = fileName;
  s.fileSize = wavBuffer.length;
  s.durationMs = Math.round(durationSec * 1000);

  generatedAudios.push(s);
  console.log(`✓ [${s.category}] [${s.status}] ${fileName} (${s.fileSize} bytes, ${s.durationMs}ms)`);
}

// Write manifest
fs.writeFileSync(
  path.join(OUTPUT_DIR, 'sfx_manifest.json'),
  JSON.stringify(generatedAudios, null, 2)
);

// Category display mapping
const categoryNames = {
  ui_click: '1. UI 点击 (UI Click)',
  ui_slider: '2. 滑动条音效 (Slider Sound)',
  cell_place: '3. 细胞放置 (Cell Placement)',
  cell_delete: '4. 细胞删除 (Cell Deletion - 硬质无气声)',
  pusher_action: '5. 推进器工作 (Pusher / Thruster)',
  replicator_action: '6. 复制器工作 (Replicator / Mitosis)',
  monster_action: '7. 怪物行动 (Wanderer / Monster)',
  destroyer_action: '8. 摧毁器工作 (Destroyer - 硬质无气声)',
  rotator_action: '9. 转向器工作 (Rotator)',
  inhibitor_action: '10. 抑制器状态切换 (Inhibitor Engage & Release)',
  treasure_collect: '11. 宝藏收集 (Treasure Collect)',
  level_victory: '12. 关卡胜利庆典 (Level Victory - 极速上扬欢乐短曲)'
};

const grouped = {};
for (const s of generatedAudios) {
  if (!grouped[s.category]) grouped[s.category] = [];
  grouped[s.category].push(s);
}

const htmlContent = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>《构造一个我》音效试听选型面板 (第3版更新)</title>
  <style>
    :root {
      --bg: #111a21;
      --card-bg: #18252f;
      --border: #283e4e;
      --accent: #8ce2be;
      --accent-hover: #b4f5d8;
      --text: #d6e5ea;
      --text-bright: #ffffff;
      --text-muted: #8ca3ae;
      --success: #3fb950;
      --tag-bg: #21323f;
      --gold: #f1e05a;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.6;
      padding: 32px 20px 80px;
    }
    .container {
      max-width: 1040px;
      margin: 0 auto;
    }
    header {
      margin-bottom: 24px;
      padding-bottom: 20px;
      border-bottom: 1px solid var(--border);
    }
    h1 {
      color: var(--text-bright);
      font-size: 26px;
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 10px;
    }
    .badge {
      font-size: 13px;
      background: rgba(140, 226, 190, 0.15);
      color: var(--accent);
      padding: 3px 10px;
      border-radius: 12px;
      border: 1px solid rgba(140, 226, 190, 0.35);
    }
    .subtitle {
      color: var(--text-muted);
      font-size: 14.5px;
    }
    .global-bar {
      display: flex;
      align-items: center;
      justify-content: space-between;
      background: var(--card-bg);
      padding: 14px 20px;
      border-radius: 10px;
      border: 1px solid var(--border);
      margin-bottom: 28px;
      position: sticky;
      top: 12px;
      z-index: 100;
      box-shadow: 0 6px 20px rgba(0,0,0,0.45);
    }
    .global-bar .volume-ctrl {
      display: flex;
      align-items: center;
      gap: 12px;
      font-size: 14px;
    }
    input[type=range] {
      accent-color: var(--accent);
      cursor: pointer;
    }
    .category-section {
      margin-bottom: 30px;
    }
    .category-title {
      color: var(--text-bright);
      font-size: 18px;
      margin-bottom: 14px;
      display: flex;
      align-items: center;
      gap: 8px;
      border-left: 4px solid var(--accent);
      padding-left: 12px;
    }
    .card-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(460px, 1fr));
      gap: 16px;
    }
    @media (max-width: 600px) {
      .card-grid { grid-template-columns: 1fr; }
    }
    .card {
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 16px 18px;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      transition: border-color 0.15s ease, transform 0.1s ease;
      position: relative;
    }
    .card.selected-card {
      border: 1px solid #3fb95088;
      background: #14221d;
    }
    .card:hover {
      border-color: #8ce2be88;
    }
    .card.playing {
      border-color: var(--accent);
      box-shadow: 0 0 14px rgba(140, 226, 190, 0.35);
    }
    .card-header {
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      margin-bottom: 6px;
    }
    .card-title {
      font-weight: 600;
      font-size: 15.5px;
      color: var(--text-bright);
    }
    .status-tag {
      font-size: 11px;
      padding: 2px 8px;
      border-radius: 4px;
      font-weight: 600;
      margin-left: 6px;
    }
    .tag-selected {
      background: rgba(63, 185, 80, 0.2);
      color: #3fb950;
      border: 1px solid rgba(63, 185, 80, 0.4);
    }
    .tag-candidate {
      background: rgba(241, 224, 90, 0.15);
      color: #f1e05a;
      border: 1px solid rgba(241, 224, 90, 0.3);
    }
    .duration-tag {
      font-size: 12px;
      color: var(--text-muted);
      background: var(--tag-bg);
      padding: 2px 8px;
      border-radius: 4px;
      font-family: monospace;
    }
    .card-desc {
      font-size: 13px;
      color: var(--text-muted);
      margin-bottom: 14px;
      flex-grow: 1;
    }
    .card-actions {
      display: flex;
      align-items: center;
      gap: 10px;
      padding-top: 10px;
      border-top: 1px solid #233644;
    }
    .btn-play {
      background: var(--accent);
      color: #0b151d;
      border: none;
      padding: 7px 16px;
      border-radius: 6px;
      font-weight: 600;
      font-size: 13.5px;
      cursor: pointer;
      display: flex;
      align-items: center;
      gap: 6px;
      transition: background 0.15s, transform 0.05s;
    }
    .btn-play:hover {
      background: var(--accent-hover);
    }
    .btn-play:active {
      transform: scale(0.96);
    }
    .btn-b58 {
      background: var(--tag-bg);
      color: var(--text);
      border: 1px solid var(--border);
      padding: 6px 10px;
      border-radius: 6px;
      font-size: 12px;
      cursor: pointer;
      text-decoration: none;
      transition: all 0.15s;
    }
    .btn-b58:hover {
      background: #2f475a;
      color: var(--text-bright);
    }
    .file-tag {
      font-family: monospace;
      font-size: 12px;
      color: #8ce2be;
      margin-left: auto;
    }
    audio { display: none; }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <h1>
        构造一个我 - 音效试听选型面板
        <span class="badge">第3轮聚焦微调</span>
      </h1>
      <p class="subtitle">
        已成功锁定 8 大核心音效（包含复制器选C、抑制器选A组）；本轮重点提供：彻底去除气声的硬质删除/摧毁器音效，以及 180BPM 极速上扬欢乐狂欢的胜利庆典！
      </p>
    </header>

    <div class="global-bar">
      <div class="volume-ctrl">
        <span>试听主音量:</span>
        <input type="range" id="global-volume" min="0" max="1" step="0.05" value="0.8">
        <span id="vol-label">80%</span>
      </div>
      <div>
        <span style="font-size:13px; color:var(--text-muted);">
          绿色为<b>已锁定确认项</b>，黄色为<b>本轮重点试听项</b>（点击即可试听）
        </span>
      </div>
    </div>

    ${Object.keys(grouped).map(catKey => {
      const items = grouped[catKey];
      const title = categoryNames[catKey] || catKey;
      return `
      <section class="category-section">
        <h2 class="category-title">${title}</h2>
        <div class="card-grid">
          ${items.map(item => `
            <div class="card ${item.status === 'selected' ? 'selected-card' : ''}" id="card-${item.name}">
              <div>
                <div class="card-header">
                  <div style="display:flex; align-items:center;">
                    <div class="card-title">${item.label}</div>
                    <span class="status-tag ${item.status === 'selected' ? 'tag-selected' : 'tag-candidate'}">
                      ${item.status === 'selected' ? '已确认' : '重点试听'}
                    </span>
                  </div>
                  <span class="duration-tag">${item.durationMs} ms</span>
                </div>
                <div class="card-desc">${item.desc}</div>
              </div>
              <div class="card-actions">
                <button class="btn-play" onclick="playSound('${item.name}')">
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor">
                    <polygon points="5 3 19 12 5 21 5 3"></polygon>
                  </svg>
                  播放试听
                </button>
                ${item.b58 ? `
                  <a class="btn-b58" href="https://sfxr.me/#${item.b58}" target="_blank" title="在 sfxr.me 在线打开并调整参数">
                    sfxr.me 调音
                  </a>
                ` : ''}
                <span class="file-tag">${item.fileName}</span>
              </div>
              <audio id="audio-${item.name}" src="${item.fileName}" preload="auto"></audio>
            </div>
          `).join('')}
        </div>
      </section>
      `;
    }).join('')}
  </div>

  <script>
    const volSlider = document.getElementById('global-volume');
    const volLabel = document.getElementById('vol-label');

    volSlider.addEventListener('input', (e) => {
      volLabel.textContent = Math.round(e.target.value * 100) + '%';
    });

    function playSound(name) {
      const audio = document.getElementById('audio-' + name);
      const card = document.getElementById('card-' + name);
      if (!audio) return;

      audio.volume = parseFloat(volSlider.value);
      audio.currentTime = 0;
      audio.play().catch(e => console.error(e));

      document.querySelectorAll('.card').forEach(c => c.classList.remove('playing'));
      card.classList.add('playing');

      audio.onended = () => {
        card.classList.remove('playing');
      };
    }
  </script>
</body>
</html>
`;

fs.writeFileSync(PREVIEW_HTML_PATH, htmlContent);
console.log(`\n✓ Preview HTML updated at: ${PREVIEW_HTML_PATH}`);
