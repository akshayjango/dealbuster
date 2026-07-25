/* DEAL BUSTER app top-banner animation — scenes for animations-v2 SceneStage */
const { SceneStage, Easing, animate, clamp, useScene, useTime } = window;
const { useTweaks, TweaksPanel, TweakSection, TweakToggle, TweakColor, TweakRadio } = window;

const W = 1080, H = 880;

/* ---- three motion helpers, nothing else eases ---- */
const MOTION = {
  enter: (p, s, e) => animate({ from: 0, to: 1, start: s, end: e, ease: Easing.easeOutCubic })(p),
  draw:  (p, s, e) => animate({ from: 0, to: 1, start: s, end: e, ease: Easing.easeInOutCubic })(p),
  pop:   (p, s, e) => animate({ from: 0, to: 1, start: s, end: e, ease: Easing.easeOutBack })(p),
};

const ThemeCtx = React.createContext(null);
const useTheme = () => React.useContext(ThemeCtx);

const FONT_H = "'Montserrat', 'Helvetica Neue', Helvetica, sans-serif";
const FONT_B = "'Poppins', 'Helvetica Neue', Helvetica, sans-serif";

/* ---------- persistent stage ---------- */
function Sparkle({ x, y, s, o, phase = 0 }) {
  const t = useTime ? useTime().time : 0;
  /* slow shimmer: fade out and back, with a gentle scale + spin */
  const w = (Math.sin((t * 1.15 + phase) * Math.PI * 2) + 1) / 2; // 0..1
  const k = 0.22 + w * 0.78;
  return (
    <div style={{
      position: 'absolute', left: x, top: y, width: s, height: s,
      opacity: o * k,
      transform: `scale(${0.62 + k * 0.5}) rotate(${w * 24 - 12}deg)`,
      filter: `drop-shadow(0 0 ${4 + k * 12}px rgba(255,255,255,${0.35 * k}))`,
      background: '#ffffff',
      clipPath: 'polygon(50% 0%,57% 43%,100% 50%,57% 57%,50% 100%,43% 57%,0% 50%,43% 43%)',
    }} />
  );
}

function Backdrop() {
  const t = useTheme();
  return (
    <div style={{
      position: 'absolute', inset: 0, overflow: 'hidden',
      borderRadius: t.roundBottom ? '0 0 52px 52px' : 0,
      background: `linear-gradient(177deg, ${t.bgTop} 0%, ${t.bgMid} 44%, ${t.bgBot} 100%)`,
    }}>
      <div style={{
        position: 'absolute', left: '52%', top: '38%', width: 1300, height: 980,
        transform: 'translate(-50%,-50%)', opacity: 0.5,
        background: `radial-gradient(closest-side, ${t.bgHalo} 0%, rgba(0,0,0,0) 72%)`,
      }} />
      <div style={{
        position: 'absolute', inset: 0,
        background: 'radial-gradient(120% 80% at 50% 108%, rgba(0,0,0,0.34) 0%, rgba(0,0,0,0) 60%)',
      }} />
      <Sparkle x={62} y={196} s={30} o={0.85} phase={0} />
      <Sparkle x={128} y={620} s={22} o={0.6} phase={0.34} />
      <Sparkle x={992} y={160} s={34} o={0.9} phase={0.62} />
      <Sparkle x={946} y={700} s={18} o={0.5} phase={0.18} />
      <Sparkle x={520} y={112} s={14} o={0.4} phase={0.8} />
    </div>
  );
}

/* ---------- glow line that travels a rounded outline ---------- */
function GlowRing({ x, y, w, h, radius, angle, opacity, color, thickness = 7 }) {
  if (opacity <= 0.001) return null;
  return (
    <div style={{
      position: 'absolute', left: x, top: y, width: w, height: h,
      borderRadius: radius, padding: thickness, boxSizing: 'border-box', opacity,
      background: `conic-gradient(from ${angle}deg, rgba(255,255,255,0) 0deg, rgba(255,255,255,0) 232deg, ${color}00 240deg, ${color} 340deg, #ffffff 358deg, rgba(255,255,255,0) 360deg)`,
      WebkitMask: 'linear-gradient(#000,#000) content-box, linear-gradient(#000,#000)',
      WebkitMaskComposite: 'xor',
      mask: 'linear-gradient(#000,#000) content-box, linear-gradient(#000,#000)',
      maskComposite: 'exclude',
      filter: `drop-shadow(0 0 12px ${color}) drop-shadow(0 0 34px ${color}) drop-shadow(0 0 60px ${color}aa)`,
      pointerEvents: 'none',
    }} />
  );
}

