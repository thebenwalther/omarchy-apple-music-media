import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";

const source = readFileSync(new URL("../MediaController.js", import.meta.url), "utf8");
const qmlModule = { exports: {} as Record<string, (...args: any[]) => any> };
new Function("module", source)(qmlModule);
const controller = qmlModule.exports;

function player(pid: number, overrides: Record<string, unknown> = {}) {
  return {
    dbusName: `org.mpris.MediaPlayer2.chromium.instance${pid}`,
    identity: "Chromium",
    isPlaying: false,
    ...overrides,
  };
}

describe("Apple Music source detection", () => {
  test("matches the web-app PID to Chromium's MPRIS instance", () => {
    const pids = controller.appleMusicPids(JSON.stringify([
      { class: "firefox", pid: 9 },
      { class: "chrome-music.apple.com__-Default", pid: 5173 },
    ]));
    expect(pids).toEqual([5173]);
    expect(controller.applePlayerKey([player(5173)], pids)).toEndWith("instance5173");
  });

  test("prefers a playing manual source, then playing Apple Music", () => {
    const apple = player(10, { isPlaying: true });
    const spotify = { dbusName: "org.mpris.MediaPlayer2.spotify", identity: "Spotify", isPlaying: true };
    expect(controller.choosePlayerKey([apple, spotify], [10], spotify.dbusName, apple.dbusName)).toBe(spotify.dbusName);
    spotify.isPlaying = false;
    expect(controller.choosePlayerKey([apple, spotify], [10], spotify.dbusName, spotify.dbusName)).toBe(apple.dbusName);
  });

  test("falls back cleanly when PID correlation is unavailable", () => {
    const fallback = player(20);
    expect(controller.choosePlayerKey([fallback], [], "", fallback.dbusName)).toBe(fallback.dbusName);
  });
});

describe("formatting and timers", () => {
  test("bounds metadata and accepts only Chromium temporary artwork", () => {
    expect(controller.plainMetadata("<img src='file:///etc/passwd'>\nTrack", 40)).toBe("img src='file:///etc/passwd' Track");
    expect(controller.plainMetadata("x".repeat(600), 160)).toHaveLength(160);
    expect(controller.safeArtworkCandidate("file:///tmp/.org.chromium.Chromium.UGbLCZ")).toEqual({
      url: "file:///tmp/.org.chromium.Chromium.UGbLCZ",
      path: "/tmp/.org.chromium.Chromium.UGbLCZ",
    });
    expect(controller.safeArtworkCandidate("https://example.com/cover.jpg")).toEqual({ url: "", path: "" });
    expect(controller.safeArtworkCandidate("file:///etc/passwd")).toEqual({ url: "", path: "" });
    expect(controller.safeArtworkCandidate("file:///tmp/.org.chromium.Chromium.bad/path")).toEqual({ url: "", path: "" });
  });

  test("formats track and long-form countdown times", () => {
    expect(controller.formatTime(65)).toBe("1:05");
    expect(controller.formatTime(3661)).toBe("1:01:01");
    expect(controller.timerDeadline(15, 1000)).toBe(901000);
    expect(controller.timerRemaining(61000, 1000)).toBe("1:00");
  });

  test("ends on either the track boundary or a track change", () => {
    const track = player(30, { trackTitle: "A", trackArtist: "B", length: 180, position: 179 });
    const signature = controller.trackSignature(track);
    expect(controller.endOfTrackReached(track, signature, 1.5)).toBe(true);
    track.position = 10;
    expect(controller.endOfTrackReached(track, signature, 1.5)).toBe(false);
    track.trackTitle = "Next";
    expect(controller.endOfTrackReached(track, signature, 1.5)).toBe(true);
  });

  test("keeps logical track identity independent from delayed artwork", () => {
    const track = player(31, { trackTitle: "A", trackArtist: "B", trackAlbum: "C", trackArtUrl: "old.jpg" });
    const signature = controller.trackSignature(track);
    expect(controller.artworkSignature(track)).toBe("old.jpg");
    track.trackArtUrl = "new.jpg";
    expect(controller.trackSignature(track)).toBe(signature);
    expect(controller.artworkSignature(track)).toBe("new.jpg");
  });

  test("builds useful source labels", () => {
    const apple = player(40, { trackTitle: "Song", trackArtist: "Artist" });
    expect(controller.sourceName(apple, apple.dbusName)).toBe("Apple Music");
    expect(controller.sourceDetail(apple)).toBe("Song — Artist");
  });

  test("only advertises source-supported playback modes", () => {
    expect(controller.capabilities({ shuffleSupported: false, loopSupported: false })).toEqual({ shuffle: false, loop: false });
    expect(controller.capabilities({ shuffleSupported: true, loopSupported: false })).toEqual({ shuffle: true, loop: false });
  });

  test("models deadline fade, completion, and restored-volume math", () => {
    const track = player(50, { trackTitle: "Song", trackArtist: "Artist", length: 180, position: 30 });
    expect(controller.timerPhase("deadline", 10_000, track, "", 4_000, 5)).toEqual({ phase: "wait", progress: 0 });
    expect(controller.timerPhase("deadline", 10_000, track, "", 7_500, 5)).toEqual({ phase: "fade", progress: 0.5 });
    expect(controller.fadeVolume(0.8, 0.5)).toBeCloseTo(0.4);
    expect(controller.timerPhase("deadline", 10_000, track, "", 10_000, 5)).toEqual({ phase: "finish", progress: 1 });
  });

  test("models end-of-track fade and defensive track-change completion", () => {
    const track = player(60, { trackTitle: "Song", trackArtist: "Artist", length: 180, position: 176 });
    const signature = controller.trackSignature(track);
    const fading = controller.timerPhase("track", 0, track, signature, 0, 5);
    expect(fading.phase).toBe("fade");
    expect(fading.progress).toBeCloseTo(0.2);
    track.position = 179.9;
    expect(controller.timerPhase("track", 0, track, signature, 0, 5).phase).toBe("finish");
    track.position = 50;
    track.trackTitle = "Next";
    expect(controller.timerPhase("track", 0, track, signature, 0, 5).phase).toBe("finish");
    expect(controller.timerPhase("track", 0, null, signature, 0, 5).phase).toBe("idle");
  });
});

