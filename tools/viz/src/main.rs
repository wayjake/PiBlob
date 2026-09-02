// PiBlob visualizer: a plasma field under copper bars, for a CRT over composite.
//
// Runs until stopped. Escape or Q quits if a keyboard is attached; otherwise
// Ctrl-C over ssh -t, or `pkill -x piblob-viz` from another shell.
//
// Everything here obeys the same display rules the game does. The render driver
// is forced to software because SDL's default pick on this board draws nothing.
// Copper bar strips are 2px tall, never 1, because an interlaced signal makes
// single-scanline features strobe. Palettes are generated with saturation held
// down and reds pulled down further still, because composite chroma bandwidth
// is narrow and saturated red smears sideways.

use sdl2::event::Event;
use sdl2::keyboard::Keycode;
use sdl2::pixels::{Color, PixelFormatEnum};
use sdl2::rect::Rect;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

const W: usize = 320;
const H: usize = 240;
const LUT: usize = 1024;

// ---------------------------------------------------------------- randomness
// Hand-rolled xorshift rather than the rand crate, per AGENTS.md.
struct Rng(u32);
impl Rng {
    fn next(&mut self) -> u32 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 17;
        self.0 ^= self.0 << 5;
        self.0
    }
    fn f32(&mut self) -> f32 {
        (self.next() >> 8) as f32 / 16_777_216.0
    }
    fn range(&mut self, lo: f32, hi: f32) -> f32 {
        lo + self.f32() * (hi - lo)
    }
}

// ------------------------------------------------------------------- palette
fn hsv_to_rgb(h: f32, s: f32, v: f32) -> (u8, u8, u8) {
    let h = (h.fract() + 1.0).fract() * 6.0;
    let i = h.floor() as i32;
    let f = h - i as f32;
    let p = v * (1.0 - s);
    let q = v * (1.0 - s * f);
    let t = v * (1.0 - s * (1.0 - f));
    let (r, g, b) = match i % 6 {
        0 => (v, t, p),
        1 => (q, v, p),
        2 => (p, v, t),
        3 => (p, q, v),
        4 => (t, p, v),
        _ => (v, p, q),
    };
    (
        (r * 255.0) as u8,
        (g * 255.0) as u8,
        (b * 255.0) as u8,
    )
}

// A palette that wraps seamlessly at 256 so colour cycling has no visible seam.
fn make_palette(rng: &mut Rng) -> [(u8, u8, u8); 256] {
    let base = rng.f32();
    let span = rng.range(0.25, 0.9);
    let sat_base = rng.range(0.30, 0.52);
    let sat_amp = rng.range(0.05, 0.16);
    let val_base = rng.range(0.42, 0.62);
    let val_amp = rng.range(0.18, 0.34);
    let hue_cycles = [1.0f32, 1.0, 2.0][(rng.next() % 3) as usize];
    let val_cycles = [1.0f32, 2.0, 3.0][(rng.next() % 3) as usize];

    let mut pal = [(0u8, 0u8, 0u8); 256];
    for (i, slot) in pal.iter_mut().enumerate() {
        let t = i as f32 / 256.0;
        let tau = t * std::f32::consts::TAU;
        let hue = base + span * (tau * hue_cycles).sin() * 0.5;
        let mut sat = sat_base + sat_amp * (tau * 2.0).sin();
        let val = (val_base + val_amp * (tau * val_cycles).sin()).clamp(0.05, 0.86);

        // Pull saturation down near red. Composite smears it horizontally.
        let hue_wrapped = (hue.fract() + 1.0).fract();
        let dist_to_red = (hue_wrapped.min(1.0 - hue_wrapped)) * 6.0;
        if dist_to_red < 1.0 {
            sat *= 0.45 + 0.55 * dist_to_red;
        }
        *slot = hsv_to_rgb(hue, sat.clamp(0.0, 0.60), val);
    }
    pal
}

