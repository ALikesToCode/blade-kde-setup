// Plasma 6 layout applied by scripts/apply-panels.sh.
// Runtime values are injected as BLADE_* globals by the shell wrapper.

var bladeStatusItems = [
    "org.kde.plasma.networkmanagement",
    "org.kde.plasma.bluetooth",
    "org.kde.plasma.volume",
    "org.kde.plasma.battery",
    "org.kde.plasma.notifications"
];

var bladeExtraTrayItems = bladeStatusItems.concat([
    "org.kde.plasma.mediacontroller",
    "org.kde.plasma.clipboard",
    "org.kde.kscreen",
    "org.kde.kdeconnect"
]);

var bladePrimaryOrder = [
    "org.kde.plasma.kickoff",
    "org.kde.plasma.icontasks",
    "org.kde.plasma.mediacontroller",
    "org.kde.plasma.systemmonitor.cpu",
    "org.kde.plasma.systemmonitor.memory",
    "org.kde.plasma.systemmonitor",
    "org.kde.plasma.pager",
    "org.kde.plasma.marginsseparator",
    "org.kde.plasma.systemtray",
    "org.kde.plasma.digitalclock",
    "org.kde.plasma.showdesktop"
];

var bladeSecondaryOrder = [
    "org.kde.plasma.kickoff",
    "org.kde.plasma.icontasks",
    "org.kde.plasma.mediacontroller",
    "org.kde.plasma.pager",
    "org.kde.plasma.marginsseparator",
    "org.kde.plasma.systemmonitor.cpu",
    "org.kde.plasma.systemmonitor.memory",
    "org.kde.plasma.systemmonitor",
    "org.kde.plasma.systemtray",
    "org.kde.plasma.digitalclock",
    "org.kde.plasma.showdesktop"
];

function bladeWrite(widget, group, values) {
    widget.currentConfigGroup = group;
    Object.keys(values).forEach(function (key) {
        widget.writeConfig(key, values[key]);
    });
    widget.currentConfigGroup = [];
    widget.reloadConfig();
}

function bladeReadList(widget, group, key) {
    widget.currentConfigGroup = group;
    var current = widget.readConfig(key, []);
    widget.currentConfigGroup = [];
    if (Array.isArray(current)) {
        return current;
    }
    if (typeof current !== "string" || current.length === 0) {
        return [];
    }
    if (current.charAt(0) === "[") {
        try {
            var parsed = JSON.parse(current);
            return Array.isArray(parsed) ? parsed : [];
        } catch (error) {
            return [];
        }
    }
    return current.split(",").filter(function (value) {
        return value.length > 0;
    });
}

function bladeMergeList(widget, group, key, wanted) {
    var merged = bladeReadList(widget, group, key);
    wanted.forEach(function (value) {
        if (merged.indexOf(value) === -1) {
            merged.push(value);
        }
    });
    var values = {};
    values[key] = merged;
    bladeWrite(widget, group, values);
}

function bladeWidgetsOfType(panel, type) {
    return panel.widgets().filter(function (widget) {
        return widget.type === type;
    });
}

function bladeAddWidget(panel, type) {
    var before = {};
    panel.widgets().forEach(function (widget) {
        before[widget.id] = true;
    });

    var result = panel.addWidget(type);
    if (result && result.id !== undefined) {
        return result;
    }

    var after = panel.widgets();
    for (var index = 0; index < after.length; ++index) {
        if (!before[after[index].id] && after[index].type === type) {
            return after[index];
        }
    }
    print("Blade panels: unavailable widget " + type);
    return null;
}

function bladeEnsureWidget(panel, type) {
    var matches = bladeWidgetsOfType(panel, type);
    return matches.length > 0 ? matches[0] : bladeAddWidget(panel, type);
}

