const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "../kde/plasma/music-controls.js"), "utf8");
function panel(id, types) {
    const widgets = types.map((type, index) => ({id: index + 1, type}));
    return {id, widgets: () => widgets, addWidget: type => {
        const widget = {id: widgets.length + 1, type};
        widgets.push(widget);
        return widget;
    }};
}
const application = panel(29, ["org.kde.plasma.kickoff", "org.kde.plasma.mediacontroller"]);
const desktopOnly = panel(40, ["org.kde.plasma.folder"]);
const context = {panels: () => [application, desktopOnly], print: () => {}};
vm.runInNewContext(source, context);
vm.runInNewContext(source, context);
const types = application.widgets().map(w => w.type);
assert.equal(types.filter(t => t === "org.mysterious.blademusic").length, 1, "repeated setup must not duplicate the widget");
assert.equal(types[1], "org.kde.plasma.mediacontroller", "the existing media widget must stay");
assert.equal(desktopOnly.widgets().length, 1, "panels without a launcher or task manager are left alone");
console.log("Music panel preservation and idempotence checks passed.");
