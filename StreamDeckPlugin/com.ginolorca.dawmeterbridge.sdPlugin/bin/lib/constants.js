// Names and numbers shared by the plugin modules. See docs/CONTROL.md.

export const PLUGIN_UUID = "com.ginolorca.dawmeterbridge";
export const PLUGIN_VERSION = "0.2.0.0";

/** The app's bundle identifier, for `open -g -b` and Stream Deck's ApplicationsToMonitor. */
export const APP_BUNDLE_ID = "com.ginolorca.DAWMeterBridge";

/** Action UUID -> the app switch it drives (`op` in a `ctl` message, field in `ctl.state`). */
export const ACTION_SWITCHES = Object.freeze({
    "com.ginolorca.dawmeterbridge.bridge": "bridge",
    "com.ginolorca.dawmeterbridge.main": "main",
});

/** The app's control port (UDP, 127.0.0.1). DAWMB_CONTROL_PORT overrides it. */
export const DEFAULT_CONTROL_PORT = 47802;

export const CONTROL_PROTOCOL_VERSION = 1;

/** Timings from docs/CONTROL.md, plus the plugin's own. All in milliseconds. */
export const TIMING = Object.freeze({
    /** `ctl.sub` keep-alive period. */
    keepAliveMs: 2000,
    /** Keep-alive period while waiting for the app to come up (after a launch). */
    fastKeepAliveMs: 500,
    /** The app is offline after this long without a `ctl.state`. */
    offlineMs: 5000,
    /** At startup, the app counts as offline if the first `ctl.sub` gets no answer this fast. */
    probeMs: 1500,
    /** After `open -g -b`, how long the app has to answer before the key shows an alert. */
    launchTimeoutMs: 15000,
    /** How long a key press waits for the app's `ctl.state` answer before it shows an alert. */
    commandTimeoutMs: 2000,
    /** How long to wait before binding the UDP socket again after it failed. */
    rebindMs: 1000,
});
