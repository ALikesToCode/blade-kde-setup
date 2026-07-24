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

var bladePinnedApplications = [
    "applications:org.kde.konsole.desktop",
    "applications:org.kde.dolphin.desktop",
    "applications:zen.desktop",
    "applications:dev.zed.Zed.desktop",
    "applications:antigravity.desktop",
    "applications:systemsettings.desktop"
];

var bladeEventCalendar = "org.kde.plasma.eventcalendar";
var bladeNetworkMonitor = "org.kde.plasma.systemmonitor.net";

var bladePrimaryOrder = [
    "org.kde.plasma.kickoff",
    "org.kde.plasma.icontasks",
    "org.kde.plasma.mediacontroller",
    "org.kde.plasma.systemmonitor.cpu",
    "org.kde.plasma.systemmonitor.memory",
    "org.kde.plasma.systemmonitor",
    bladeNetworkMonitor,
    "org.kde.plasma.pager",
    "org.kde.plasma.marginsseparator",
    "org.kde.plasma.systemtray",
    bladeEventCalendar,
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
    bladeNetworkMonitor,
    "org.kde.plasma.systemtray",
    bladeEventCalendar,
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

function bladePlaceWidgetAfter(panel, widget, anchorType) {
    if (!widget) {
        return;
    }

    var anchors = bladeWidgetsOfType(panel, anchorType);
    if (anchors.length === 0) {
        return;
    }

    panel.currentConfigGroup = ["General"];
    var storedOrder = panel.readConfig("AppletOrder", "");
    panel.currentConfigGroup = [];
    if (typeof storedOrder !== "string" || storedOrder.length === 0) {
        return;
    }

    var widgetId = String(widget.id);
    var anchorId = String(anchors[0].id);
    var order = storedOrder.split(";").filter(function (id) {
        return id.length > 0 && id !== widgetId;
    });
    var anchorIndex = order.indexOf(anchorId);
    if (anchorIndex === -1) {
        return;
    }

    order.splice(anchorIndex + 1, 0, widgetId);
    bladeWrite(panel, ["General"], {"AppletOrder": order.join(";")});
}

function bladeConfigureNetworkMonitor(widget) {
    if (!widget) {
        return;
    }

    var sensors = ["network/all/download", "network/all/upload"];
    bladeWrite(widget, [], {
        "CurrentPreset": "org.kde.plasma.systemmonitor",
        "highPrioritySensorIds": JSON.stringify(sensors),
        "lowPrioritySensorIds": JSON.stringify([]),
        "showTitle": false,
        "title": "Network Speed",
        "totalSensors": JSON.stringify([]),
        "updateRateLimit": 1000
    });
    bladeWrite(widget, ["Appearance"], {
        "chartFace": "org.kde.ksysguard.textonly",
        "title": "Network Speed"
    });
    bladeWrite(widget, ["FaceConfig"], {
        "groupByTotal": false
    });
    bladeWrite(widget, ["SensorColors"], {
        "network/all/download": "84,209,255",
        "network/all/upload": "129,201,149"
    });
    bladeWrite(widget, ["SensorLabels"], {
        "network/all/download": "DOWN",
        "network/all/upload": "UP"
    });
    bladeWrite(widget, ["Sensors"], {
        "highPrioritySensorIds": JSON.stringify(sensors),
        "lowPrioritySensorIds": JSON.stringify([]),
        "totalSensors": JSON.stringify([])
    });
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
        color = "138,180,248";
        lowSensors = ["cpu/all/averageTemperature", "cpu/all/averageFrequency", "cpu/all/coreCount"];
        label = "CPU";
    } else if (kind === "memory") {
        sensor = "memory/physical/used";
        title = "Memory Usage";
        color = "129,201,149";
        lowSensors = ["memory/physical/total", "memory/physical/application", "memory/physical/cache"];
        label = "RAM";
    } else {
        sensor = BLADE_GPU_PREFIX + "/usage";
        title = BLADE_GPU_TITLE;
        color = "84,209,255";
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
        "showTitle": false,
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
        "showLegend": false,
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
        bladeMergeList(widget, ["General"], "launchers", bladePinnedApplications);
        bladeWrite(widget, ["General"], {
            "groupingStrategy": 1,
            "indicateAudioStreams": true,
            "showOnlyCurrentActivity": false,
            "showOnlyCurrentDesktop": false,
            "showOnlyCurrentScreen": true,
            "wheelEnabled": true
        });
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
    } else if (type === bladeEventCalendar) {
        bladeWrite(widget, ["General"], {
            "pin": false,
            "widgetShowMeteogram": false,
            "widgetShowTimer": false,
            "widgetShowAgenda": true,
            "widgetShowCalendar": true,
            "clockFontFamily": "Noto Sans",
            "clockTimeFormat1": "HH:mm",
            "clockTimeFormat2": "ddd d MMM",
            "clockShowLine2": true,
            "clockLine2HeightRatio": 0.32,
            "clockLineBold1": true,
            "clockLineBold2": false,
            "clockMaxHeight": 44,
            "showOutlines": false,
            "showBackground": false,
            "topRowHeight": 96,
            "bottomRowHeight": 420,
            "leftColumnWidth": 380,
            "rightColumnWidth": 440
        });
        bladeWrite(widget, ["Calendar"], {
            "monthShowBorder": false,
            "monthShowWeekNumbers": false,
            "monthEventBadgeType": "dots",
            "monthTodayStyle": "theme",
            "monthCellRadius": 0.34,
            "monthHighlightCurrentDayWeek": true,
            "monthHeightSingleColumn": 320,
            "firstDayOfWeek": -1
        });
        bladeWrite(widget, ["Agenda"], {
            "twoColumns": true,
            "agendaWeatherOnRight": true,
            "agendaWeatherShowIcon": true,
            "agendaWeatherShowText": false,
            "agendaInProgressColor": "#81c995",
            "agendaDaySpacing": 16,
            "agendaEventSpacing": 8,
            "agendaMaxDescriptionLines": 3,
            "agendaShowEventDescription": true,
            "agendaCondensedAllDayEvent": true
        });
        bladeWrite(widget, ["Weather"], {
            "weatherUnits": "metric",
            "meteogramTextColor": "#f0f6fc",
            "meteogramGridColor": "#263b55",
            "meteogramRainColor": "#54d1ff",
            "meteogramPositiveTempColor": "#81c995",
            "meteogramNegativeTempColor": "#8ab4f8",
            "meteogramIconColor": "#8ab4f8"
        });
    } else if (type === bladeNetworkMonitor) {
        bladeConfigureNetworkMonitor(widget);
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
    panel.height = 52;
    panel.floating = true;
    panel.alignment = "center";
    panel.lengthMode = "fill";
    panel.opacity = "opaque";
    // Keep the primary panel steady; the additional-display panel reveals on hover.
    panel.hiding = screenIndex === 0 ? "none" : "autohide";

    var order = screenIndex === 0 ? bladePrimaryOrder : bladeSecondaryOrder;
    order.forEach(function (type) {
        var widget = bladeEnsureWidget(panel, type);
        bladeConfigureWidget(widget, type);
    });

    if (BLADE_REPLACE_CLOCK && bladeWidgetsOfType(panel, bladeEventCalendar).length > 0) {
        bladeWidgetsOfType(panel, "org.kde.plasma.digitalclock").forEach(function (widget) {
            widget.remove();
        });
    }
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

var bladePositionOnly = typeof BLADE_POSITION_ONLY !== "undefined" && BLADE_POSITION_ONLY;
var bladeCount = bladeScreenCount();
if (!bladePositionOnly) {
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
}

panels().forEach(function (panel) {
    var networkWidgets = bladeWidgetsOfType(panel, bladeNetworkMonitor);
    if (networkWidgets.length > 0) {
        bladePlaceWidgetAfter(panel, networkWidgets[0], "org.kde.plasma.systemmonitor");
    }
});

print(bladePositionOnly
    ? "Blade panels: positioned network speed beside telemetry"
    : "Blade panels: configured " + bladeCount + " display(s)");