/* ---------- hero (INTRODUCING / DEAL BUSTER / button / gift) ---------- */
const BOX = { x: 322, y: 268, w: 664, h: 288 };
const BTN = { x: 366, y: 622, w: 372, h: 104 };

function Hook({ x }) {
  const t = useTheme();
  return (
    <React.Fragment>
      <div style={{
        position: 'absolute', left: x, top: 78, width: 52, height: 52,
        border: `9px solid ${t.hook}`, borderRadius: '50%', borderTopColor: 'rgba(0,0,0,0)',
        transform: 'rotate(35deg)',
      }} />
    </React.Fragment>
  );
}

function Hero({ reveal = 1, shrink = 0, boxGlow = 0, boxAngle = 0, btnGlow = 0, btnAngle = 0 }) {
  const t = useTheme();
  const r = clamp(reveal, 0, 1);

  const panel = MOTION.draw(r, 0, 0.3);
  const gift = MOTION.pop(r, 0.1, 0.56);
  const intro = MOTION.draw(r, 0.2, 0.42);
  const box = MOTION.draw(r, 0.24, 0.5);
  const deal = MOTION.pop(r, 0.32, 0.64);
  const buster = MOTION.pop(r, 0.42, 0.74);
  const btn = MOTION.pop(r, 0.6, 0.92);

  const s = shrink > 0 ? animate({ from: 1, to: 0.04, start: 0, end: 1, ease: Easing.easeInCubic })(shrink) : 1;
  const o = shrink > 0 ? animate({ from: 1, to: 0, start: 0.5, end: 1, ease: Easing.easeInQuad })(shrink) : 1;

  return (
    <div style={{ position: 'absolute', inset: 0, transform: `scale(${s})`, opacity: o, transformOrigin: '50% 46%' }}>
      {/* hanging panel + hooks */}
      <div style={{ position: 'absolute', inset: 0, opacity: panel * 0.9, transform: `translateY(${(1 - panel) * -40}px)` }}>
        <div style={{
          position: 'absolute', left: 300, top: 96, width: 520, height: 470,
          background: 'linear-gradient(180deg, rgba(255,255,255,0.075), rgba(255,255,255,0.01))',
          clipPath: 'polygon(4% 0%, 96% 0%, 88% 100%, 12% 100%)',
        }} />
        <div style={{ position: 'absolute', left: 372, top: 104, width: 2, height: 200, background: 'rgba(255,255,255,0.16)', transform: 'rotate(-7deg)' }} />
        <div style={{ position: 'absolute', left: 742, top: 104, width: 2, height: 200, background: 'rgba(255,255,255,0.16)', transform: 'rotate(7deg)' }} />
        <Hook x={352} />
        <Hook x={718} />
      </div>

      {/* headline block */}
      <div style={{
        position: 'absolute', left: BOX.x, top: BOX.y, width: BOX.w, height: BOX.h,
        border: `5px solid ${t.green}`, borderRadius: 20, opacity: box,
        transform: `scale(${0.94 + box * 0.06})`, transformOrigin: '0% 50%',
        boxShadow: `0 0 26px ${t.green}33`,
      }} />

      <div style={{
        position: 'absolute', left: BOX.x, top: 196, width: BOX.w, textAlign: 'center',
        font: `600 34px/1 ${FONT_B}`, letterSpacing: '0.3em', color: '#F2ECFF',
        opacity: intro, transform: `translateY(${(1 - intro) * 16}px)`,
      }}>INTRODUCING</div>

      <div style={{ position: 'absolute', left: BOX.x, top: BOX.y + 46, width: BOX.w, textAlign: 'center', overflow: 'visible' }}>
        <div style={{
          font: `italic 900 132px/0.94 ${FONT_H}`, letterSpacing: '-0.015em', color: t.green,
          textShadow: `0 6px 0 rgba(0,0,0,0.35), 0 0 34px ${t.green}55`,
          opacity: deal, transform: `translateY(${(1 - deal) * -54}px) scale(${0.86 + deal * 0.14})`,
        }}>DEAL</div>
        <div style={{
          font: `italic 900 92px/1 ${FONT_H}`, letterSpacing: '0.02em', color: '#FFFFFF',
          textShadow: '0 5px 0 rgba(0,0,0,0.32)', marginTop: 12,
          opacity: buster, transform: `translateY(${(1 - buster) * 48}px) scale(${0.86 + buster * 0.14})`,
        }}>BUSTER</div>
      </div>

      {/* gift */}
      <img src="assets/gift.svg" alt="" style={{
        position: 'absolute', left: 74, top: 286, width: 300, height: 300,
        opacity: clamp(gift * 1.4, 0, 1),
        transform: `translateX(${(1 - gift) * -230}px) rotate(${(1 - gift) * -22}deg) scale(${0.8 + gift * 0.2})`,
        filter: 'drop-shadow(0 18px 26px rgba(0,0,0,0.45))',
      }} />

      {/* button */}
      <div style={{
        position: 'absolute', left: BTN.x, top: BTN.y, width: BTN.w, height: BTN.h,
        borderRadius: 999, background: `linear-gradient(180deg, ${t.green}, ${t.greenDeep})`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        font: `600 44px/1 ${FONT_B}`, color: '#17200A',
        boxShadow: `0 12px 30px rgba(0,0,0,0.35), 0 0 0 6px ${t.green}1f`,
        opacity: btn, transform: `scale(${0.7 + btn * 0.3})`, transformOrigin: '50% 50%',
      }}>Check it out</div>

      <GlowRing x={BOX.x - 4} y={BOX.y - 4} w={BOX.w + 8} h={BOX.h + 8} radius={24}
        angle={boxAngle} opacity={boxGlow} color={t.glow} />
      <GlowRing x={BTN.x - 4} y={BTN.y - 4} w={BTN.w + 8} h={BTN.h + 8} radius={999}
        angle={btnAngle} opacity={btnGlow} color={t.glow} thickness={6} />
    </div>
  );
}