describe("cinematic presentation helpers", () => {
  test("chooses a vivid contrasting artwork accent or falls back", () => {
    const chosen = controller.bestArtworkAccent(["#222222", "#ff3366", "#777777"], "#abcdef", "#101010");
    expect(chosen).toBe("#ff3366");
    expect(controller.contrastRatio(chosen, "#101010")).toBeGreaterThanOrEqual(3);
    expect(controller.bestArtworkAccent(["invalid", "#151515"], "#abcdef", "#101010")).toBe("#abcdef");
  });

  test("uses deterministic responsive thresholds and preference defaults", () => {
    expect(controller.responsiveClass(320)).toBe("narrow");
    expect(controller.layoutMode(359)).toBe("narrow");
    expect(controller.layoutMode(360)).toBe("medium");
    expect(controller.layoutMode(459)).toBe("medium");
    expect(controller.layoutMode(460)).toBe("wide");
    expect(controller.responsiveGeometry(320)).toEqual({ mode: "narrow", targetWidth: 340, artworkSize: 156, stackedHero: true, preferenceColumns: 1, stackedActions: true });
    expect(controller.responsiveGeometry(400)).toEqual({ mode: "medium", targetWidth: 420, artworkSize: 142, stackedHero: false, preferenceColumns: 1, stackedActions: false });
    expect(controller.responsiveGeometry(520)).toEqual({ mode: "wide", targetWidth: 520, artworkSize: 176, stackedHero: false, preferenceColumns: 2, stackedActions: false });
    expect(controller.preferenceDefaults()).toEqual({
      dynamicArtworkColor: true,
      barProgress: true,
      barDisplayMode: "full",
      motionEnabled: true,
      trackChangeOsd: false,
      rememberSessionHistory: true,
    });
    expect(controller.normalizeBarDisplayMode("compact")).toBe("compact");
    expect(controller.normalizeBarDisplayMode("TITLE")).toBe("title");
    expect(controller.normalizeBarDisplayMode("unexpected")).toBe("full");
    expect(controller.normalizePopupPage("more", false)).toBe("more");
    expect(controller.normalizePopupPage("more", true)).toBe("player");
  });

  test("formats copy text and bounds deduplicated session history", () => {
    const first = player(70, { trackTitle: "One", trackArtist: "Artist", trackAlbum: "Album" });
    expect(controller.copyText(first)).toBe("One — Artist\nAlbum");
    let history = controller.addHistory([], first, 3, 1);
    history = controller.addHistory(history, first, 3, 2);
    expect(history).toHaveLength(1);
    for (let index = 2; index <= 5; index++) {
      history = controller.addHistory(history, player(70, { trackTitle: String(index), trackArtist: "Artist" }), 3, index);
    }
    expect(history).toHaveLength(3);
    expect(history.map((entry: { title: string }) => entry.title)).toEqual(["5", "4", "3"]);
    history = controller.addHistory(history, player(70, { trackTitle: "4", trackArtist: "Artist" }), 3, 6);
    expect(history.map((entry: { title: string }) => entry.title)).toEqual(["4", "5", "3"]);
    expect(controller.copyText({ title: "Only title" })).toBe("Only title");
    expect(controller.copyText({ album: "Only album" })).toBe("Only album");
  });

  test("applies palettes only to the artwork that produced them", () => {
    expect(controller.artworkAccentUpdate("", "old", ["#ff3366"], "#abcdef", "#101010"))
      .toEqual({ apply: true, color: "#abcdef" });
    expect(controller.artworkAccentUpdate("new", "old", ["#ff3366"], "#abcdef", "#101010"))
      .toEqual({ apply: false, color: "" });
    expect(controller.artworkAccentUpdate("new", "new", [], "#abcdef", "#101010"))
      .toEqual({ apply: false, color: "" });
    expect(controller.artworkAccentUpdate("new", "new", ["#ff3366"], "#abcdef", "#101010"))
      .toEqual({ apply: true, color: "#ee5281" });
  });

  test("recomputes restrained accents for theme changes and falls back safely", () => {
    expect(controller.blendColors("#ff0000", "#0000ff", 0.8)).toBe("#cc0033");
    const dark = controller.artworkAccentUpdate("cover", "cover", ["#ff3366"], "#abcdef", "#101010");
    const light = controller.artworkAccentUpdate("cover", "cover", ["#224488"], "#335577", "#f8f8f8");
    expect(dark).toEqual({ apply: true, color: "#ee5281" });
    expect(light.apply).toBe(true);
    expect(light.color).not.toBe(dark.color);
    expect(controller.contrastRatio(light.color, "#f8f8f8")).toBeGreaterThanOrEqual(3);
    expect(controller.artworkAccentUpdate("cover", "cover", ["invalid", "#151515"], "#abcdef", "#101010"))
      .toEqual({ apply: true, color: "#abcdef" });
  });

  test("formats relative history time and clamps custom sleep durations", () => {
    const now = 10 * 24 * 60 * 60 * 1000;
    expect(controller.relativeTime(now - 20_000, now)).toBe("now");
    expect(controller.relativeTime(now - 8 * 60_000, now)).toBe("8m ago");
    expect(controller.relativeTime(now - 3 * 60 * 60_000, now)).toBe("3h ago");
    expect(controller.relativeTime(now - 2 * 24 * 60 * 60_000, now)).toBe("2d ago");
    expect(controller.clampSleepMinutes(1)).toBe(5);
    expect(controller.clampSleepMinutes(47)).toBe(45);
    expect(controller.clampSleepMinutes(999)).toBe(180);
    expect(controller.timerDeadline(controller.clampSleepMinutes(47), 1_000)).toBe(2_701_000);
  });

  test("models source-popover close, idle presentation, and reduced motion", () => {
    expect(controller.sourcePopoverSelection("spotify")).toEqual({ selectedKey: "spotify", open: false });
    expect(controller.idlePresentation(false)).toEqual({
      title: "Apple Music",
      prompt: "Open to start listening",
      icon: "󰝚",
      controlsVisible: false,
    });
    expect(controller.idlePresentation(true).controlsVisible).toBe(true);
    expect(controller.motionDuration(true, 200)).toBe(200);
    expect(controller.motionDuration(false, 200)).toBe(0);
  });

  test("shares source, history, timer, palette, and popup counts across consumers", () => {
    let shared = controller.createSessionState();
    const firstConsumer = () => shared;
    const secondConsumer = () => shared;
    shared = controller.reduceSessionState(shared, { type: "source", key: "apple" });
    shared = controller.reduceSessionState(shared, { type: "history", history: [{ title: "One" }] });
    shared = controller.reduceSessionState(shared, { type: "timer", mode: "deadline" });
    shared = controller.reduceSessionState(shared, { type: "palette", artUrl: "cover.jpg" });
    shared = controller.reduceSessionState(shared, { type: "popup", open: true });
    shared = controller.reduceSessionState(shared, { type: "popup", open: true });
    expect(firstConsumer()).toBe(secondConsumer());
    expect(shared).toEqual({
      manualPlayerKey: "apple",
      history: [{ title: "One" }],
      sleepMode: "deadline",
      paletteArtUrl: "cover.jpg",
      popupConsumers: 2,
    });
    shared = controller.reduceSessionState(shared, { type: "popup", open: false });
    expect(shared.popupConsumers).toBe(1);
  });
});