fn main() {
    let seed = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.subsec_nanos() | 1)
        .unwrap_or(0x1234_5678);
    let mut rng = Rng(seed);

    let driver = std::env::var("PIBLOB_RENDERER").unwrap_or_else(|_| "software".into());
    sdl2::hint::set("SDL_VIDEODRIVER", "kmsdrm");
    sdl2::hint::set("SDL_RENDER_SCALE_QUALITY", "0");
    sdl2::hint::set("SDL_RENDER_DRIVER", &driver);

    let sdl = sdl2::init().expect("sdl init");
    let video = sdl.video().expect("video");
    let window = video
        .window("piblob-viz", 720, 480)
        .fullscreen_desktop()
        .build()
        .expect("window");
    sdl.mouse().show_cursor(false);
    let mut canvas = window
        .into_canvas()
        .present_vsync()
        .build()
        .expect("canvas");
    canvas.set_logical_size(W as u32, H as u32).expect("logical size");
    let mut pump = sdl.event_pump().expect("pump");

    let name = canvas.info().name.to_string();
    println!("renderer: {}", name);
    assert_eq!(name, driver, "SDL handed back a different render driver");

    let creator = canvas.texture_creator();
    let mut tex = creator
        .create_texture_streaming(PixelFormatEnum::ARGB8888, W as u32, H as u32)
        .expect("texture");

    // Sine lookup scaled to a sixth of the palette, so four terms sum across it.
    let sine: Vec<i32> = (0..LUT)
        .map(|i| {
            let a = i as f32 / LUT as f32 * std::f32::consts::TAU;
            ((a.sin() * 0.5 + 0.5) * 63.0) as i32
        })
        .collect();

    // Radial distance from centre, precomputed once: the only per-pixel sqrt.
    let mut radial = vec![0u16; W * H];
    for y in 0..H {
        for x in 0..W {
            let dx = x as f32 - W as f32 * 0.5;
            let dy = (y as f32 - H as f32 * 0.5) * 1.15; // 4:3 pixels are not square
            radial[y * W + x] = (dx * dx + dy * dy).sqrt() as u16;
        }
    }

    let mut pal_a = make_palette(&mut rng);
    let mut pal_b = make_palette(&mut rng);
    let mut pal = pal_a;
    let mut mix: f32 = 0.0;
    const FADE_FRAMES: f32 = 150.0; // 2.5s crossfade
    const HOLD_FRAMES: u32 = 60 * 18; // 18s on each palette
    let mut hold = HOLD_FRAMES;

    // Copper bars, each with its own speed and phase.
    let bars: Vec<(f32, f32, u8)> = (0..6)
        .map(|_| {
            (
                rng.range(0.22, 0.62),
                rng.range(0.0, std::f32::consts::TAU),
                (rng.next() % 256) as u8,
            )
        })
        .collect();

    let mut col_x = vec![0i32; W];
    let mut col_y = vec![0i32; H];
    let mut col_d = vec![0i32; W + H];

    // Optional argument: run for N seconds then exit with a report. With no
    // argument it runs until stopped.
    let limit: Option<f64> = std::env::args().nth(1).and_then(|a| a.parse().ok());

    let start = Instant::now();
    let mut frames: u64 = 0;
    let mut last_report = Instant::now();

    'main: loop {
        for ev in pump.poll_iter() {
            match ev {
                Event::Quit { .. }
                | Event::KeyDown {
                    keycode: Some(Keycode::Escape),
                    ..
                }
                | Event::KeyDown {
                    keycode: Some(Keycode::Q),
                    ..
                } => break 'main,
                _ => {}
            }
        }

        if let Some(secs) = limit {
            if start.elapsed().as_secs_f64() >= secs {
                break 'main;
            }
        }

        let t = start.elapsed().as_secs_f32();

        // Palette lifecycle: hold, then crossfade into a freshly random one.
        if hold > 0 {
            hold -= 1;
        } else {
            mix += 1.0 / FADE_FRAMES;
            if mix >= 1.0 {
                pal_a = pal_b;
                pal_b = make_palette(&mut rng);
                mix = 0.0;
                hold = HOLD_FRAMES;
            }
        }
        for i in 0..256 {
            let (ar, ag, ab) = pal_a[i];
            let (br, bg, bb) = pal_b[i];
            let l = |a: u8, b: u8| (a as f32 + (b as f32 - a as f32) * mix) as u8;
            pal[i] = (l(ar, br), l(ag, bg), l(ab, bb));
        }

        // Separable plasma terms, so the inner loop is four table lookups.
        let idx = |ph: f32, step: f32, i: usize| -> usize {
            ((ph + step * i as f32) as i64).rem_euclid(LUT as i64) as usize
        };
        let p1 = t * 47.0;
        let p2 = t * 31.0;
        let p3 = t * -53.0;
        let p4 = t * 67.0;
        for x in 0..W {
            col_x[x] = sine[idx(p1, 3.7, x)];
        }
        for y in 0..H {
            col_y[y] = sine[idx(p2, 5.1, y)];
        }
        for d in 0..(W + H) {
            col_d[d] = sine[idx(p3, 2.3, d)];
        }
        let cycle = (t * 40.0) as i32;

        tex.with_lock(None, |buf: &mut [u8], pitch: usize| {
            for y in 0..H {
                let row = y * pitch;
                let cy = col_y[y];
                for x in 0..W {
                    let r = radial[y * W + x] as usize;
                    let v = col_x[x]
                        + cy
                        + col_d[x + y]
                        + sine[((p4 as i64 + (r as i64) * 4).rem_euclid(LUT as i64)) as usize];
                    let (cr, cg, cb) = pal[((v + cycle) & 255) as usize];
                    let o = row + x * 4;
                    buf[o] = cb;
                    buf[o + 1] = cg;
                    buf[o + 2] = cr;
                    buf[o + 3] = 255;
                }
            }
        })
        .expect("lock");

        canvas.clear();
        canvas.copy(&tex, None, None).expect("copy");

        // Copper bars on top. Strips are 2px so they cannot strobe on interlace.
        for (speed, phase, hue) in &bars {
            let yc = H as f32 * 0.5 + (H as f32 * 0.40) * (t * speed * 2.4 + phase).sin();
            let half = 7i32;
            let mut s = -half;
            while s < half {
                let yy = yc as i32 + s;
                if yy >= 0 && yy + 2 <= H as i32 {
                    // Brightest through the middle of the bar, dim at the edges.
                    let k = 1.0 - (s as f32 / half as f32).abs();
                    let (r, g, b) = pal[((*hue as i32 + cycle * 2) & 255) as usize];
                    let boost = 0.35 + 0.65 * k;
                    canvas.set_draw_color(Color::RGB(
                        (r as f32 * boost + 90.0 * k * k).min(235.0) as u8,
                        (g as f32 * boost + 90.0 * k * k).min(235.0) as u8,
                        (b as f32 * boost + 90.0 * k * k).min(235.0) as u8,
                    ));
                    canvas.fill_rect(Rect::new(0, yy, W as u32, 2)).ok();
                }
                s += 2;
            }
        }

        canvas.present();
        frames += 1;

        if last_report.elapsed().as_secs() >= 60 {
            println!(
                "{} frames, {:.1} Hz average",
                frames,
                frames as f64 / start.elapsed().as_secs_f64()
            );
            last_report = Instant::now();
        }
    }

    println!(
        "stopped after {} frames, {:.1} Hz average",
        frames,
        frames as f64 / start.elapsed().as_secs_f64()
    );
}
