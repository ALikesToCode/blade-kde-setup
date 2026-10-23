const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "../kde/plasma/power-controls.js"), "utf8");
const widgets = [{id: 1, type: "org.kde.plasma.kickoff"}, {id: 2, type: "user.custom.widget"}];
const panel = {id: 29, widgets: () => widgets, addWidget: type => {
    const widget = {id: widgets.length + 1, type};
    widgets.push(widget);
    return widget;
}};
const context = {panels: () => [panel], print: () => {}};
vm.runInNewContext(source, context);
vm.runInNewContext(source, context);
assert.equal(widgets.length, 4, "repeated setup must not duplicate controls");
assert.equal(widgets[1].type, "user.custom.widget", "existing widgets must survive");
assert.equal(widgets.filter(w => w.type === "org.kde.plasma.brightness").length, 1);
assert.equal(widgets.filter(w => w.type === "org.mysterious.bladepower").length, 1);
const trayWidgets = [{id: 1, type: "org.kde.plasma.icontasks"}, {id: 2, type: "org.kde.plasma.systemtray"}];
const trayPanel = {id: 30, widgets: () => trayWidgets, addWidget: type => {
    const widget = {id: trayWidgets.length + 1, type};
    trayWidgets.push(widget);
    return widget;
}};
vm.runInNewContext(source, {panels: () => [trayPanel], print: () => {}});
assert.equal(trayWidgets.filter(w => w.type === "org.kde.plasma.brightness").length, 0,
    "a panel with a tray keeps brightness in the tray");
assert.equal(trayWidgets.filter(w => w.type === "org.mysterious.bladepower").length, 1);
console.log("Power panel preservation and idempotence checks passed.");