/* ---------- calendar ---------- */
function Tick({ p }) {
  const t = useTheme();
  const a = MOTION.pop(p, 0, 1);
  const len = 40;
  return (
    <div style={{
      width: 88, height: 74, borderRadius: 10,
      background: `linear-gradient(180deg, ${t.tick}, ${t.tickDeep})`,
      border: '3px solid rgba(255,255,255,0.9)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      opacity: clamp(p * 3, 0, 1),
      transform: `translateY(${(1 - a) * -46}px) scale(${0.55 + a * 0.45})`,
      boxShadow: '0 4px 10px rgba(0,0,0,0.25)',
    }}>
      <svg width="54" height="42" viewBox="0 0 54 42">
        <polyline points="6,22 20,34 47,7" fill="none" stroke="#ffffff" strokeWidth="8"
          strokeLinecap="round" strokeLinejoin="round"
          strokeDasharray={len} strokeDashoffset={len * (1 - MOTION.draw(p, 0.25, 1))} />
      </svg>
    </div>
  );
}

function Popper({ p, flip }) {
  const t = useTheme();
  const L = 340;
  return (
    <svg width="190" height="190" viewBox="0 0 190 190" style={{ transform: flip ? 'scaleX(-1)' : 'none', overflow: 'visible' }}>
      <path d="M14 168 C 52 66, 150 44, 146 96 C 143 138, 78 122, 112 62" fill="none"
        stroke={t.green} strokeWidth="8" strokeLinecap="round"
        strokeDasharray={L} strokeDashoffset={-L * (1 - MOTION.draw(p, 0, 0.8))} opacity={clamp(p * 4, 0, 1)} />
      <path d="M4 128 L 44 118" fill="none" stroke={t.green} strokeWidth="8" strokeLinecap="round"
        opacity={clamp((p - 0.6) * 4, 0, 1)} />
    </svg>
  );
}