function bladeConfigureMonitor(widget, kind) {
    if (!widget) {
        return;
    }

    var sensor;
    var title;
    var color;
    var lowSensors;
    var label;

    if (kind === "cpu") {
        sensor = "cpu/all/usage";
        title = "CPU Usage";
        color = "56,189,248";
        lowSensors = ["cpu/all/averageTemperature", "cpu/all/averageFrequency", "cpu/all/coreCount"];
        label = "CPU";
    } else if (kind === "memory") {
        sensor = "memory/physical/used";
        title = "Memory Usage";
        color = "80,250,123";
        lowSensors = ["memory/physical/total", "memory/physical/application", "memory/physical/cache"];
        label = "RAM";
    } else {
        sensor = BLADE_GPU_PREFIX + "/usage";
        title = BLADE_GPU_TITLE;
        color = "66,133,244";
        lowSensors = [
            BLADE_GPU_PREFIX + "/temperature",
            BLADE_GPU_PREFIX + "/usedVram",
            BLADE_GPU_PREFIX + "/totalVram",
            BLADE_GPU_PREFIX + "/power"
        ];
        label = "GPU";
    }

    bladeWrite(widget, [], {
        "CurrentPreset": "org.kde.plasma.systemmonitor",
        "highPrioritySensorIds": JSON.stringify([sensor]),
        "lowPrioritySensorIds": JSON.stringify(lowSensors),
        "showTitle": true,
        "title": title,
        "totalSensors": JSON.stringify([kind === "memory" ? "memory/physical/usedPercent" : sensor]),
        "updateRateLimit": 1000
    });
    bladeWrite(widget, ["Appearance"], {
        "chartFace": "org.kde.ksysguard.piechart",
        "title": title
    });
    bladeWrite(widget, ["FaceConfig"], {
        "fromAngle": -150,
        "toAngle": 150,
        "rangeAuto": kind === "memory",
        "rangeFrom": 0,
        "rangeTo": 100,
        "rangeFromMultiplier": 1,
        "rangeToMultiplier": 1,
        "showLegend": true,
        "smoothEnds": true
    });
    var colorConfig = {};
    colorConfig[sensor] = color;
    bladeWrite(widget, ["SensorColors"], colorConfig);
    var labelConfig = {};
    labelConfig[sensor] = label;
    bladeWrite(widget, ["SensorLabels"], labelConfig);
    bladeWrite(widget, ["Sensors"], {
        "highPrioritySensorIds": JSON.stringify([sensor]),
        "lowPrioritySensorIds": JSON.stringify(kind === "memory" ? ["memory/physical/total"] : lowSensors),
        "totalSensors": JSON.stringify([kind === "memory" ? "memory/physical/usedPercent" : sensor])
    });
}

function bladeConfigureWidget(widget, type) {
    if (!widget) {
        return;
    }

    if (type === "org.kde.plasma.kickoff") {
        bladeWrite(widget, ["General"], {"icon": BLADE_ICON_PATH});
    } else if (type === "org.kde.plasma.icontasks") {
        bladeMergeList(widget, ["General"], "launchers", [
            "applications:systemsettings.desktop",
            "preferred://filemanager",
            "applications:zen.desktop"
        ]);
    } else if (type === "org.kde.plasma.pager") {
        bladeWrite(widget, ["General"], {
            "displayedText": "Number",
            "showWindowIcons": true,
            "wrapPage": true
        });
    } else if (type === "org.kde.plasma.systemtray") {
        bladeMergeList(widget, ["General"], "extraItems", bladeExtraTrayItems);
        bladeMergeList(widget, ["General"], "shownItems", bladeStatusItems);
    } else if (type === "org.kde.plasma.digitalclock") {
        bladeWrite(widget, ["Appearance"], {
            "showDate": true,
            "showSeconds": false
        });
    } else if (type === "org.kde.plasma.systemmonitor.cpu") {
        bladeConfigureMonitor(widget, "cpu");
    } else if (type === "org.kde.plasma.systemmonitor.memory") {
        bladeConfigureMonitor(widget, "memory");
    } else if (type === "org.kde.plasma.systemmonitor") {
        bladeConfigureMonitor(widget, "gpu");
    }
}

function bladeConfigurePanel(panel, screenIndex) {
    panel.screen = screenIndex;
    panel.location = "bottom";
    panel.height = 46;
    panel.floating = true;
    panel.alignment = "center";
    panel.lengthMode = "fill";
    panel.opacity = "opaque";
    // Keep the primary panel steady; the additional-display panel reveals on hover.
    panel.hiding = screenIndex === 0 ? "none" : "autohide";

    var order = screenIndex === 0 ? bladePrimaryOrder : bladeSecondaryOrder;
    order.forEach(function (type) {
        bladeConfigureWidget(bladeEnsureWidget(panel, type), type);
    });
}

function bladeScreenCount() {
    var count = 1;
    desktops().forEach(function (desktop) {
        count = Math.max(count, desktop.screen + 1);
    });
    panels().forEach(function (panel) {
        count = Math.max(count, panel.screen + 1);
    });
    return count;
}

var bladeCount = bladeScreenCount();
if (BLADE_REPLACE_EXISTING) {
    panels().forEach(function (panel) {
        panel.remove();
    });
    for (var bladeScreen = 0; bladeScreen < bladeCount; ++bladeScreen) {
        var bladePanel = new Panel;
        bladeConfigurePanel(bladePanel, bladeScreen);
    }
} else {
    for (var screenIndex = 0; screenIndex < bladeCount; ++screenIndex) {
        var candidates = panels().filter(function (panel) {
            return panel.screen === screenIndex;
        });
        var panel = candidates.length > 0 ? candidates[0] : new Panel;
        bladeConfigurePanel(panel, screenIndex);
    }
}

print("Blade panels: configured " + bladeCount + " display(s)");