describe("QML accessibility and theme structure", () => {
  const plugin = new URL("../", import.meta.url);

  test("uses alpha-based secondary text in light and dark theme roles", () => {
    const popup = readFileSync(new URL("ArtworkHero.qml", plugin), "utf8")
      + readFileSync(new URL("MorePage.qml", plugin), "utf8");
    const bar = readFileSync(new URL("BarWidget.qml", plugin), "utf8");
    expect(popup).toContain("Util.alpha(Color.popups.text, 0.68)");
    expect(bar).toContain("Util.alpha(root.bar.barForeground, 0.68)");
    expect(popup).not.toContain("Qt.darker");
    expect(bar).not.toContain("Qt.darker");
  });

  test("keeps bar title and artist on one horizontal line", () => {
    const bar = readFileSync(new URL("BarWidget.qml", plugin), "utf8");
    expect(bar).toContain("id: metadataRow");
    expect(bar).toContain('spacing: root.effectiveBarDisplayMode === "full" ? Style.spacing.controlGap : 0');
    expect(bar).toContain("Math.min(implicitWidth, Math.max(0, (parent.width - parent.spacing) * 0.62))");
    expect(bar).not.toContain("      Column {\n        visible: !root.bar.vertical");
  });

  test("owns keyboard-operable accessible controls", () => {
    const slider = readFileSync(new URL("MediaSlider.qml", plugin), "utf8");
    expect(slider).toContain("Accessible.role: Accessible.Slider");
    expect(slider).toContain("Keys.onLeftPressed");
    expect(slider).toContain("Keys.onSpacePressed");
    expect(slider).toContain("onWheel:");
    for (const file of ["MediaButton.qml", "MediaToggle.qml", "MediaDropdown.qml"])
      expect(readFileSync(new URL(file, plugin), "utf8")).toContain("Accessible.role:");
  });

  test("splits responsive pages around one shared QML session", () => {
    const session = readFileSync(new URL("MediaSession.qml", plugin), "utf8");
    const bar = readFileSync(new URL("BarWidget.qml", plugin), "utf8");
    const popup = readFileSync(new URL("PlayerPopup.qml", plugin), "utf8");
    expect(session).toStartWith("pragma Singleton");
    expect(session).toContain('target: "thebenwalther-apple-music"');
    expect(bar).toContain("Local.MediaSession");
    expect(popup).toContain("PlayerPage {");
    expect(popup).toContain("MorePage {");
    expect(readFileSync(new URL("SourcePopover.qml", plugin), "utf8")).toContain('Accessible.name: "Media sources"');
  });

  test("bounds untrusted MPRIS text and artwork before QML rendering", () => {
    const session = readFileSync(new URL("MediaSession.qml", plugin), "utf8");
    const bar = readFileSync(new URL("BarWidget.qml", plugin), "utf8");
    const hero = readFileSync(new URL("ArtworkHero.qml", plugin), "utf8");
    expect(session).toContain("MediaController.plainMetadata(currentPlayer.trackTitle, 160)");
    expect(session).toContain('["env", "LC_ALL=C", "stat", "-c", "%F|%s|%a", "--", probingArtPath]');
    expect(session).toContain('fields[0] === "regular file" && ownerPrivate');
    expect(session).toContain("encodedBytes <= 8 * 1024 * 1024");
    expect(bar).toContain("textFormat: Text.PlainText");
    expect(hero).toContain("textFormat: Text.PlainText");
    expect(bar).toContain("sourceSize.width: 64");
    expect(hero).toContain("sourceSize.width: 512");
  });
});