function CalendarBlock({ reveal = 1, shrink = 0, ticks = 6, tickP = () => 1, popper = 1 }) {
  const t = useTheme();
  const r = clamp(reveal, 0, 1);
  const inFly = MOTION.pop(r, 0, 0.34);
  const cap = MOTION.draw(r, 0.3, 0.52);
  const btn = MOTION.pop(r, 0.4, 0.7);

  const s = shrink > 0 ? animate({ from: 1, to: 0.04, start: 0, end: 1, ease: Easing.easeInCubic })(shrink) : 1;
  const o = shrink > 0 ? animate({ from: 1, to: 0, start: 0.5, end: 1, ease: Easing.easeInQuad })(shrink) : 1;

  const cells = [];
  for (let i = 0; i < 6; i++) {
    const p = clamp(tickP(i), 0, 1);
    cells.push(<div key={i} style={{ width: 88, height: 74 }}>{p > 0 ? <Tick p={p} /> : null}</div>);
  }

  return (
    <div style={{ position: 'absolute', inset: 0, transform: `scale(${s})`, opacity: o, transformOrigin: '50% 46%' }}>
      {/* poppers */}
      <div style={{ position: 'absolute', left: 118, top: 268, opacity: 1 }}><Popper p={popper} /></div>
      <div style={{ position: 'absolute', left: 772, top: 268 }}><Popper p={popper} flip /></div>

      <div style={{
        position: 'absolute', left: 0, right: 0, top: 178, height: 360,
        opacity: clamp(inFly * 2, 0, 1),
        transform: `scale(${0.06 + inFly * 0.94}) translateY(${(1 - inFly) * 40}px)`,
        transformOrigin: '50% 50%',
        filter: 'drop-shadow(0 26px 30px rgba(0,0,0,0.45))',
      }}>
      <div style={{ display: 'flex', justifyContent: 'center', perspective: 1500, height: 360 }}>
        <div style={{ display: 'flex', transformStyle: 'preserve-3d', transform: 'rotateX(11deg) rotateZ(-3.5deg)' }}>
          {/* left flap */}
          <div style={{ width: 128, height: 340, transform: 'rotateY(52deg)', transformOrigin: '100% 50%', background: '#CBB292' }}>
            <div style={{ height: 54, background: '#5E9A2C' }} />
          </div>
          {/* front face */}
          <div style={{ width: 424, height: 340, transform: 'rotateY(-11deg)', transformOrigin: '0% 50%', background: 'linear-gradient(180deg,#F2E2C9,#E2CDAC)', position: 'relative' }}>
            <div style={{ height: 54, background: 'linear-gradient(180deg,#7CBE3A,#63A128)' }} />
            <div style={{ position: 'absolute', left: 86, top: -22, width: 34, height: 34, border: '8px solid #1D3A16', borderRadius: '50%', borderBottomColor: 'rgba(0,0,0,0)', transform: 'rotate(-18deg)' }} />
            <div style={{ position: 'absolute', right: 86, top: -22, width: 34, height: 34, border: '8px solid #1D3A16', borderRadius: '50%', borderBottomColor: 'rgba(0,0,0,0)', transform: 'rotate(18deg)' }} />
            <div style={{
              position: 'absolute', left: 0, right: 0, top: 78, display: 'grid',
              gridTemplateColumns: 'repeat(3, 88px)', gap: 20, justifyContent: 'center',
            }}>{cells}</div>
          </div>
        </div>
      </div>
      </div>

      <div style={{
        position: 'absolute', left: 0, right: 0, top: 578, textAlign: 'center',
        font: `500 46px/1 ${FONT_B}`, color: '#EFE9FF', letterSpacing: '0.005em',
        opacity: cap, transform: `translateY(${(1 - cap) * 20}px)`,
      }}>New deals updated daily</div>

      <div style={{
        position: 'absolute', left: BTN.x, top: 662, width: BTN.w, height: 100,
        borderRadius: 999, background: `linear-gradient(180deg, ${t.green}, ${t.greenDeep})`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        font: `600 44px/1 ${FONT_B}`, color: '#17200A',
        boxShadow: `0 12px 30px rgba(0,0,0,0.35), 0 0 0 6px ${t.green}1f`,
        opacity: btn, transform: `scale(${0.7 + btn * 0.3})`,
      }}>Check it out</div>
    </div>
  );
}

