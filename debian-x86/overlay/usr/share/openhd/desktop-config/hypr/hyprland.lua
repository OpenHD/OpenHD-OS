-- OpenHD skin for Hyprland 0.55 (Debian 13 backports).
hl.on("hyprland.start", function()
    hl.exec_cmd("sh -c 'mkdir -p /home/openhd/.local/state/openhd; exec qs -p /usr/share/openhd/desktop-config/quickshell >>/home/openhd/.local/state/openhd/quickshell.log 2>&1'")
    hl.exec_cmd("mako -c /usr/share/openhd/desktop-config/mako/config")
    hl.exec_cmd("lxpolkit")
    hl.exec_cmd("nm-tray")
end)

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.config({
    general = {
        gaps_in = 7, gaps_out = 16, border_size = 2, resize_on_border = true,
        layout = "dwindle",
        col = { active_border = { colors = {"rgba(71dce9ee)", "rgba(407eb8cc)"}, angle = 35 }, inactive_border = "rgba(2a3b5366)" },
    },
    decoration = {
        rounding = 14, rounding_power = 2,
        active_opacity = 1.0, inactive_opacity = 0.97,
        shadow = { enabled = true, range = 18, render_power = 3, color = 0x99101928 },
        blur = { enabled = true, size = 4, passes = 2, vibrancy = 0.12 },
    },
    animations = { enabled = true },
    dwindle = { preserve_split = true },
    input = { kb_layout = "us", follow_mouse = 1, touchpad = { natural_scroll = true } },
    misc = { force_default_wallpaper = -1, disable_hyprland_logo = true, disable_splash_rendering = true },
})
hl.curve("openhdEase", { type = "bezier", points = {{0.16, 1}, {0.3, 1}} })
hl.animation({ leaf = "global", enabled = true, speed = 5, bezier = "openhdEase" })
hl.bind("SUPER + Return", hl.dsp.exec_cmd("foot --config /usr/share/openhd/desktop-config/foot/foot.ini"))
hl.bind("SUPER + E", hl.dsp.exec_cmd("thunar"))
hl.bind("SUPER + K", hl.dsp.exec_cmd("/usr/local/sbin/openhd-shell-action keyboard"))
hl.bind("SUPER + N", hl.dsp.exec_cmd("/usr/local/sbin/openhd-shell-action network"))
hl.bind("SUPER + Tab", hl.dsp.exec_cmd("/usr/local/sbin/openhd-shell-action flight"))
hl.bind("ALT + Tab", hl.dsp.window.cycle_next())
hl.bind("ALT + SHIFT + Tab", hl.dsp.window.cycle_next({ next = false }))
hl.bind("CTRL + ALT + Delete", hl.dsp.exec_cmd("gnome-system-monitor"))
hl.bind("ALT + F4", hl.dsp.window.close())
hl.bind("SUPER + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + C", hl.dsp.window.close())
hl.bind("SUPER + Escape", hl.dsp.exec_cmd("/usr/local/sbin/openhd-shell-action power"))
hl.bind("SUPER + left", hl.dsp.focus({ direction = "left" }))
hl.bind("SUPER + right", hl.dsp.focus({ direction = "right" }))
hl.bind("SUPER + up", hl.dsp.focus({ direction = "up" }))
hl.bind("SUPER + down", hl.dsp.focus({ direction = "down" }))
for workspace = 1, 4 do
    hl.bind("SUPER + " .. workspace, hl.dsp.focus({ workspace = workspace }))
    hl.bind("SUPER + SHIFT + " .. workspace, hl.dsp.window.move({ workspace = workspace }))
end
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.window_rule({ match = { class = ".*" }, float = true, center = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("/usr/local/sbin/openhd-shell-action volume-up"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("/usr/local/sbin/openhd-shell-action volume-down"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("/usr/local/sbin/openhd-shell-action volume-mute"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("/usr/local/sbin/openhd-shell-action brightness-up"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("/usr/local/sbin/openhd-shell-action brightness-down"), { locked = true, repeating = true })
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
