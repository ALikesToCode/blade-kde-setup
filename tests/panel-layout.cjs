const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "../kde/plasma/blade-panels.js"), "utf8");
let nextId = 100;

function configurable(object) {
    object.config = {};
    object.currentConfigGroup = [];
    object.readConfig = (key, fallback) => {
        const value = object.config[object.currentConfigGroup.concat(key).join("/")];
        return value === undefined ? fallback : value;
    };
    object.writeConfig = (key, value) => {
        object.config[object.currentConfigGroup.concat(key).join("/")] = value;
    };
    object.reloadConfig = () => {};
    return object;
}

function makePanel(screen, types) {
    const panel = configurable({id: nextId++, screen, list: []});
    panel.widgets = () => panel.list.slice();
    panel.addWidget = type => {
        if (type === "org.kde.plasma.unavailable") {
            return null;
        }
        const widget = configurable({id: nextId++, type});
        widget.remove = () => panel.list.splice(panel.list.indexOf(widget), 1);
        panel.list.push(widget);
        return widget;
    };
    types.forEach(type => panel.addWidget(type));
    panel.currentConfigGroup = ["General"];
    panel.writeConfig("AppletOrder", panel.list.map(w => w.id).join(";"));
    panel.currentConfigGroup = [];
    return panel;
}

function order(panel) {
    const ids = panel.config["General/AppletOrder"].split(";");
    return ids.map(id => panel.list.find(w => String(w.id) === id).type);
}

const oldLayout = [
    "org.kde.plasma.kickoff", "org.kde.plasma.icontasks", "org.kde.plasma.mediacontroller",
    "org.kde.plasma.systemmonitor.cpu", "org.kde.plasma.systemmonitor.memory",
    "org.kde.plasma.systemmonitor", "org.kde.plasma.systemmonitor.net", "org.kde.plasma.pager",
    "org.kde.plasma.marginsseparator", "org.kde.plasma.systemtray", "org.kde.plasma.brightness",
    "org.mysterious.bladepower", "org.kde.plasma.eventcalendar", "org.kde.plasma.showdesktop",
    "org.mysterious.blademusic", "user.custom.widget"
];
const laptop = makePanel(0, oldLayout);
const external = makePanel(1, oldLayout.filter(t => t !== "org.mysterious.blademusic"));
const tray = laptop.list.find(w => w.type === "org.kde.plasma.systemtray");
tray.config["General/shownItems"] = ["org.kde.plasma.clipboard", "org.kde.plasma.volume"];

const context = {
    panels: () => [laptop, external],
    desktops: () => [{screen: 0}, {screen: 1}],
    print: () => {},
    BLADE_ICON_PATH: "/icon.png",
    BLADE_GPU_PREFIX: "gpu/gpu1",
    BLADE_GPU_TITLE: "GPU",
    BLADE_REPLACE_EXISTING: false,
    BLADE_REPLACE_CLOCK: false,
    BLADE_POSITION_ONLY: false
};
vm.runInNewContext(source, context);
vm.runInNewContext(source, context);

assert.deepEqual(order(laptop), [
    "org.kde.plasma.kickoff", "org.kde.plasma.icontasks", "org.kde.plasma.panelspacer",
    "org.kde.plasma.mediacontroller", "org.mysterious.blademusic", "org.kde.plasma.panelspacer",
    "org.kde.plasma.systemmonitor", "org.kde.plasma.systemtray", "org.mysterious.bladepower",
    "org.kde.plasma.eventcalendar", "org.kde.plasma.showdesktop", "user.custom.widget"
], "laptop panel: apps left, music centred, status right, user widgets kept");
assert.equal(laptop.list.length, 12, "repeated runs add no duplicate spacers or widgets");

const externalOrder = order(external);
assert.ok(externalOrder.includes("org.kde.plasma.pager"), "the large display keeps workspaces");
assert.ok(!externalOrder.includes("org.mysterious.blademusic"), "optional widgets are not installed here");
for (const retired of ["org.kde.plasma.systemmonitor.cpu", "org.kde.plasma.systemmonitor.net",
    "org.kde.plasma.brightness", "org.kde.plasma.marginsseparator"]) {
    assert.ok(!externalOrder.includes(retired), `${retired} is retired`);
}
assert.equal(laptop.opacity, "adaptive");
assert.equal(external.hiding, "autohide");

const shown = tray.config["General/shownItems"];
assert.ok(shown.includes("org.kde.plasma.brightness"), "brightness moves into the tray");
assert.ok(!shown.includes("org.kde.plasma.clipboard"), "clipboard goes under the tray arrow");
assert.ok(tray.config["General/hiddenItems"].includes("org.kde.plasma.mediacontroller"),
    "the panel media widget is the only visible player");

const telemetry = laptop.list.find(w => w.type === "org.kde.plasma.systemmonitor");
assert.equal(telemetry.config["Appearance/chartFace"], "org.kde.ksysguard.textonly");
assert.deepEqual(JSON.parse(telemetry.config["Sensors/highPrioritySensorIds"]),
    ["memory/physical/usedPercent", "network/all/download", "cpu/all/usage", "gpu/gpu1/usage"]);
console.log("Panel layout checks passed.");