/* ---------- scenes ---------- */
function SceneIntro() {
  const { progress } = useScene();
  return <React.Fragment><Backdrop /><Hero reveal={MOTION.draw(progress, 0, 0.94)} /></React.Fragment>;
}

function SceneGlow() {
  const { progress } = useScene();
  const t = useTheme();
  const p = progress;
  const boxOn = t.glowOn ? clamp(MOTION.draw(p, 0.04, 0.12) - MOTION.draw(p, 0.44, 0.52), 0, 1) : 0;
  const btnOn = t.glowOn ? clamp(MOTION.draw(p, 0.5, 0.58) - MOTION.draw(p, 0.9, 0.99), 0, 1) : 0;
  return (
    <React.Fragment>
      <Backdrop />
      <Hero reveal={1}
        boxGlow={boxOn} boxAngle={MOTION.draw(p, 0.04, 0.5) * 360}
        btnGlow={btnOn} btnAngle={MOTION.draw(p, 0.5, 0.96) * 360} />
    </React.Fragment>
  );
}

function SceneCollapse() {
  const { progress } = useScene();
  return <React.Fragment><Backdrop /><Hero reveal={1} shrink={progress} /></React.Fragment>;
}

function SceneCalendar() {
  const { progress } = useScene();
  const p = progress;
  const tickP = (i) => (p - (0.5 + i * 0.055)) / 0.14;
  return (
    <React.Fragment>
      <Backdrop />
      <CalendarBlock reveal={MOTION.draw(p, 0, 0.5)} tickP={tickP} popper={clamp((p - 0.86) / 0.13, 0, 1)} />
    </React.Fragment>
  );
}

function SceneReset() {
  const { progress } = useScene();
  return <React.Fragment><Backdrop /><CalendarBlock reveal={1} shrink={progress} /></React.Fragment>;
}

/* ---------- root ---------- */
const PALETTES = {
  'violet':  ['#4A1B96', '#2E0F63', '#170733', 'rgba(150,90,255,0.42)'],
  'indigo':  ['#33257F', '#211550', '#0F0A2A', 'rgba(120,110,255,0.38)'],
  'plum':    ['#5A1360', '#3A0B44', '#1C0522', 'rgba(210,80,220,0.34)'],
};

function DealBusterBanner() {
  const [tw, setTweak] = useTweaks(window.TWEAK_DEFAULTS);
  const pal = PALETTES[tw.palette] || PALETTES.violet;
  const theme = {
    bgTop: pal[0], bgMid: pal[1], bgBot: pal[2], bgHalo: pal[3],
    green: tw.accent, greenDeep: '#8FCF20', glow: '#DFFF8A',
    tick: '#7CC03C', tickDeep: '#5E9A2C', hook: 'rgba(20,6,45,0.9)',
    glowOn: tw.glowOn, roundBottom: tw.roundBottom,
  };
  return (
    <ThemeCtx.Provider value={theme}>
      <div style={{ width: '100%', height: '100%' }}>
        <SceneStage width={W} height={H} scenes={window.OM_SCENES} playback={window.OM_PLAYBACK} bg={pal[2]}>
          {{
            'Intro': SceneIntro,
            'Glow line': SceneGlow,
            'Collapse': SceneCollapse,
            'Calendar': SceneCalendar,
            'Reset': SceneReset,
          }}
        </SceneStage>
        <TweaksPanel>
          <TweakSection label="Look" />
          <TweakColor label="Accent" value={tw.accent}
            options={['#B6F24C', '#A3E635', '#7DF9C4', '#FFD34D']}
            onChange={(v) => setTweak('accent', v)} />
          <TweakRadio label="Backdrop" value={tw.palette}
            options={['violet', 'indigo', 'plum']}
            onChange={(v) => setTweak('palette', v)} />
          <TweakSection label="Motion" />
          <TweakToggle label="Glow sweep" value={tw.glowOn} onChange={(v) => setTweak('glowOn', v)} />
          <TweakToggle label="Rounded bottom" value={tw.roundBottom} onChange={(v) => setTweak('roundBottom', v)} />
          <TweakToggle label="Motion editor" value={tw.motionEditor} onChange={(v) => setTweak('motionEditor', v)} />
        </TweaksPanel>
      </div>
    </ThemeCtx.Provider>
  );
}

window.DealBusterBanner = DealBusterBanner;
